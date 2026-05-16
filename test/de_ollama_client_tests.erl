%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_ollama_client_tests).

-include_lib("eunit/include/eunit.hrl").

-define(CTX,
        #{conn => self(), ref => ref, tmo => 1000,
          host => "host", is_stream => true, cb => undefined}).

%% =============================================================================
%% Test Generators
%% =============================================================================

-spec logger_test_() -> term().

logger_test_() ->
    {setup,
     fun () -> logger:set_primary_config(#{level => none})
     end,
     fun (_) -> logger:set_primary_config(#{level => info})
     end,
     [test_stream_events(), test_endpoint_parsing()]}.

%% =============================================================================
%% Tests
%% =============================================================================

-spec test_stream_events() -> [term()].

test_stream_events() ->
    [?_assertEqual({next, <<>>, <<>>},
                   (de_ollama_client:handle_stream_event({gun_response,
                                                          self(),
                                                          ref,
                                                          nofin,
                                                          200,
                                                          []},
                                                         ?CTX,
                                                         <<>>,
                                                         <<>>))),
     ?_assertEqual({error, {http_status, 404}},
                   (de_ollama_client:handle_stream_event({gun_response,
                                                          self(),
                                                          ref,
                                                          nofin,
                                                          404,
                                                          []},
                                                         ?CTX,
                                                         <<>>,
                                                         <<>>))),
     ?_assertEqual({error, {stream_err, reason}},
                   (de_ollama_client:handle_stream_event({gun_error,
                                                          self(),
                                                          ref,
                                                          reason},
                                                         ?CTX,
                                                         <<>>,
                                                         <<>>))),
     ?_assertEqual({error, {gun_err, reason}},
                   (de_ollama_client:handle_stream_event({gun_error,
                                                          self(),
                                                          reason},
                                                         ?CTX,
                                                         <<>>,
                                                         <<>>))),
     ?_assertEqual({error, connection_closed},
                   (de_ollama_client:handle_stream_event({gun_down,
                                                          self(),
                                                          http,
                                                          closed,
                                                          [],
                                                          []},
                                                         ?CTX,
                                                         <<>>,
                                                         <<>>)))].

-spec test_endpoint_parsing() -> [term()].

test_endpoint_parsing() ->
    [?_assertEqual({"localhost", 11434, "/api/chat"},
                   (de_utils:parse_url("http://localhost:11434/api/chat"))),
     ?_assertEqual({"ollama", 80, "/api/chat"},
                   (de_utils:parse_url("http://ollama/api/chat")))].
