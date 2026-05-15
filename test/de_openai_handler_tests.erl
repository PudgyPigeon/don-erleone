-module(de_openai_handler_tests).
-include_lib("eunit/include/eunit.hrl").

build_success_response_test() ->
    Resp = de_openai_formatter:build_success(<<"System running.">>, 456),
    Decoded = jsx:decode(Resp, [return_maps]),
    ?assertEqual(<<"456">>, maps:get(<<"mission_id">>, Decoded)),

    [Choice | _] = maps:get(<<"choices">>, Decoded),
    Message = maps:get(<<"message">>, Choice),
    ?assertEqual(<<"assistant">>, maps:get(<<"role">>, Message)),
    ?assertEqual(<<"System running.">>, maps:get(<<"content">>, Message)).

build_success_response_null_id_test() ->
    Resp = de_openai_formatter:build_success(<<"Ok">>, null),
    Decoded = jsx:decode(Resp, [return_maps]),
    ?assertEqual(<<"null">>, maps:get(<<"mission_id">>, Decoded)).

build_error_response_test() ->
    Resp = de_openai_formatter:build_error(timeout),
    Decoded = jsx:decode(Resp, [return_maps]),
    ErrorMap = maps:get(<<"error">>, Decoded),
    ?assertEqual(<<"de_consigliere_error">>, maps:get(<<"type">>, ErrorMap)),
    ?assertEqual(<<"timeout">>, maps:get(<<"message">>, ErrorMap)).
