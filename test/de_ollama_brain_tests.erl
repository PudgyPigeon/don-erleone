%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_ollama_brain_tests).
-include_lib("eunit/include/eunit.hrl").

%% =============================================================================
%% Test Generators
%% =============================================================================

accumulate_test_() ->
  [
    {"Accumulate content chunks",
     fun() ->
       Acc = #{<<"message">> => #{<<"content">> => <<"Hello ">>}},
       Msg = #{<<"message">> => #{<<"content">> => <<"world">>}},
       Result = de_ollama_brain:accumulate(Acc, Msg, undefined),
       ExpectedContent = <<"Hello world">>,
       ?assertEqual(ExpectedContent, get_content(Result))
     end},
    {"Merge tool calls (simple)",
     fun() ->
       Acc = #{<<"message">> => #{<<"content">> => <<>>, <<"tool_calls">> => [1]}},
       Msg = #{<<"message">> => #{<<"content">> => <<>>, <<"tool_calls">> => [2]}},
       Result = de_ollama_brain:accumulate(Acc, Msg, undefined),
       ?assertEqual([1, 2], get_tools(Result))
     end},
    {"Merge tool calls (streamed chunks)",
     fun() ->
       Call1 = #{<<"index">> => 0, <<"id">> => <<"call_1">>, <<"function">> => #{<<"name">> => <<"get_logs">>}},
       Call2 = #{<<"index">> => 0, <<"function">> => #{<<"arguments">> => <<"{\"n\":">>}},
       Call3 = #{<<"index">> => 0, <<"function">> => #{<<"arguments">> => <<"10}">>}},
       
       Acc0 = #{<<"message">> => #{<<"content">> => <<>>, <<"tool_calls">> => [Call1]}},
       Msg1 = #{<<"message">> => #{<<"content">> => <<>>, <<"tool_calls">> => [Call2]}},
       Acc1 = de_ollama_brain:accumulate(Acc0, Msg1, undefined),
       
       Msg2 = #{<<"message">> => #{<<"content">> => <<>>, <<"tool_calls">> => [Call3]}},
       Result = de_ollama_brain:accumulate(Acc1, Msg2, undefined),
       
       [Merged] = get_tools(Result),
       ?assertEqual(<<"call_1">>, maps:get(<<"id">>, Merged)),
       ?assertEqual(<<"{\"n\":10}">>, maps:get(<<"arguments">>, maps:get(<<"function">>, Merged)))
     end},
    {"Full mission flow simulation",
     fun() ->
       %% 1. Simulate a JSON response from Ollama
       RawResponse = <<"{\"message\": {\"role\": \"assistant\", \"content\": \"{\\\"response\\\": \\\"I will help with that.\\\", \\\"delegate_required\\\": true, \\\"tool_intent\\\": \\\"autonomous\\\"}\"}}">>,
       Decoded = jsx:decode(RawResponse, [return_maps]),
       
       %% 2. Extract content (as de_consigliere_worker would)
       Content = maps:get(<<"content">>, maps:get(<<"message">>, Decoded)),
       
       %% 3. Analyze with brain
       {delegate, Intent, Args, Resp} = de_mission_brain:analyze_llm_response(Content, []),
       ?assertEqual(<<"autonomous">>, Intent),
       ?assertEqual(true, is_map(Args)),
       ?assertEqual(<<"I will help with that.">>, Resp),
       
       %% 4. Build new context
       NewCtx = de_mission_brain:build_new_context(<<"hi">>, Content, []),
       ?assertEqual(2, length(NewCtx)),
       ?assertEqual(<<"hi">>, maps:get(<<"content">>, lists:nth(1, NewCtx))),
       ?assertEqual(Content, maps:get(<<"content">>, lists:nth(2, NewCtx)))
     end}
  ].

get_content(#{<<"message">> := #{<<"content">> := C}}) -> C.
get_tools(#{<<"message">> := #{<<"tool_calls">> := T}}) -> T.
