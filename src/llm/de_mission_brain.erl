%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_mission_brain).

-export([
  analyze_llm_response/2,
  parse_json_payload/1,
  build_new_context/3
]).

%% =============================================================================
%% API
%% =============================================================================

%% @doc Determines if the LLM output requires delegation or a direct response.
-spec analyze_llm_response(binary(), list()) ->
  {delegate, binary(), map(), binary()} | {direct, binary()}.
analyze_llm_response(RawBin, _PrevContext) ->
  Parsed = parse_json_payload(RawBin),

  %% Extract fields with default fallbacks
  ResponseRaw = maps:get(<<"response">>, Parsed, RawBin),
  Response = to_bin(ResponseRaw),
  DelegateRaw = maps:get(<<"delegate_required">>, Parsed, false),
  Delegate = (DelegateRaw =:= true) orelse
    (DelegateRaw =:= <<"true">>) orelse
    (DelegateRaw =:= "true"),
  Intent = maps:get(<<"tool_intent">>, Parsed, <<"autonomous">>),
  Args = maps:get(<<"mcp_args">>, Parsed, #{}),

  case Delegate of
    true ->
      {delegate, Intent, Args, Response};
    false ->
      {direct, Response}
  end.

%% @doc Robust JSON extraction. Filters out conversational "noise" around the JSON block.
-spec parse_json_payload(binary()) -> map().
parse_json_payload(Bin) ->
  %% Look for the first '{' and last '}' to handle LLM conversational filler
  case re:run(Bin, <<"{.*}">>, [dotall, {capture, first, binary}]) of
    {match, [JsonOnly]} ->
      try jsx:decode(JsonOnly, [return_maps])
      catch _:_ -> #{} end;
    nomatch ->
      #{}
  end.

%% @doc Manages a sliding window of conversation history.
-spec build_new_context(binary(), binary(), list()) -> list().
build_new_context(Prompt, Response, Prev) ->
  New = Prev ++ [
    #{<<"role">> => <<"user">>, <<"content">> => to_bin(Prompt)},
    #{<<"role">> => <<"assistant">>, <<"content">> => to_bin(Response)}
  ],
  %% Sliding window: Keep only the last 10 messages (5 rounds)
  case length(New) > 10 of
    true -> lists:nthtail(length(New) - 10, New);
    false -> New
  end.

%% =============================================================================
%% Internals
%% =============================================================================

-spec to_bin(term()) -> binary().
to_bin(B) when is_binary(B) -> B;
to_bin(Any) -> iolist_to_binary(io_lib:format("~p", [Any])).