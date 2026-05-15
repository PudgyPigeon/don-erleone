-module(de_app_tests).
-include_lib("eunit/include/eunit.hrl").

%% ===================================================================
%% Setup & Teardown Fixtures
%% ===================================================================

setup_env() ->
    %% You can set up initial state here if needed,
    %% but for this we just need to pass an empty state forward.
    ok.

teardown_env(_SetupState) ->
    %% GUARANTEED CLEANUP: Wipe all variables we touched during tests
    application:unset_env(don_erleone, test_str),
    application:unset_env(don_erleone, test_bin),
    application:unset_env(don_erleone, test_int),
    application:unset_env(don_erleone, test_int_str),
    application:unset_env(don_erleone, test_int_bin),
    application:unset_env(don_erleone, test_bad).

%% ===================================================================
%% Test Generators
%% ===================================================================

%% The _test_() suffix tells EUnit this is a generator that uses fixtures
env_vars_test_() ->
    {foreach, fun setup_env/0, fun teardown_env/1, [
        fun test_get_env_string/1,
        fun test_get_env_integer/1
    ]}.

%% ===================================================================
%% The Actual Tests (Note they take _SetupState as an argument now)
%% ===================================================================

test_get_env_string(_SetupState) ->
    %% Return a list of assertions
    [
        begin
            application:set_env(don_erleone, test_str, "hello"),
            ?_assertEqual("hello", de_config:get_env_string(test_str, "default"))
        end,
        begin
            application:set_env(don_erleone, test_bin, <<"world">>),
            ?_assertEqual("world", de_config:get_env_string(test_bin, "default"))
        end,
        ?_assertEqual("default", de_config:get_env_string(missing_key, "default"))
    ].

test_get_env_integer(_SetupState) ->
    [
        begin
            application:set_env(don_erleone, test_int, 42),
            ?_assertEqual(42, de_config:get_env_integer(test_int, 10))
        end,
        begin
            application:set_env(don_erleone, test_int_str, "100"),
            ?_assertEqual(100, de_config:get_env_integer(test_int_str, 10))
        end,
        begin
            application:set_env(don_erleone, test_int_bin, <<"200">>),
            ?_assertEqual(200, de_config:get_env_integer(test_int_bin, 10))
        end,
        begin
            application:set_env(don_erleone, test_bad, "not_int"),
            ?_assertEqual(10, de_config:get_env_integer(test_bad, 10))
        end,
        ?_assertEqual(10, de_config:get_env_integer(missing_key, 10))
    ].

%% We don't need setup/teardown for this one since it doesn't mutate state,
%% so we can just use the standard _test() suffix.
get_system_prompt_test() ->
    Prompt = de_config:get_system_prompt(),
    ?assert(is_binary(Prompt)),
    %% Ensure it's not empty/tiny
    ?assert(byte_size(Prompt) > 50),

    %% Optional: Check for a keyword you know must exist in the prompt
    %% (e.g., binary:match(Prompt, <<"You are Don Erleone">>) =/= nomatch)
    ok.
