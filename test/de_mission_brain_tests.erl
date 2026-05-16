%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_mission_brain_tests).
-include_lib("eunit/include/eunit.hrl").

parse_json_payload_clean_test() ->
  Json = << "{\"response\": \"Hello\"}" >>,
  Result = de_mission_brain:parse_json_payload(Json),
  ?assertEqual(<<"Hello">>, maps:get(<<"response">>, Result)).

parse_json_payload_noisy_test() ->
  Json = << "Filler text { \"response\": \"Hello\" } more filler" >>,
  Result = de_mission_brain:parse_json_payload(Json),
  ?assertEqual(<<"Hello">>, maps:get(<<"response">>, Result)).

parse_json_payload_empty_test() ->
  Json = << "No JSON here" >>,
  Result = de_mission_brain:parse_json_payload(Json),
  ?assertEqual(#{}, Result).

analyze_llm_response_direct_test() ->
  Json = << "{\"delegate_required\": false, \"response\": \"Direct answer\"}" >>,
  Result = de_mission_brain:analyze_llm_response(Json, []),
  ?assertEqual({direct, <<"Direct answer">>}, Result).

analyze_llm_response_delegate_test() ->
  Json = << "{\"delegate_required\": true, \"response\": \"Thinking\", \"tool_intent\": \"k8s\", \"mcp_args\": {\"a\": 1}}" >>,
  Result = de_mission_brain:analyze_llm_response(Json, []),
  ?assertEqual({delegate, <<"k8s">>, #{<<"a">> => 1}, <<"Thinking">>}, Result).

build_new_context_sliding_window_test() ->
  Prev = [#{<<"role">> => <<"user">>, <<"content">> => <<X>>} || X <- lists:seq(1, 10)],
  New = de_mission_brain:build_new_context(<<"new prompt">>, <<"new response">>, Prev),
  ?assertEqual(10, length(New)),
  ?assertEqual(<<"new response">>, maps:get(<<"content">>, lists:last(New))).
