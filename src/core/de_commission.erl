%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_commission).

-behaviour(supervisor).

-export([start_link/2, init/1]).

%% =============================================================================
%% API
%% =============================================================================

-spec start_link(de_config:config(), de_config:sub_config()) ->
  {ok, pid()} | {error, term()}.
start_link(Config, SubConfig) ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, [Config, SubConfig]).

%% =============================================================================
%% Supervisor Initialization
%% =============================================================================

-spec init(list()) -> {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init([Config, SubConfig]) ->
  logger:info(#{event => supervisor_init, module => ?MODULE}),
  %% Strategy: one_for_one
  %% Decoupling the Strategy workers from the Execution managers.
  SupFlags = #{
    strategy => one_for_one,
    intensity => 10,
    period => 60
  },

  {ok, {SupFlags, child_specs(Config, SubConfig)}}.

%% =============================================================================
%% Child Definitions
%% =============================================================================

-spec child_specs(de_config:config(), de_config:sub_config()) -> [supervisor:child_spec()].
child_specs(Config, SubConfig) ->
  [
    %% 1. The Underboss (Fleet Manager for Caporegimes)
    %% This handles the 'Shell' side of the Autonomous Loop.
    #{
      id => de_underboss,
      start => {de_underboss, start_link, [SubConfig]},
      restart => permanent,
      type => supervisor
    },

    %% 2. The Consigliere Pool (Strategy Workers)
    %% This handles the 'Shell' side of the LLM Strategy.
    poolboy:child_spec(de_consigliere_pool, pool_config(), [Config])
  ].

%% =============================================================================
%% Internal Configuration
%% =============================================================================

-spec pool_config() -> list().
pool_config() ->
  [
    {name, {local, de_consigliere_pool}},
    {worker_module, de_consigliere_worker},
    {size, 5},           %% Static workers always ready
    {max_overflow, 15},  %% Expanded overflow for busy shifts
    {strategy, fifo}     %% Ensure we don't 'wear out' the first worker in the pool
  ].