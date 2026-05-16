%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_consigliere_worker).

-behaviour(gen_server).
-behaviour(poolboy_worker).

-export([
  start_link/1,
  consult/4,
  init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2
]).

-record(de_consigliere_worker_state, {
  config :: de_config:config()
}).

-type state() :: #de_consigliere_worker_state{}.

%% =============================================================================
%% Lifecycle
%% =============================================================================

-spec start_link([de_config:config()]) -> {ok, pid()} | {error, term()}.
start_link([Config]) ->
  gen_server:start_link(?MODULE, Config, []).

-spec init(de_config:config()) -> {ok, state()}.
init(Config) ->
  {ok, #de_consigliere_worker_state{config = Config}}.

%% =============================================================================
%% API
%% =============================================================================

-spec consult(pid(), binary(), binary(), {pid(), reference()}) -> ok | {error, term()}.
consult(Worker, SessionId, Prompt, CowboyFrom) ->
  %% infinity is used because Ollama generation can take 60s+
  gen_server:call(Worker, {consult, SessionId, Prompt, CowboyFrom}, infinity).

%% =============================================================================
%% Orchestration
%% =============================================================================

-spec handle_call(term(), {pid(), term()}, state()) -> {reply, term(), state()}.
handle_call({consult, Sid, Prompt, From}, _From, State) ->
  logger:debug(#{event => worker_consult_start, session_id => Sid}),
  try
    execute_consultation(Sid, Prompt, From, State)
  catch
    _:Error:Stack ->
      handle_worker_fault(Error, Stack, Sid, From, State)
  end.

execute_consultation(Sid, Prompt, From, State) ->
  Config = State#de_consigliere_worker_state.config,
  Context = de_store:get_latest_context(Sid),
  handle_ollama_result(call_ollama(Prompt, Context, Config), Sid, Prompt, Context, From, State).

handle_ollama_result({ok, Data}, Sid, Prompt, Context, From, State) ->
  Raw = extract_raw(Data),
  process_decision(Sid, Prompt, Raw, Context, From, State);
handle_ollama_result({error, Reason}, Sid, _Prompt, _Context, From, State) ->
  logger:error(#{event => ollama_call_failed, session_id => Sid, error => Reason}),
  notify_error(From, Reason),
  {reply, {error, Reason}, State}.

handle_worker_fault(Error, Stack, Sid, From, State) ->
  logger:error(#{event => worker_crash, session_id => Sid, error => Error, stack => Stack}),
  notify_error(From, worker_fault),
  {reply, {error, Error}, State}.

%% =============================================================================
%% Decision Flow
%% =============================================================================

process_decision(Sid, Prompt, Raw, PrevCtx, From, State) ->
  Decision = de_mission_brain:analyze_llm_response(Raw, PrevCtx),
  NewCtx = de_mission_brain:build_new_context(Prompt, Raw, PrevCtx),
  handle_decision(Decision, Sid, Prompt, NewCtx, From, State).

handle_decision({delegate, Intent, Args, Msg}, Sid, Prompt, NewCtx, From, State) ->
  logger:info(#{event => decision_delegate, session_id => Sid, intent => Intent}),
  Data = {chunk, [<<"\n">>, Msg, <<"\n">>]},
  finalize_decision(Sid, Intent, Prompt, NewCtx, From, State, Data, Args);
handle_decision({direct, Msg}, Sid, Prompt, NewCtx, From, State) ->
  logger:info(#{event => decision_direct, session_id => Sid}),
  finalize_decision(Sid, <<"direct">>, Prompt, NewCtx, From, State, {done, Msg}, undefined).

finalize_decision(Sid, Intent, Prompt, NewCtx, From, State, MsgData, Args) ->
  Result = de_store:post_mission(Sid, Intent, Prompt, NewCtx),
  handle_storage_result(Result, Sid, Intent, Prompt, From, State, MsgData, Args).

handle_storage_result({ok, Mid}, Sid, Intent, Prompt, From, State, MsgData, Args) ->
  dispatch_result(From, MsgData, Mid, Intent, Args, Prompt, State);
handle_storage_result({error, Reason}, Sid, _Intent, _Prompt, From, State, _MsgData, _Args) ->
  logger:error(#{event => de_store_failed, session_id => Sid, error => Reason}),
  notify_error(From, Reason),
  {reply, {error, Reason}, State}.

dispatch_result(From, {Tag, Content}, Mid, <<"direct">>, _Args, _Prompt, State) ->
  safe_send(From, {Tag, Content, Mid}),
  {reply, ok, State};
dispatch_result(From, {Tag, Content}, Mid, Intent, Args, Prompt, State) ->
  safe_send(From, {Tag, Content, Mid}),
  de_underboss:dispatch_mission(#{
    id => Mid,
    intent => Intent,
    args => Args,
    prompt => Prompt,
    cowboy_from => From
  }),
  {reply, ok, State}.

%% =============================================================================
%% Infrastructure Helpers
%% =============================================================================

call_ollama(Prompt, Context, Config) ->
  de_ollama_client:generate(Prompt,
    de_config:config_system_prompt(Config),
    Context,
    #{
      url => de_config:config_ollama_url(Config),
      model => de_config:config_model(Config),
      timeout => de_config:config_timeout(Config),
      stream => de_config:config_stream(Config)
    }).

safe_send({Pid, Tag}, Msg) ->
  do_safe_send(is_process_alive(Pid), Pid, Tag, Msg).

do_safe_send(true, Pid, Tag, Msg) ->
  Pid ! {Tag, Msg}, ok;
do_safe_send(false, Pid, _Tag, Msg) ->
  logger:warning(#{event => cowboy_dead_drop, target_pid => Pid, message => Msg}), ok.

notify_error({Pid, Tag}, Reason) ->
  do_notify_error(is_process_alive(Pid), Pid, Tag, Reason).

do_notify_error(true, Pid, Tag, Reason) ->
  Pid ! {Tag, {error, Reason}}, ok;
do_notify_error(false, _Pid, _Tag, _Reason) ->
  ok.

extract_raw(Data) when is_list(Data) ->
  extract_raw(iolist_to_binary(Data));
extract_raw(Data) ->
  do_extract_raw(Data).

do_extract_raw(#{<<"message">> := #{<<"content">> := C}}) -> C;
do_extract_raw(#{<<"content">> := C}) -> C;
do_extract_raw(#{<<"response">> := C}) -> C;
do_extract_raw(C) when is_binary(C) -> C;
do_extract_raw(Unknown) ->
  logger:warning(#{event => unknown_ollama_response_format, data => Unknown}),
  <<"error">>.

-spec handle_cast(term(), state()) -> {noreply, state()}.
handle_cast(_, S) -> {noreply, S}.

-spec handle_info(term(), state()) -> {noreply, state()}.
handle_info(_, S) -> {noreply, S}.