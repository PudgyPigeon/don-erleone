-module(de_ollama_client_tests).
-include_lib("eunit/include/eunit.hrl").

to_bin_test() ->
  ?assertEqual(<<"hello">>, de_ollama_brain:to_bin(<<"hello">>)),
  ?assertEqual(<<"world">>, de_ollama_brain:to_bin("world")),
  ?assertEqual(<<"123">>, de_ollama_brain:to_bin(123)).

build_payload_test() ->
  %% build_payload(Model, Prompt, Context, System, Stream, Tools)
  Payload = de_ollama_brain:build_payload("qwen", <<"Hello">>, [#{<<"role">> => <<"context">>}], <<"System">>, false, []),
  Decoded = jsx:decode(Payload, [return_maps]),
  ?assertEqual(<<"qwen">>, maps:get(<<"model">>, Decoded)),
  Messages = maps:get(<<"messages">>, Decoded),
  ?assertEqual(3, length(Messages)),
  ?assertEqual(false, maps:get(<<"stream">>, Decoded)).
