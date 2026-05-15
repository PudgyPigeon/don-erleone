-module(de_consigliere_tests).
-include_lib("eunit/include/eunit.hrl").

handle_mission_test_() ->
    {setup,
        fun() ->
            {ok, _} = application:ensure_all_started(telemetry),
            de_telemetry:setup(),
            meck:new(poolboy, [non_strict]),
            %% Intercept and silence the expected error logs
            meck:new(logger, [unstick, passthrough]),
            meck:expect(logger, error, fun(_Format, _Args) -> ok end),
            ok
        end,
        fun(_) ->
            meck:unload(logger),
            meck:unload(poolboy)
        end,
        fun() ->
            %% 1. Force the poolboy transaction to crash
            meck:expect(poolboy, transaction, fun(_Pool, _Fun) ->
                erlang:error(simulated_pool_timeout)
            end),

            TestPid = self(),
            Tag = make_ref(),
            CowboyFrom = {TestPid, Tag},

            %% 2. Dispatch the mission
            ?assertEqual(ok, de_consigliere:handle_mission(<<"sess">>, <<"prompt">>, CowboyFrom)),

            %% 3. Verify the cowboy process receives the fallback error payload
            receive
                {Tag, {error, internal_service_error}} -> ok
            after 1000 ->
                erlang:error(timeout_waiting_for_cowboy_reply)
            end
        end}.
