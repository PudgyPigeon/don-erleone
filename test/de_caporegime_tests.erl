%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_caporegime_tests).

-include_lib("eunit/include/eunit.hrl").

%% Test the logic that moved to de_agent_brain
-spec build_sub_prompt_test_() -> list().

build_sub_prompt_test_() ->
    Cases = [{<<"k8s_deploy">>,
              <<"Deploy nginx">>,
              <<"k8s_deploy">>},
             {<<"check_mcp">>, <<"Status">>, <<"STRICT PROTOCOL">>},
             {<<"unknown">>, <<"Do this">>, <<"MISSION RULES">>}],
    [{lists:flatten(io_lib:format("Testing ~s prompt",
                                  [Task])),
      ?_assertMatch({_, _},
                    (binary:match(iolist_to_binary(de_agent_brain:build_sub_prompt(Task,
                                                                                   Input,
                                                                                   [])),
                                  ExpectedSubString)))}
     || {Task, Input, ExpectedSubString} <- Cases].

-spec decode_tools_test() -> ok.

decode_tools_test() ->
    Raw = jsx:encode(#{<<"result">> =>
                           #{<<"tools">> => [#{<<"name">> => <<"test_tool">>}]}}),
    {ok, Tools} = de_agent_brain:decode_tools(Raw),
    ?assertEqual(1, (length(Tools))),
    ?assertEqual(<<"test_tool">>,
                 (maps:get(<<"name">>, hd(Tools)))).
