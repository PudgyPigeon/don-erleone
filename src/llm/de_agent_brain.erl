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
analyze_loop_step(Msg) ->
  %% If the model gave us an answer, STOP.
  HasContent = maps:get(<<"content stream">>, Msg, maps:get(<<"content">>, Msg, <<>>)),
  HasTools = maps:get(<<"tool_calls">>, Msg, []),

  case {HasContent, HasTools} of
    {Content, _} when is_binary(Content), byte_size(Content) > 20 ->
      {stop, Content};
    {_, Calls} when is_list(Calls), length(Calls) > 0 ->
      {continue, Calls};
    {Content, _} when is_binary(Content), byte_size(Content) > 0 ->
      {stop, Content};
    _ ->
      {stop, <<"Mission complete or no further action required.">>}
  end.

-spec decode_tools(term()) -> {ok, list()} | {error, term()}.
decode_tools(Body) ->
  try
    Decoded = jsx:decode(to_bin(Body), [return_maps]),
    case Decoded of
      #{<<"result">> := #{<<"tools">> := Tools}} -> {ok, Tools};
      #{<<"tools">> := Tools} -> {ok, Tools};
      _ -> {error, {bad_structure, Decoded}}
    end
  catch
    _:_ -> {error, json_invalid}
  end.

-spec build_sub_prompt(binary(), binary(), list()) -> binary().
build_sub_prompt(Intent, Goal, Tools) ->
  ValidNames = [maps:get(<<"name">>, T) || T <- Tools],
  NamesBin = lists:join(<<", ">>, ValidNames),
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

-spec to_bin(term()) -> binary().
to_bin(B) when is_binary(B) -> B;
to_bin(V) -> iolist_to_binary(io_lib:format("~p", [V])).