-module(de_store_tests).
-include_lib("eunit/include/eunit.hrl").

de_store_test_() ->
  {setup, fun setup/0, fun cleanup/1, [
    fun test_post_retrieval/0,
    fun test_post_initial_status/0,
    fun test_update_status/0,
    fun test_complete_status/0,
    fun test_complete_result/0,
    fun test_fail_status/0,
    fun test_fail_error/0,
    fun test_get_latest_context/0,
    fun test_get_pending_missions/0
  ]}.

setup() ->
  {ok, _} = application:ensure_all_started(telemetry),
  de_telemetry:setup(),
  application:set_env(mnesia, dir, ".mnesia_test_dir"),
  _ = mnesia:stop(),
  _ = mnesia:delete_schema([node()]),
  _ = mnesia:start(),
  de_store:init_db(),
  ok.

cleanup(_) ->
  _ = mnesia:stop(),
  _ = mnesia:delete_schema([node()]),
  ok.

test_post_retrieval() ->
  {ok, Id} = de_store:post_mission(<<"s1">>, <<"i1">>, <<"p">>, []),
  {ok, Mission} = de_store:get_mission(Id),
  ?assertEqual(Id, de_store:mission_id(Mission)).

test_post_initial_status() ->
  {ok, Id} = de_store:post_mission(<<"s2">>, <<"i2">>, <<"p">>, []),
  {ok, Mission} = de_store:get_mission(Id),
  ?assertEqual(pending, de_store:mission_status(Mission)).

test_update_status() ->
  {ok, Id} = de_store:post_mission(<<"s3">>, <<"i3">>, <<"p">>, []),
  ok = de_store:update_status(Id, in_progress),
  {ok, Mission} = de_store:get_mission(Id),
  ?assertEqual(in_progress, de_store:mission_status(Mission)).

test_complete_status() ->
  {ok, Id} = de_store:post_mission(<<"s4">>, <<"i4">>, <<"p">>, []),
  ok = de_store:complete_mission(Id, <<"res">>),
  {ok, Mission} = de_store:get_mission(Id),
  ?assertEqual(completed, de_store:mission_status(Mission)).

test_complete_result() ->
  {ok, Id} = de_store:post_mission(<<"s5">>, <<"i5">>, <<"p">>, []),
  ok = de_store:complete_mission(Id, <<"res">>),
  {ok, Mission} = de_store:get_mission(Id),
  ?assertEqual(<<"res">>, de_store:mission_result(Mission)).

test_fail_status() ->
  {ok, Id} = de_store:post_mission(<<"s6">>, <<"i6">>, <<"p">>, []),
  ok = de_store:fail_mission(Id, <<"err">>),
  {ok, Mission} = de_store:get_mission(Id),
  ?assertEqual(failed, de_store:mission_status(Mission)).

test_fail_error() ->
  {ok, Id} = de_store:post_mission(<<"s7">>, <<"i7">>, <<"p">>, []),
  ok = de_store:fail_mission(Id, <<"err">>),
  {ok, Mission} = de_store:get_mission(Id),
  ?assertEqual(<<"err">>, de_store:mission_error(Mission)).

test_get_latest_context() ->
  Session = <<"ctx_sess">>,
  de_store:post_mission(Session, <<"i">>, <<"p">>, [1]),
  timer:sleep(10),
  de_store:post_mission(Session, <<"i">>, <<"p">>, [1, 2]),
  ?assertEqual([1, 2], de_store:get_latest_context(Session)).

test_get_pending_missions() ->
  {ok, Id} = de_store:post_mission(<<"pend">>, <<"i">>, <<"p">>, []),
  {ok, Pending} = de_store:get_pending_missions(),
  Ids = [de_store:mission_id(M) || M <- Pending],
  ?assert(lists:member(Id, Ids)).
