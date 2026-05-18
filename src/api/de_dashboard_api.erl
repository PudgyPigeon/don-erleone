%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_dashboard_api).

-export([get_metrics/0, get_recent_missions/1]).

%% =============================================================================
%% API: Operational Metrics (LiveView Deck)
%% =============================================================================

-spec get_metrics() -> map().
get_metrics() ->
    Consigliere = get_pool_status(de_consigliere_pool, 5, 15),
    Caporegime = get_pool_status(de_caporegime_pool, 3, 10),
    Memory = erlang:memory(total),
    Procs = erlang:system_info(process_count),
    RunQueue = erlang:statistics(run_queue),
    
    #{
        consigliere => Consigliere,
        caporegime => Caporegime,
        system_vitals => #{
            memory_bytes => Memory,
            process_count => Procs,
            run_queue => RunQueue
        }
    }.

-spec get_pool_status(atom(), integer(), integer()) -> map().
get_pool_status(PoolName, DefaultSize, DefaultOverflow) ->
    case catch poolboy:status(PoolName) of
        {StatusAtom, Active, Idle, Overflow} when is_atom(StatusAtom) ->
            #{
                active => Active,
                idle => Idle,
                overflow => Overflow,
                max_size => DefaultSize,
                max_overflow => DefaultOverflow,
                status => StatusAtom
            };
        _ ->
            #{
                active => 0,
                idle => DefaultSize,
                overflow => 0,
                max_size => DefaultSize,
                max_overflow => DefaultOverflow,
                status => offline
            }
    end.

%% =============================================================================
%% API: Mission Ledgers
%% =============================================================================

-spec get_recent_missions(integer()) -> [map()].
get_recent_missions(Limit) ->
    case catch mnesia:dirty_select(mission, [{'_', [], ['$_']}]) of
        List when is_list(List) ->
            %% Sort descending by timestamp
            Sorted = lists:sort(
                fun(A, B) ->
                    %% mission record tuple element 10 is timestamp
                    element(10, A) > element(10, B)
                end,
                List
            ),
            Truncated = lists:sublist(Sorted, Limit),
            lists:map(fun format_mission/1, Truncated);
        _ ->
            []
    end.

-spec format_mission(tuple()) -> map().
format_mission(MissionTuple) ->
    %% Record format: {mission, id, session_id, intent, raw_prompt, status, result, error, context_tokens, timestamp}
    #{
        id => element(2, MissionTuple),
        session_id => element(3, MissionTuple),
        intent => element(4, MissionTuple),
        raw_prompt => element(5, MissionTuple),
        status => element(6, MissionTuple),
        result => format_term(element(7, MissionTuple)),
        error => format_term(element(8, MissionTuple)),
        timestamp => element(10, MissionTuple)
    }.

-spec format_term(term()) -> binary().
format_term(undefined) -> <<"nil">>;
format_term(Term) when is_binary(Term) -> Term;
format_term(Term) -> 
    iolist_to_binary(io_lib:format("~p", [Term])).
