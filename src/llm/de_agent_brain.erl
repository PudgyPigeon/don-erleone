%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_agent_brain).

-define(MCP_VERSION, <<"2025-06-18">>).
-define(JSONRPC_VER, <<"2.0">>).

-export([
  analyze_loop_step/1,
  decode_tools/1,
  build_sub_prompt/3,
  prepare_mcp_request/2
]).

%% =============================================================================
%% MCP Protocol
%% =============================================================================

-spec prepare_mcp_request(binary() | string(), map()) -> {list(), binary()}.
prepare_mcp_request(Method, Params) ->
  Headers = [
    {<<"Content-Type">>, <<"application/json">>},
    {<<"Mcp-Protocol-Version">>, ?MCP_VERSION}
  ],

  %% Standard MCP tools/call structure
  Payload = #{
    <<"jsonrpc">> => ?JSONRPC_VER,
    <<"id">> => 1,
    <<"method">> => to_bin(Method),
    <<"params">> => Params
  },
  {Headers, jsx:encode(Payload)}.

%% =============================================================================
%% Logic
%% =============================================================================

-spec analyze_loop_step(map()) -> {stop, binary()} | {continue, list()}.
%% Priority 1: Tool calls always take precedence if present
analyze_loop_step(#{<<"tool_calls">> := Calls}) when is_list(Calls), length(Calls) > 0 ->
  {continue, Calls};
%% Priority 2: Evaluate content
analyze_loop_step(Msg) ->
  Content = extract_content(Msg),
  evaluate_content(Content).

-spec evaluate_content(binary()) -> {stop, binary()}.
evaluate_content(<<>>) ->
  {stop, <<"Mission complete or no further action required.">>};
evaluate_content(Content) ->
  {stop, Content}.

-spec extract_content(map()) -> binary().
extract_content(Msg) ->
  maps:get(<<"content stream">>, Msg, maps:get(<<"content">>, Msg, <<>>)).

-spec decode_tools(term()) -> {ok, list()} | {error, term()}.
decode_tools(Body) ->
  case safe_decode(Body) of
    {ok, Decoded} -> extract_tools_list(Decoded);
    {error, _} = Err -> Err
  end.

-spec safe_decode(term()) -> {ok, map()} | {error, json_invalid}.
safe_decode(Body) ->
  try
    {ok, jsx:decode(to_bin(Body), [return_maps])}
  catch
    _:_ -> {error, json_invalid}
  end.

-spec extract_tools_list(map()) -> {ok, list()} | {error, term()}.
extract_tools_list(#{<<"result">> := #{<<"tools">> := Tools}}) -> {ok, Tools};
extract_tools_list(#{<<"tools">> := Tools}) -> {ok, Tools};
extract_tools_list(Other) -> {error, {bad_structure, Other}}.

-spec build_sub_prompt(binary(), binary(), list()) -> list().
build_sub_prompt(Intent, Goal, Tools) ->
  NamesBin = format_tool_names(Tools),
  [
    "SYSTEM: You are a Senior AI Infrastructure Engineer.\n",
    "STRICT PROTOCOL: You may ONLY use these tools: ", NamesBin, "\n\n",
    "MISSION RULES:\n",
    "1. One-Stop Completion: If the goal is to list something, call the tool ONCE.\n",
    "2. Immediate Exit: Once you see the tool output in the history, you MUST provide the final answer.\n",
    "3. No Scope Creep: Do not check pods or deployments unless explicitly asked.\n",
    "4. Stop Token: You must finish your response with a final summary.\n\n",
    "GOAL: ", Goal, "\n",
    "INTENT: ", Intent
  ].

-spec format_tool_names(list()) -> iolist().
format_tool_names(Tools) ->
  Names = [maps:get(<<"name">>, T) || T <- Tools],
  lists:join(<<", ">>, Names).

-spec to_bin(term()) -> binary().
to_bin(B) when is_binary(B) -> B;
to_bin(V) -> iolist_to_binary(io_lib:format("~p", [V])).