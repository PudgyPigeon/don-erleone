%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_caporegime).

-behaviour(gen_server).

-behaviour(poolboy_worker).

-export([start_link/1,
         init/1,
         execute_mission/2,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2]).

-ifdef(TEST).

-export([check_conn_alive/2, parse_mcp_body/1]).

-endif.

-record(de_caporegime_state,
        {config :: de_config:sub_config(),
         conn :: pid() | undefined}).

-type state() :: #de_caporegime_state{}.

%% =============================================================================
%% Lifecycle & API
%% =============================================================================

-spec start_link([de_config:sub_config()]) -> {ok,
                                               pid()} |
                                              {error, term()}.

start_link([SubConfig]) ->
    gen_server:start_link(?MODULE, SubConfig, []).

-spec init(de_config:sub_config()) -> {ok, state()}.

init(SubConfig) ->
    %% Lazy Connection: don't block boot on MCP availability.
    {ok,
     #de_caporegime_state{config = SubConfig,
                          conn = undefined}}.

%% =============================================================================
%% API
%% =============================================================================

-spec execute_mission(pid(), map()) -> term().

execute_mission(Worker, Spec) ->
    %% 300,000ms (5 minutes) timeout.
    gen_server:call(Worker,
                    {execute_mission, Spec},
                    300000).

-spec handle_call(term(), {pid(), term()},
                  state()) -> {reply, term(), state()}.

handle_call({execute_mission, Spec}, _From, State) ->
    Mid = maps:get(id, Spec),
    logger:info(#{event => de_caporegime_mission_start,
                  mission_id => Mid}),
    de_store:update_status(Mid, in_progress),
    handle_conn_check(ensure_conn(State), Spec).

-spec handle_conn_check({ok, state()} | {error, term()},
                        map()) -> {reply, term(), state()}.

handle_conn_check({ok, NewState}, Spec) ->
    Result = run_mission(Spec, NewState),
    finalize_mission(Spec, Result),
    {reply, Result, NewState};
handle_conn_check({error, Reason}, Spec) ->
    Mid = maps:get(id, Spec),
    logger:error(#{event => mcp_connection_failed,
                   mission_id => Mid, error => Reason}),
    Result = {error, {infrastructure_down, Reason}},
    finalize_mission(Spec, Result),
    {reply, Result, undefined}.

%% =============================================================================
%% Self-Healing Connection Manager
%% =============================================================================

-spec ensure_conn(state() | undefined) -> {ok,
                                           state()} |
                                          {error, term()}.

