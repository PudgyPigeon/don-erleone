%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_consigliere).

-export([handle_mission/3]).

%% =============================================================================
%% API: The Dispatcher (Imperative Shell)
%% =============================================================================

-spec handle_mission(binary(), binary(), {pid(), reference()}) -> ok.
handle_mission(SessionId, Prompt, CowboyFrom) ->
  %% We use proc_lib:spawn to ensure the process is integrated into OTP error logging
  proc_lib:spawn(fun() -> async_pool_consult(SessionId, Prompt, CowboyFrom) end),
  ok.

%% =============================================================================
%% Internal Helpers: Orchestration & Error Handling
%% =============================================================================

-spec async_pool_consult(binary(), binary(), {pid(), reference()}) -> term().
async_pool_consult(SessionId, Prompt, CowboyFrom) ->
  StartTime = erlang:system_time(microsecond),
  telemetry:execute([don_erleone, worker, execute, start], #{time => StartTime},
    #{session_id => SessionId, pool => de_consigliere_pool}),

  try
    Result = execute_transaction(SessionId, Prompt, CowboyFrom),
    report_success(SessionId, StartTime),
    Result
  catch
    Class:Reason:Stack ->
      handle_consult_fault(Class, Reason, Stack, SessionId, CowboyFrom, StartTime)
  end.

execute_transaction(SessionId, Prompt, CowboyFrom) ->
  poolboy:transaction(de_consigliere_pool, fun(Worker) ->
    de_consigliere_worker:consult(Worker, SessionId, Prompt, CowboyFrom)
  end).

report_success(SessionId, StartTime) ->
  telemetry:execute([don_erleone, worker, execute, stop],
    #{duration => erlang:system_time(microsecond) - StartTime},
    #{session_id => SessionId, pool => de_consigliere_pool}).

handle_consult_fault(exit, {timeout, _}, _Stack, Sid, From, Start) ->
  report_exception(Sid, pool_timeout, exit, Start),
  notify_client_of_failure(From, pool_overloaded);
handle_consult_fault(Class, Reason, Stack, Sid, From, Start) ->
  report_exception(Sid, Reason, Class, Start),
  logger:error(#{
    event => de_consigliere_dispatch_failed,
    session_id => Sid,
    class => Class,
    error => Reason,
    stack => Stack
  }),
  notify_client_of_failure(From, internal_service_error).

report_exception(Sid, Reason, Class, Start) ->
  telemetry:execute([don_erleone, worker, execute, exception],
    #{duration => erlang:system_time(microsecond) - Start},
    #{session_id => Sid, class => Class, reason => Reason}).

%% =============================================================================
%% Client Notification (Ensures Cowboy never hangs)
%% =============================================================================

-spec notify_client_of_failure({pid(), reference()}, term()) -> ok.
notify_client_of_failure({Pid, Tag}, Reason) ->
  %% Only send if the Cowboy process is still alive to receive it
  safe_notify(is_process_alive(Pid), Pid, Tag, Reason).

-spec safe_notify(boolean(), pid(), reference(), term()) -> ok.
safe_notify(true, Pid, Tag, Reason) ->
  Pid ! {Tag, {error, Reason}},
  ok;
safe_notify(false, Pid, _Tag, Reason) ->
  logger:warning(#{
    event => callback_delivery_failed,
    reason => Reason,
    target_pid => Pid
  }),
  ok.