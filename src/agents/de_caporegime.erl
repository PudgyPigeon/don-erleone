%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_caporegime).

-behaviour(gen_server).
-behaviour(poolboy_worker).

-export([
  start_link/1,
  init/1,
  execute_mission/2,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2
]).

-record(de_caporegime_state, {
  config :: de_config:sub_config(),
  conn :: pid() | undefined
}).

-type state() :: #de_caporegime_state{}.

%% =============================================================================
%% Lifecycle & API
%% =============================================================================

-spec start_link([de_config:sub_config()]) -> {ok, pid()} | {error, term()}.
start_link([SubConfig]) ->
  gen_server:start_link(?MODULE, SubConfig, []).

-spec init(de_config:sub_config()) -> {ok, state()}.
init(SubConfig) ->
  %% Lazy Connection: don't block boot on MCP availability.
  {ok, #de_caporegime_state{config = SubConfig, conn = undefined}}.

%% =============================================================================
%% API
%% =============================================================================

-spec execute_mission(pid(), map()) -> term().
execute_mission(Worker, Spec) ->
  %% 300,000ms (5 minutes) timeout.
  gen_server:call(Worker, {execute_mission, Spec}, 300000).

-spec handle_call(term(), {pid(), term()}, state()) -> {reply, term(), state()}.
handle_call({execute_mission, Spec}, _From, State) ->
  Mid = maps:get(id, Spec),
  logger:info(#{event => de_caporegime_mission_start, mission_id => Mid}),
  de_store:update_status(Mid, in_progress),

  case ensure_conn(State) of
    {ok, NewState} ->
      Result = run_mission(Spec, NewState),
      finalize_mission(Spec, Result),
      {reply, Result, NewState};
    {error, Reason} ->
      logger:error(#{event => mcp_connection_failed, mission_id => Mid, error => Reason}),
      Result = {error, {infrastructure_down, Reason}},
      finalize_mission(Spec, Result),
      {reply, Result, State}
  end.

%% =============================================================================
%% Self-Healing Connection Manager
%% =============================================================================

-spec ensure_conn(state()) -> {ok, state()} | {error, term()}.
ensure_conn(#de_caporegime_state{conn = Conn} = State) when is_pid(Conn) ->
  case is_process_alive(Conn) of
    true -> {ok, State};
    false -> reconnect(State)
  end;
ensure_conn(State) ->
  reconnect(State).

-spec reconnect(state()) -> {ok, state()} | {error, term()}.
reconnect(State) ->
  State1 = close_old_conn(State),
  establish_mcp_conn(State1).

close_old_conn(#de_caporegime_state{conn = OldConn} = State) ->
  case OldConn of
    Pid when is_pid(Pid) -> gun:close(Pid);
    _ -> ok
  end,
  State#de_caporegime_state{conn = undefined}.

establish_mcp_conn(#de_caporegime_state{config = Conf} = State) ->
  URL = de_config:sub_config_mcp_url(Conf),
  {Host, Port} = parse_mcp_url(URL),
  logger:info(#{event => de_caporegime_connecting_mcp, host => Host, port => Port}),

  case gun:open(Host, Port, #{connect_timeout => 10000, protocols => [http]}) of
    {ok, Conn} -> wait_for_mcp_up(Conn, State);
    {error, Reason} -> {error, {gun_open_failed, Reason}}
  end.

parse_mcp_url(URL) ->
  #{host := H, port := P} = uri_string:parse(URL),
  Host = case is_binary(H) of
    true -> binary_to_list(H);
    false -> H
  end,
  {Host, P}.

wait_for_mcp_up(Conn, State) ->
  case gun:await_up(Conn, 10000) of
    {ok, _} ->
      logger:info(#{event => de_caporegime_connected}),
      {ok, State#de_caporegime_state{conn = Conn}};
    {error, Reason} ->
      gun:close(Conn),
      {error, {await_up_failed, Reason}}
  end.

%% =============================================================================
%% Mission Orchestration
%% =============================================================================

run_mission(Spec, State) ->
  case discover_tools(State) of
    {ok, Tools} ->
      logger:debug(#{event => tools_discovered, count => length(Tools)}),
      Prompt = de_agent_brain:build_sub_prompt(
        maps:get(intent, Spec),
        maps:get(prompt, Spec),
        Tools
      ),
      recursive_loop(Prompt, [], Tools, State, 0);
    {error, Reason} ->
      logger:error(#{event => tool_discovery_failed, error => Reason}),
      {error, {infrastructure_down, Reason}}
  end.

discover_tools(State) ->
  case mcp_call(<<"tools/list">>, #{}, State) of
    {ok, Body} -> de_agent_brain:decode_tools(Body);
    Error -> Error
  end.

%% =============================================================================
%% Reasoning Loop
%% =============================================================================

recursive_loop(Prompt, Context, Tools, State, Step) ->
  Max = de_config:sub_config_max_steps(State#de_caporegime_state.config),
  recursive_loop_guarded(Prompt, Context, Tools, State, Step, Max).

recursive_loop_guarded(_Prompt, _Context, _Tools, _State, Step, Max) when Step >= Max ->
  {error, recursion_limit};
recursive_loop_guarded(Prompt, Context, Tools, State, Step, _Max) ->
  logger:debug(#{event => de_caporegime_loop_step, step => Step}),
  case call_ollama(Prompt, Context, Tools, State) of
    {ok, Msg} ->
      process_llm_response(Msg, Context, Tools, State, Step);
    Error ->
      logger:error(#{event => de_caporegime_ollama_failed, error => Error}),
      Error
  end.

call_ollama(Prompt, Context, Tools, #de_caporegime_state{config = Conf}) ->
  OllamaOpts = #{
    url => de_config:sub_config_ollama_url(Conf),
    model => de_config:sub_config_model(Conf),
    timeout => de_config:sub_config_timeout(Conf),
    stream => false
  },
  de_ollama_client:generate_with_tools(Prompt, <<>>, Context, Tools, OllamaOpts).

process_llm_response(Msg, Context, Tools, State, Step) ->
  Decision = de_agent_brain:analyze_loop_step(Msg),
  handle_loop_decision(Decision, Msg, Context, Tools, State, Step).

handle_loop_decision({continue, Calls}, Msg, Context, Tools, State, Step) ->
  Results = [execute_tool(C, State) || C <- Calls],
  NextCtx = Context ++ [Msg#{<<"role">> => <<"assistant">>} | Results],
  Max = de_config:sub_config_max_steps(State#de_caporegime_state.config),
  check_loop_continuation(NextCtx, Tools, State, Step + 1, Max);
handle_loop_decision({stop, Response}, _Msg, _Context, _Tools, _State, _Step) ->
  {ok, #{response => Response}}.

check_loop_continuation(_NextCtx, _Tools, _State, Step, Max) when Step >= Max ->
  {ok, #{response => <<"I have executed the final tool call. Please check the logs.">>}};
check_loop_continuation(NextCtx, Tools, State, Step, _Max) ->
  recursive_loop(<<>>, NextCtx, Tools, State, Step).

%% =============================================================================
%% Tool Execution
%% =============================================================================

execute_tool(#{<<"function">> := #{<<"name">> := N, <<"arguments">> := A}}, State) ->
  Params = #{<<"name">> => N, <<"arguments">> => A},
  case mcp_call(<<"tools/call">>, Params, State) of
    {ok, Res} ->
      format_tool_response(N, extract_mcp_result(Res));
    {error, Reason} ->
      format_tool_response(N, iolist_to_binary(io_lib:format("Error: ~p", [Reason])))
  end.

format_tool_response(Name, Content) ->
  #{<<"role">> => <<"tool">>, <<"name">> => Name, <<"content">> => Content}.

extract_mcp_result(RawRes) ->
  try
    parse_mcp_body(jsx:decode(RawRes, [return_maps]), RawRes)
  catch _:_ -> RawRes end.

parse_mcp_body(#{<<"result">> := #{<<"content">> := List}}, RawRes) ->
  parse_content_list(List, RawRes);
parse_mcp_body(#{<<"error">> := #{<<"message">> := Msg}}, _RawRes) ->
  [<<"MCP Error: ">>, Msg];
parse_mcp_body(_, RawRes) ->
  RawRes.

parse_content_list(List, Fallback) ->
  Texts = [T || #{<<"type">> := <<"text">>, <<"text">> := T} <- List],
  case Texts of
    [] -> Fallback;
    _ -> lists:join(<<"\n">>, Texts)
  end.

%% =============================================================================
%% HTTP Transport
%% =============================================================================

mcp_call(Method, Params, #de_caporegime_state{config = Conf, conn = Conn}) ->
  {Headers, Payload} = de_agent_brain:prepare_mcp_request(Method, Params),
  URL = de_config:sub_config_mcp_url(Conf),
  #{path := Path} = uri_string:parse(URL),

  Ref = gun:post(Conn, Path, Headers, Payload),
  await_gun_response(Conn, Ref, de_config:sub_config_timeout(Conf)).

await_gun_response(Conn, Ref, Timeout) ->
  case gun:await(Conn, Ref, Timeout) of
    {response, nofin, 200, _} -> gun:await_body(Conn, Ref, Timeout);
    {response, _, Status, _} -> {error, {http_status, Status}};
    _ -> {error, timeout}
  end.

%% =============================================================================
%% Helpers & Cleanup
%% =============================================================================

finalize_mission(#{id := Mid, cowboy_from := From}, {ok, Data}) ->
  de_store:complete_mission(Mid, Data),
  safe_notify(From, {done, maps:get(response, Data), Mid});
finalize_mission(#{id := Mid, cowboy_from := From}, {error, R}) ->
  de_store:fail_mission(Mid, R),
  safe_notify(From, {error, R}).

safe_notify({Pid, Tag}, Msg) ->
  case is_process_alive(Pid) of
    true -> Pid ! {Tag, Msg}, ok;
    false -> ok
  end.

-spec terminate(term(), state()) -> ok.
terminate(_Reason, #de_caporegime_state{conn = Conn}) ->
  case Conn of
    Pid when is_pid(Pid) -> gun:close(Pid);
    _ -> ok
  end,
  ok.

-spec handle_cast(term(), state()) -> {noreply, state()}.
handle_cast(_, S) -> {noreply, S}.

-spec handle_info(term(), state()) -> {noreply, state()}.
handle_info(_, S) -> {noreply, S}.