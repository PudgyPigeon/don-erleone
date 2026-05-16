%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_caporegime_infra_tests).
-include_lib("eunit/include/eunit.hrl").

-record(sub_config, {
  ollama_url :: string(),
  mcp_url :: string(),
  model :: string(),
  timeout :: integer(),
  max_steps :: integer()
}).

-record(de_caporegime_state, {
  config,
  conn
}).

%% =============================================================================
%% Test Generators
%% =============================================================================

logger_test_() ->
  {setup,
    fun() -> logger:set_primary_config(#{level => none}) end,
    fun(_) -> logger:set_primary_config(#{level => info}) end,
    [
      test_conn_lifecycle(),
      test_mcp_parsing()
    ]
  }.

%% =============================================================================
%% Tests
%% =============================================================================

test_conn_lifecycle() ->
  [
    {"Alive check",
     fun() ->
       Pid = self(),
       State = #de_caporegime_state{conn = Pid},
       ?assertEqual({ok, State}, de_caporegime:check_conn_alive(true, State))
     end},
    {"Reconnect check",
     fun() ->
       meck:new(gun, [unstick, passthrough]),
       meck:new(de_config, [passthrough]),
       try
         meck:expect(gun, open, fun(_, _, _) -> {error, simulated} end),
         meck:expect(de_config, sub_config_mcp_url, fun(_) -> "http://localhost:8080" end),
         State = #de_caporegime_state{conn = c_pid, config = #sub_config{mcp_url = "http://localhost:8080"}},
         ?assertMatch({error, _}, de_caporegime:check_conn_alive(false, State))
       after
         meck:unload(gun),
         meck:unload(de_config)
       end
     end}
  ].

test_mcp_parsing() ->
  [
    ?_assertEqual(<<"Output">>,
                  de_caporegime:parse_mcp_body(#{<<"result">> => #{<<"content">> => [#{<<"type">> => <<"text">>, <<"text">> => <<"Output">>}]}})),
    ?_assertEqual([<<"MCP Error: ">>, <<"Boom">>],
                  de_caporegime:parse_mcp_body(#{<<"error">> => #{<<"message">> => <<"Boom">>}})),
    ?_assertEqual(<<"No text response from tool.">>,
                  de_caporegime:parse_mcp_body(#{<<"result">> => #{<<"content">> => []}}))
  ].
