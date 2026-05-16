%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_utils_tests).
-include_lib("eunit/include/eunit.hrl").

to_list_binary_test() ->
  ?assertEqual("hello", de_utils:to_list(<<"hello">>)).

to_list_list_test() ->
  ?assertEqual("world", de_utils:to_list("world")).

to_list_other_test() ->
  ?assertEqual("123", de_utils:to_list(123)).

any_to_int_list_test() ->
  ?assertEqual(123, de_utils:any_to_int("123")).

any_to_int_binary_test() ->
  ?assertEqual(456, de_utils:any_to_int(<<"456">>)).

any_to_int_atom_test() ->
  ?assertEqual(789, de_utils:any_to_int('789')).
