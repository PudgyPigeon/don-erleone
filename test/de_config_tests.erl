%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_config_tests).
-include_lib("eunit/include/eunit.hrl").

get_env_string_default_test() ->
  ?assertEqual("def", de_config:get_env_string(non_existent_key, "def")).

get_env_string_os_test() ->
  os:putenv("TEST_KEY", "os_val"),
  ?assertEqual("os_val", de_config:get_env_string(test_key, "def")).

get_env_integer_default_test() ->
  ?assertEqual(123, de_config:get_env_integer(non_existent_key, 123)).

get_env_integer_os_test() ->
  os:putenv("INT_KEY", "456"),
  ?assertEqual(456, de_config:get_env_integer(int_key, 123)).

load_main_config_test() ->
  Config = de_config:load_main_config(),
  ?assert(is_list(de_config:config_ollama_url(Config))),
  ?assert(is_binary(de_config:config_system_prompt(Config))).

load_sub_config_test() ->
  Config = de_config:load_sub_agent_config(),
  ?assert(is_list(de_config:sub_config_mcp_url(Config))).
