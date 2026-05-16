%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_agent_brain_tests).

-include_lib("eunit/include/eunit.hrl").

%% =============================================================================
%% Test Generators
%% =============================================================================

-spec brain_test_() -> list().

brain_test_() ->
    [test_analyze_loop(), test_decode_tools()].

-spec test_analyze_loop() -> list().

test_analyze_loop() ->
    [{"Tool priority",
      ?_assertEqual({continue, [#{<<"id">> => 1}]},
                    (de_agent_brain:analyze_loop_step(#{<<"content">> =>
                                                            <<"Hi">>,
                                                        <<"tool_calls">> => [#{<<"id">> => 1}]})))},
     {"Stop content",
      ?_assertEqual({stop, <<"Done">>},
                    (de_agent_brain:analyze_loop_step(#{<<"content">> =>
                                                            <<"Done">>})))},
     {"Empty fallback",
      ?_assertEqual({stop,
                     <<"Mission complete or no further action "
                       "required.">>},
                    (de_agent_brain:analyze_loop_step(#{})))}].

-spec test_decode_tools() -> list().

test_decode_tools() ->
    [?_assertEqual({ok, [1]},
                   (de_agent_brain:decode_tools(<<"{\"result\": {\"tools\": [1]}}">>))),
     ?_assertEqual({ok, [2]},
                   (de_agent_brain:decode_tools(<<"{\"tools\": [2]}">>))),
     ?_assertEqual({error, json_invalid},
                   (de_agent_brain:decode_tools(<<"{">>))),
     ?_assertMatch({error, {bad_structure, _}},
                   (de_agent_brain:decode_tools(<<"{}">>)))].
