-module(de_ollama_brain_tests).
-include_lib("eunit/include/eunit.hrl").

build_payload_test() ->
  Payload = de_ollama_brain:build_payload(<<"m">>, <<"p">>, [], <<"s">>, false, []),
  Decoded = jsx:decode(Payload, [return_maps]),
  ?assertEqual(<<"m">>, maps:get(<<"model">>, Decoded)),
  Messages = maps:get(<<"messages">>, Decoded),
  ?assertEqual(2, length(Messages)).

decode_line_ok_test() ->
  Line = << "{\"message\": {\"content\": \"hi\"}}" >>,
  ?assertMatch({ok, #{<<"message">> := _}}, de_ollama_brain:decode_line(Line)).

decode_line_error_test() ->
  Line = << "{\"error\": \"failed\"}" >>,
  ?assertMatch({error, {ollama_error, <<"failed">>}}, de_ollama_brain:decode_line(Line)).

accumulate_binary_test() ->
  Msg = #{<<"message">> => #{<<"content">> => <<"world">>}},
  Result = de_ollama_brain:accumulate(<<"hello ">>, Msg, undefined),
  ?assertEqual([<<"hello ">>, <<"world">>], Result).

accumulate_list_test() ->
  Msg = #{<<"message">> => #{<<"content">> => <<"!">>}},
  Result = de_ollama_brain:accumulate([<<"hi">>, <<" there">>], Msg, undefined),
  ?assertEqual([[<<"hi">>, <<" there">>], <<"!">>], Result).

to_bin_atom_test() ->
  ?assertEqual(<<"test">>, de_ollama_brain:to_bin(test)).
