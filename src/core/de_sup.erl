%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_sup).

-behaviour(supervisor).

-export([start_link/0, init/1]).

-spec start_link() -> {ok, pid()} | {error, term()}.

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

-spec init(list()) -> {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.

init([]) ->
    SupFlags = #{
        strategy => one_for_one,
        intensity => 5,
        period => 10
    },
    %% Load Configurations
    Config = de_config:load_main_config(),
    SubConfig = de_config:load_sub_agent_config(),

    %% The HTTP Gateway
    ChildSpecs = [
        #{
            id => de_front,
            start => {de_front, start_link, []},
            restart => permanent,
            type => worker
        },
        %% The Orchestration Layer
        #{
            id => de_commission,
            start =>
                {de_commission, start_link, [Config, SubConfig]},
            restart => permanent,
            type => supervisor
        }
    ],
    {ok, {SupFlags, ChildSpecs}}.