ensure_conn(#de_caporegime_state{conn = Conn} = State)
    when is_pid(Conn) ->
    check_conn_alive(is_process_alive(Conn), State);
ensure_conn(State) -> reconnect(State).

-spec check_conn_alive(boolean(), state()) -> {ok,
                                               state()} |
                                              {error, term()}.

check_conn_alive(true, State) -> {ok, State};
check_conn_alive(false, State) -> reconnect(State).

-spec reconnect(state()) -> {ok, state()} |
                            {error, term()}.

reconnect(State) ->
    establish_mcp_conn(close_old_conn(State)).

-spec close_old_conn(state()) -> state().

close_old_conn(#de_caporegime_state{conn = OldConn} =
                   State)
    when is_pid(OldConn) ->
    gun:close(OldConn),
    State#de_caporegime_state{conn = undefined};
close_old_conn(State) ->
    State#de_caporegime_state{conn = undefined}.

-spec establish_mcp_conn(state()) -> {ok, state()} |
                                     {error, term()}.

establish_mcp_conn(#de_caporegime_state{config = Conf} =
                       State) ->
    {Host, Port} =
        parse_mcp_url(de_config:sub_config_mcp_url(Conf)),
    logger:info(#{event => de_caporegime_connecting_mcp,
                  host => Host, port => Port}),
    handle_gun_open(gun:open(Host,
                             Port,
                             #{connect_timeout => 10000, protocols => [http]}),
                    State).

-spec handle_gun_open({ok, pid()} | {error, term()},
                      state()) -> {ok, state()} | {error, term()}.

handle_gun_open({ok, Conn}, State) ->
    wait_for_mcp_up(Conn, State);
handle_gun_open({error, Reason}, _State) ->
    {error, {gun_open_failed, Reason}}.

-spec parse_mcp_url(string()) -> {string(), integer()}.

parse_mcp_url(URL) ->
    #{host := H, port := P} = uri_string:parse(URL),
    {to_list(H), P}.

-spec wait_for_mcp_up(pid(), state()) -> {ok, state()} |
                                         {error, term()}.

wait_for_mcp_up(Conn, State) ->
    handle_await_up(gun:await_up(Conn, 10000), Conn, State).

-spec handle_await_up({ok, atom()} | {error, term()},
                      pid(), state()) -> {ok, state()} | {error, term()}.

handle_await_up({ok, _}, Conn, State) ->
    logger:info(#{event => de_caporegime_connected}),
    {ok, State#de_caporegime_state{conn = Conn}};
handle_await_up({error, Reason}, Conn, _State) ->
    gun:close(Conn),
    {error, {await_up_failed, Reason}}.

%% =============================================================================
%% Mission Orchestration
%% =============================================================================

-spec run_mission(map(), state()) -> {ok, map()} |
                                     {error, term()}.

run_mission(Spec, State) ->
    handle_discovery(discover_tools(State), Spec, State).

-spec handle_discovery({ok, list()} | {error, term()},
                       map(), state()) -> {ok, map()} | {error, term()}.

handle_discovery({ok, Tools}, Spec, State) ->
    logger:debug(#{event => tools_discovered,
                   count => length(Tools)}),
    Prompt =
        de_agent_brain:build_sub_prompt(maps:get(intent, Spec),
                                        maps:get(prompt, Spec),
                                        Tools),
    recursive_loop(Prompt, [], Tools, State, 0);
handle_discovery({error, Reason}, _Spec, _State) ->
    logger:error(#{event => tool_discovery_failed,
                   error => Reason}),
    {error, {infrastructure_down, Reason}}.

-spec discover_tools(state()) -> {ok, list()} |
                                 {error, term()}.

discover_tools(State) ->
    handle_tool_list(mcp_call(<<"tools/list">>,
                              #{},
                              State)).

-spec handle_tool_list({ok, binary()} |
                       {error, term()}) -> {ok, list()} | {error, term()}.

handle_tool_list({ok, Body}) ->
    de_agent_brain:decode_tools(Body);
handle_tool_list(Error) -> Error.

%% =============================================================================
%% Reasoning Loop
%% =============================================================================

-spec recursive_loop(binary(), list(), list(), state(),
                     integer()) -> {ok, map()} | {error, term()}.

recursive_loop(Prompt, Context, Tools, State, Step) ->
    Max =
        de_config:sub_config_max_steps(State#de_caporegime_state.config),
    execute_loop_step(Step,
                      Max,
                      Prompt,
                      Context,
                      Tools,
                      State).

-spec execute_loop_step(integer(), integer(), binary(),
                        list(), list(), state()) -> {ok, map()} |
                                                    {error, term()}.

execute_loop_step(Step, Max, _P, _C, _T, _S)
    when Step >= Max ->
    {error, recursion_limit};
execute_loop_step(Step, _Max, Prompt, Context, Tools,
                  State) ->
    logger:debug(#{event => de_caporegime_loop_step,
                   step => Step}),
    try handle_ollama_step(call_ollama(Prompt,
                                       Context,
                                       Tools,
                                       State),
                           Context,
                           Tools,
                           State,
                           Step)
    catch
        Class:Reason:Stack ->
            logger:error(#{event => de_caporegime_loop_crash,
                           step => Step, class => Class, reason => Reason,
                           stack => Stack}),
            {error, {loop_crash, Reason}}
    end.

-spec handle_ollama_step({ok, map()} | {error, term()},
                         list(), list(), state(), integer()) -> {ok, map()} |
                                                                {error, term()}.

handle_ollama_step({ok, Data}, Context, Tools, State,
                   Step) ->
    process_llm_response(Data, Context, Tools, State, Step);
handle_ollama_step(Error, _Ctx, _Tools, _State,
                   _Step) ->
    logger:error(#{event => de_caporegime_ollama_failed,
                   error => Error}),
    Error.

