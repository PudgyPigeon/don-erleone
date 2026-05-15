%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_front).

-behaviour(gen_server).

-export([
  start_link/0,
  init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2
]).

-define(LISTENER_REF, http_frontend_listener).

-record(de_front_state, {}).

-type state() :: #de_front_state{}.

%% =============================================================================
%% Lifecycle
%% =============================================================================

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec init(list()) -> {ok, state()} | {stop, term()}.
init([]) ->
  %% Ensure a clean start by stopping any ghost listeners
  _ = cowboy:stop_listener(?LISTENER_REF),

  case start_http_listener() of
    {ok, _Pid} ->
      logger:info(#{event => http_frontend_operational, port => 8080}),
      {ok, #de_front_state{}};
    {error, Reason} ->
      logger:error(#{event => http_frontend_failed, reason => Reason}),
      {stop, {cowboy_start_failed, Reason}}
  end.

-spec terminate(term(), state()) -> ok.
terminate(_Reason, _State) ->
  cowboy:stop_listener(?LISTENER_REF),
  ok.

%% =============================================================================
%% HTTP Configuration (The "Functional" Chunks)
%% =============================================================================

-spec start_http_listener() -> {ok, pid()} | {error, term()}.
start_http_listener() ->
  Dispatch = build_dispatch_rules(),
  Port = application:get_env(don_erleone, http_port, 8080),

  cowboy:start_clear(
    ?LISTENER_REF,
    [{port, Port}],
    #{
      env => #{dispatch => Dispatch},
      %% 15 minute idle timeout for long-running LLM streams
      idle_timeout => 900000
    }
  ).

-spec build_dispatch_rules() -> term().
build_dispatch_rules() ->
  cowboy_router:compile([
    {'_', [
      {"/v1/chat/completions", de_openai_handler, []},
      {"/v1/models", de_openai_models_handler, []},
      {"/health", de_health_handler, []}
    ]}
  ]).

%% =============================================================================
%% Standard Callbacks
%% =============================================================================

-spec handle_call(term(), {pid(), term()}, state()) -> {reply, term(), state()}.
handle_call(_Req, _From, State) ->
  {reply, ok, State}.

-spec handle_cast(term(), state()) -> {noreply, state()}.
handle_cast(_Msg, State) ->
  {noreply, State}.

-spec handle_info(term(), state()) -> {noreply, state()}.
handle_info(_Msg, State) ->
  {noreply, State}.