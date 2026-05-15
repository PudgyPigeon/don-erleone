-module(de_agent_brain_tests).
-include_lib("eunit/include/eunit.hrl").

analyze_loop_step_stop_test() ->
  Msg = #{<<"content">> => <<"Final answer here.">>},
  ?assertEqual({stop, <<"Final answer here.">>}, de_agent_brain:analyze_loop_step(Msg)).

analyze_loop_step_continue_test() ->
  Msg = #{<<"tool_calls">> => [#{<<"id">> => 1}]},
  ?assertMatch({continue, [_]}, de_agent_brain:analyze_loop_step(Msg)).

decode_tools_ok_test() ->
  Body = << "{\"result\": {\"tools\": [{\"name\": \"t1\"}]}}" >>,
  ?assertMatch({ok, [_]}, de_agent_brain:decode_tools(Body)).

prepare_mcp_request_test() ->
  {Headers, Payload} = de_agent_brain:prepare_mcp_request(<<"m">>, #{<<"p">> => 1}),
  ?assertMatch([{<<"Content-Type">>, _}, {<<"Mcp-Protocol-Version">>, _}], Headers),
  Decoded = jsx:decode(Payload, [return_maps]),
  ?assertEqual(<<"m">>, maps:get(<<"method">>, Decoded)).

build_sub_prompt_test() ->
  Result = de_agent_brain:build_sub_prompt(<<"i">>, <<"g">>, [#{<<"name">> => <<"t1">>}]),
  Binary = iolist_to_binary(Result),
  ?assertMatch({_, _}, binary:match(Binary, <<"t1">>)),
  ?assertMatch({_, _}, binary:match(Binary, <<"GOAL: g">>)).
