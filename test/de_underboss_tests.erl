%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_underboss_tests).
-include_lib("eunit/include/eunit.hrl").

dispatch_mission_test_() ->
    {foreach,
        fun setup/0,
        fun teardown/1,
        [
            fun(Arg) -> ?_test(test_mission_failed_db_update(Arg)) end,
            fun(Arg) -> ?_test(test_mission_failed_client_notification(Arg)) end
        ]}.

setup() ->
    {ok, _} = application:ensure_all_started(telemetry),
    de_telemetry:setup(),
    meck:unload(), %% Ensure clean slate
    meck:new(poolboy, [non_strict]),
    meck:new(de_store, [non_strict]),
    meck:new(logger, [unstick, passthrough]),
    meck:expect(logger, error, fun(_Format, _Args) -> ok end),
    ok.

teardown(_) ->
    meck:unload(logger),
    meck:unload(poolboy),
    meck:unload(de_store).

test_mission_failed_db_update(_) ->
    TestPid = self(),
    meck:expect(poolboy, transaction, fun(_, _) -> erlang:error(simulated_exhaustion) end),
    meck:expect(de_store, fail_mission, fun(Id, Reason) -> TestPid ! {failed, Id, Reason}, ok end),

    Mission = #{id => 999, intent => <<"test">>, cowboy_from => {TestPid, make_ref()}},
    de_underboss:dispatch_mission(Mission),

    receive
        {failed, 999, {execution_error, simulated_exhaustion}} -> ok
    after 1000 ->
        erlang:error(timeout_db_update)
    end.

test_mission_failed_client_notification(_) ->
    TestPid = self(),
    Tag = make_ref(),
    meck:expect(poolboy, transaction, fun(_, _) -> erlang:error(simulated_exhaustion) end),
    meck:expect(de_store, fail_mission, fun(_, _) -> ok end),

    Mission = #{id => 999, intent => <<"test">>, cowboy_from => {TestPid, Tag}},
    de_underboss:dispatch_mission(Mission),

    receive
        {Tag, {error, {execution_failed, simulated_exhaustion}}} -> ok
    after 1000 ->
        erlang:error(timeout_client_notification)
    end.
