%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_underboss_tests).

-include_lib("eunit/include/eunit.hrl").

-spec dispatch_mission_test_() -> term().

dispatch_mission_test_() ->
    {foreach,
     fun setup/0,
     fun teardown/1,
     [fun (Arg) ->
              ?_test((test_mission_failed_db_update(Arg)))
      end,
      fun (Arg) ->
              ?_test((test_mission_failed_graceful_recovery(Arg)))
      end]}.

-spec setup() -> ok.

setup() ->
    {ok, _} = application:ensure_all_started(telemetry),
    de_telemetry:setup(),
    meck:unload(), %% Ensure clean slate
    meck:new(poolboy, [non_strict]),
    meck:new(de_store, [non_strict]),
    meck:new(de_consigliere, [non_strict]),
    meck:new(logger, [unstick, passthrough]),
    meck:expect(logger,
                error,
                fun (_Format, _Args) -> ok end),
    ok.

-spec teardown(term()) -> ok.

teardown(_) ->
    meck:unload(logger),
    meck:unload(poolboy),
    meck:unload(de_store),
    meck:unload(de_consigliere).

-spec test_mission_failed_db_update(term()) -> ok.

test_mission_failed_db_update(_) ->
    TestPid = self(),
    meck:expect(poolboy,
                transaction,
                fun (_, _) -> erlang:error(simulated_exhaustion) end),
    meck:expect(de_store,
                fail_mission,
                fun (Id, Reason) ->
                        TestPid ! {failed, Id, Reason},
                        ok
                end),
    Mission = #{id => 999, intent => <<"test">>,
                session_id => <<"test_sid">>,
                cowboy_from => {TestPid, make_ref()}},
    de_underboss:dispatch_mission(Mission),

    receive
        {failed,
         999,
         {execution_error, simulated_exhaustion}} ->
            ok
        after 1000 -> erlang:error(timeout_db_update)
    end.

-spec
     test_mission_failed_graceful_recovery(term()) -> ok.

test_mission_failed_graceful_recovery(_) ->
    TestPid = self(),
    Tag = make_ref(),
    meck:expect(poolboy,
                transaction,
                fun (_, _) -> erlang:error(simulated_exhaustion) end),
    meck:expect(de_store,
                fail_mission,
                fun (_, _) -> ok end),
    %% Expect de_consigliere:handle_system_error to be called
    meck:expect(de_consigliere,
                handle_system_error,
                fun (Sid, Reason, {_P, T}) ->
                        TestPid ! {graceful, Sid, Reason, T},
                        ok
                end),
    Mission = #{id => 999, intent => <<"test">>,
                session_id => <<"test_sid">>,
                cowboy_from => {TestPid, Tag}},
    de_underboss:dispatch_mission(Mission),

    receive
        {graceful, <<"test_sid">>, simulated_exhaustion, Tag} ->
            ok
        after 1000 ->
                  erlang:error(timeout_graceful_recovery_notification)
    end.