-spec process_llm_response(map(), list(), list(),
                           state(), integer()) -> {ok, map()} | {error, term()}.

process_llm_response(Msg, Context, Tools, State,
                     Step) ->
    handle_loop_decision(de_agent_brain:analyze_loop_step(Msg),
                         Msg,
                         Context,
                         Tools,
                         State,
                         Step).

-spec handle_loop_decision({stop, binary()} |
                           {continue, list()},
                           map(), list(), list(), state(), integer()) -> {ok,
                                                                          map()} |
                                                                         {error, term()}.

handle_loop_decision({continue, Calls}, Msg, Context,
                     Tools, State, Step) ->
    Results = [execute_tool(C, State) || C <- Calls],
    NextCtx = Context ++
                  [Msg#{<<"role">> => <<"assistant">>} | Results],
    check_continuation(NextCtx, Tools, State, Step + 1);
handle_loop_decision({stop, Response}, _Msg, _Context,
                     _Tools, _State, _Step) ->
    {ok, #{response => Response}}.

-spec check_continuation(list(), list(), state(),
                         integer()) -> {ok, map()} | {error, term()}.

check_continuation(_NextCtx, _Tools, State, Step) ->
    Max =
        de_config:sub_config_max_steps(State#de_caporegime_state.config),
    decide_continuation(Step >= Max,
                        _NextCtx,
                        _Tools,
                        State,
                        Step).

-spec decide_continuation(boolean(), list(), list(),
                          state(), integer()) -> {ok, map()} | {error, term()}.

decide_continuation(true, _Ctx, _T, _S, _Step) ->
    {ok,
     #{response =>
           <<"I have executed the final tool call. "
             "Please check the logs.">>}};
decide_continuation(false, NextCtx, Tools, State,
                    Step) ->
    recursive_loop(<<>>, NextCtx, Tools, State, Step).

-spec call_ollama(binary(), list(), list(),
                  state()) -> {ok, map()} | {error, term()}.

call_ollama(Prompt, Context, Tools,
            #de_caporegime_state{config = Conf}) ->
    OllamaOpts = #{url =>
                       de_config:sub_config_ollama_url(Conf),
                   model => de_config:sub_config_model(Conf),
                   timeout => de_config:sub_config_timeout(Conf),
                   stream => false},
    de_ollama_client:generate_with_tools(<<>>,
                                         Prompt,
                                         Context,
                                         Tools,
                                         OllamaOpts).

%% =============================================================================
%% Tool Execution
%% =============================================================================

-spec execute_tool(map(), state()) -> map().

execute_tool(#{<<"id">> := Id,
               <<"function">> :=
                   #{<<"name">> := N, <<"arguments">> := A}},
             State) ->
    Params = #{<<"name">> => N, <<"arguments">> => A},
    handle_tool_call(mcp_call(<<"tools/call">>,
                              Params,
                              State),
                     N,
                     Id).

-spec handle_tool_call({ok, binary()} | {error, term()},
                       binary(), binary()) -> map().

handle_tool_call({ok, Res}, Name, Id) ->
    format_tool_response(Name, Id, extract_mcp_result(Res));
handle_tool_call({error, Reason}, Name, Id) ->
    format_tool_response(Name,
                         Id,
                         iolist_to_binary(io_lib:format("Error: ~p", [Reason]))).

-spec format_tool_response(binary(), binary(),
                           binary()) -> map().

format_tool_response(Name, Id, Content) ->
    #{<<"role">> => <<"tool">>, <<"name">> => Name,
      <<"content">> => Content, <<"tool_call_id">> => Id}.

-spec extract_mcp_result(binary()) -> binary().

extract_mcp_result(Raw) ->
    handle_mcp_decode(safe_jsx_decode(Raw), Raw).

-spec safe_jsx_decode(binary()) -> {ok, term()} |
                                   {error, decode_failed}.

safe_jsx_decode(Raw) ->
    try {ok, jsx:decode(Raw, [return_maps])} catch
        _:_ -> {error, decode_failed}
    end.

-spec handle_mcp_decode({ok, term()} | {error, term()},
                        binary()) -> binary().

handle_mcp_decode({ok, Decoded}, _Raw) ->
    parse_mcp_body(Decoded);
handle_mcp_decode({error, _}, Raw) -> Raw.

-spec parse_mcp_body(map() | term()) -> binary() |
                                        term().

parse_mcp_body(#{<<"result">> :=
                     #{<<"content">> := List}}) ->
    parse_content_list(List);
parse_mcp_body(#{<<"error">> :=
                     #{<<"message">> := Msg}}) ->
    [<<"MCP Error: ">>, Msg];
parse_mcp_body(Other) -> Other.

-spec parse_content_list(list()) -> binary().

parse_content_list(List) ->
    Texts = [T
             || #{<<"type">> := <<"text">>, <<"text">> := T}
                    <- List],
    format_content_texts(Texts).

-spec format_content_texts(list()) -> binary().

format_content_texts([]) ->
    <<"No text response from tool.">>;
format_content_texts(Texts) ->
    iolist_to_binary(lists:join(<<"\n">>, Texts)).

%% =============================================================================
%% HTTP Transport
%% =============================================================================

-spec mcp_call(binary(), map(), state()) -> {ok,
                                             binary()} |
                                            {error, term()}.

mcp_call(Method, Params,
         #de_caporegime_state{config = Conf, conn = Conn}) ->
    {Headers, Payload} =
        de_agent_brain:prepare_mcp_request(Method, Params),
    #{path := Path} =
        uri_string:parse(de_config:sub_config_mcp_url(Conf)),
    Ref = gun:post(Conn, Path, Headers, Payload),
    await_gun_response(Conn,
                       Ref,
                       de_config:sub_config_timeout(Conf)).

-spec await_gun_response(pid(), reference(),
                         integer()) -> {ok, binary()} | {error, term()}.

await_gun_response(Conn, Ref, Timeout) ->
    handle_gun_await(gun:await(Conn, Ref, Timeout),
                     Conn,
                     Ref,
                     Timeout).

-spec handle_gun_await(term(), pid(), reference(),
                       integer()) -> {ok, binary()} | {error, term()}.

handle_gun_await({response, nofin, 200, _}, Conn, Ref,
                 Timeout) ->
    gun:await_body(Conn, Ref, Timeout);
handle_gun_await({response, _, Status, _}, _Conn, _Ref,
                 _Timeout) ->
    {error, {http_status, Status}};
handle_gun_await(Error, _Conn, _Ref, _Timeout) ->
    {error, Error}.

%% =============================================================================
%% Helpers & Cleanup
%% =============================================================================

-spec finalize_mission(map(),
                       {ok, map()} | {error, term()}) -> ok.

finalize_mission(#{id := Mid, cowboy_from := From},
                 {ok, Data}) ->
    de_store:complete_mission(Mid, Data),
    safe_notify(From,
                {done, maps:get(response, Data), Mid});
finalize_mission(#{id := Mid, cowboy_from := From,
                   session_id := Sid},
                 {error, R}) ->
    de_store:fail_mission(Mid, R),
    de_consigliere:handle_system_error(Sid, R, From).

-spec safe_notify({pid(), reference()}, term()) -> ok.

safe_notify({Pid, Tag}, Msg) ->
    do_safe_notify(is_process_alive(Pid), Pid, Tag, Msg).

-spec do_safe_notify(boolean(), pid(), reference(),
                     term()) -> ok.

do_safe_notify(true, Pid, Tag, Msg) ->
    Pid ! {Tag, Msg},
    ok;
do_safe_notify(false, _Pid, _Tag, _Msg) -> ok.

-spec to_list(term()) -> string().

to_list(B) when is_binary(B) -> binary_to_list(B);
to_list(L) when is_list(L) -> L;
to_list(Any) ->
    lists:flatten(io_lib:format("~s", [Any])).

-spec terminate(term(), state()) -> ok.

terminate(_Reason, #de_caporegime_state{conn = Conn}) ->
    case Conn of
        Pid when is_pid(Pid) -> gun:close(Pid);
        _ -> ok
    end,
    ok.

-spec handle_cast(term(), state()) -> {noreply,
                                       state()}.

handle_cast(_, S) -> {noreply, S}.

-spec handle_info(term(), state()) -> {noreply,
                                       state()}.

handle_info(_, S) -> {noreply, S}.
