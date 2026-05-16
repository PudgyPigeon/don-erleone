%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_consigliere_tests).

-include_lib("eunit/include/eunit.hrl").

%% =============================================================================
%% Test Generators
%% =============================================================================

-spec handle_mission_test_() -> term().

handle_mission_test_() ->
    {setup,
     fun () ->
             {ok, _} = application:ensure_all_started(telemetry),
             de_telemetry:setup(),
             meck:new(poolboy, [non_strict]),
             %% Quiet the logger modern way
             logger:set_primary_config(#{level => none}),
             ok
     end,
     fun (_) ->
             logger:set_primary_config(#{level => info}),
             meck:unload(poolboy)
     end,
     [{"Verify fallback on pool timeout",
       fun test_pool_timeout_fallback/0}]}.

-spec test_pool_timeout_fallback() -> ok.

test_pool_timeout_fallback() ->
    %% 1. Force the poolboy transaction to crash
    meck:expect(poolboy,
                transaction,
                fun (_Pool, _Fun) ->
                        erlang:error(simulated_pool_timeout)
                end),
    TestPid = self(),
    Tag = make_ref(),
    CowboyFrom = {TestPid, Tag},

    %% 2. Dispatch the mission
    ?assertEqual(ok,
                 (de_consigliere:handle_mission(<<"sess">>,
                                                <<"prompt">>,
                                                CowboyFrom))),
    %% 3. Verify the cowboy process receives the fallback error payload
    receive
        {Tag, {error, internal_service_error}} -> ok
        after 1000 -> ?assert(timeout_waiting_for_reply)
    end.
