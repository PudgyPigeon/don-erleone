%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_store_failures_tests).
-include_lib("eunit/include/eunit.hrl").

%% =============================================================================
%% Test Generators
%% =============================================================================

logger_test_() ->
  {setup,
    fun() -> logger:set_primary_config(#{level => none}) end,
    fun(_) -> logger:set_primary_config(#{level => info}) end,
    [
      test_transactions(),
      test_reads(),
      test_writes()
    ]
  }.

%% =============================================================================
%% Tests
%% =============================================================================

test_transactions() ->
  [
    ?_assertEqual(ok, de_store:handle_transaction({atomic, ok}, 1)),
    ?_assertEqual({error, fail}, de_store:handle_transaction({aborted, fail}, 1))
  ].

test_reads() ->
  [
    ?_assertEqual({ok, rec}, de_store:handle_read_result([rec])),
    ?_assertEqual({error, not_found}, de_store:handle_read_result([])),
    ?_assertEqual({error, fail}, de_store:handle_read_result({error, fail}))
  ].

test_writes() ->
  [
    ?_assertEqual({ok, 1}, de_store:handle_write_result(ok, 1)),
    ?_assertEqual({error, fail}, de_store:handle_write_result({error, fail}, 1))
  ].
