%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_telemetry).

-export([setup/0]).

-export([handle_event/4]).

-include_lib("kernel/include/logger.hrl").

%% =============================================================================
%% API
%% =============================================================================

-spec setup() -> ok | {error, term()}.

setup() ->
    Events = [
        [don_erleone, startup],
        [don_erleone, http, request, start],
        [don_erleone, http, request, stop],
        [don_erleone, http, request, exception],
        [don_erleone, ollama, request, start],
        [don_erleone, ollama, request, stop],
        [don_erleone, ollama, request, error],
        [don_erleone, worker, execute, start],
        [don_erleone, worker, execute, stop],
        [don_erleone, worker, execute, exception]
    ],
    %% Switched macro capture to local capture to prevent formatter crashes
    telemetry:attach_many(
        <<"don-erleone-telemetry">>,
        Events,
        fun handle_event/4,
        ok
    ).

-spec handle_event(list(), map(), map(), term()) -> ok.

handle_event(Event, Measurements, Metadata, _Config) ->
    ?LOG_INFO(
        (#{
            node => node(),
            telemetry_event => Event,
            measurements => Measurements,
            metadata => Metadata
        })
    ),
    ok.
