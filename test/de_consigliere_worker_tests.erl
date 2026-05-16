%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_consigliere_worker_tests).

-include_lib("eunit/include/eunit.hrl").

%% We test the logic that moved to de_mission_brain
-spec parse_json_payload_test() -> ok.

parse_json_payload_test() ->
    ?assertEqual((#{}),
                 (de_mission_brain:parse_json_payload(<<>>))),
    ?assertEqual((#{}),
                 (de_mission_brain:parse_json_payload(<<"not json">>))),
    ValidJson = <<"{\"key\": \"value\"}">>,
    ?assertEqual((#{<<"key">> => <<"value">>}),
                 (de_mission_brain:parse_json_payload(<<"some noise ",
                                                        ValidJson/binary, " more noise">>))).

-spec analyze_llm_response_test() -> ok.

analyze_llm_response_test() ->
    OllamaRaw =
        <<"{\"delegate_required\": true, \"tool_intent\""
          ": \"k8s_deploy\", \"response\": \"Delegating\""
          "}">>,
    {Type, Intent, _Args, Response} =
        de_mission_brain:analyze_llm_response(OllamaRaw, []),
    ?assertEqual(delegate, Type),
    ?assertEqual(<<"k8s_deploy">>, Intent),
    ?assertEqual(<<"Delegating">>, Response).

-spec analyze_llm_response_fallback_test() -> ok.

analyze_llm_response_fallback_test() ->
    FakeOllama = <<"Just plain text here.">>,
    {Type, Response} =
        de_mission_brain:analyze_llm_response(FakeOllama, []),
    ?assertEqual(direct, Type),
    ?assertEqual(FakeOllama, Response).

-spec build_new_context_test() -> ok.

build_new_context_test() ->
    Prev = [],
    NewCtx = de_mission_brain:build_new_context(<<"hello">>,
                                                <<"world">>,
                                                Prev),
    ?assertEqual(2, (length(NewCtx))),
    [User, Asst] = NewCtx,
    ?assertEqual(<<"user">>, (maps:get(<<"role">>, User))),
    ?assertEqual(<<"assistant">>,
                 (maps:get(<<"role">>, Asst))).
