%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_app).

-behaviour(application).

-export([start/2, stop/1]).

-spec start(application:start_type(), term()) ->
    {ok, pid()}
    | {error, term()}.

start(_StartType, _StartArgs) ->
    %% Setup Telemetry early
    de_telemetry:setup(),
    telemetry:execute([don_erleone, startup], #{}, #{}),

    %% Initialize Database
    case de_store:init_db() of
        ok -> ok;
        {error, DbErr} -> logger:error(#{event => db_init_failed, error => DbErr})
    end,
    de_sup:start_link().

-spec stop(term()) -> ok.

stop(_State) -> ok.
