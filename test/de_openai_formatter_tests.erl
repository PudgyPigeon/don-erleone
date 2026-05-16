%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_openai_formatter_tests).

-include_lib("eunit/include/eunit.hrl").

-spec build_success_test() -> ok.

build_success_test() ->
    Json = de_openai_formatter:build_success(<<"hi">>, 123),
    Decoded = jsx:decode(Json, [return_maps]),
    ?assertMatch((#{<<"mission_id">> := <<"123">>}),
                 Decoded),
    Choices = maps:get(<<"choices">>, Decoded),
    ?assertMatch([#{<<"message">> :=
                        #{<<"content">> := <<"hi">>}}],
                 Choices).

-spec build_error_test() -> ok.

build_error_test() ->
    Json = de_openai_formatter:build_error(failed),
    Decoded = jsx:decode(Json, [return_maps]),
    ?assertMatch((#{<<"error">> :=
                        #{<<"message">> := <<"failed">>}}),
                 Decoded).
