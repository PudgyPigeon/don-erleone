%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_store).

-export([init_db/0,
         post_mission/4,
         get_mission/1,
         get_latest_context/1,
         update_status/2,
         complete_mission/2,
         fail_mission/2,
         get_pending_missions/0,
         mission_id/1,
         mission_session_id/1,
         mission_intent/1,
         mission_status/1,
         mission_result/1,
         mission_error/1]).

-ifdef(TEST).

-export([handle_transaction/2,
         handle_read_result/1,
         handle_write_result/2]).

-endif.

-export_type([mission/0]).

-record(mission,
        {id :: integer(),
         session_id :: binary(),
         intent :: binary(),
         raw_prompt :: binary(),
         status = pending ::
             pending | in_progress | completed | failed,
         result :: term(),
         error :: term(),
         context_tokens = [] :: list(),
         timestamp :: integer()}).

-type mission() :: #mission{}.

%% =============================================================================
%% Database Lifecycle
%% =============================================================================

-spec init_db() -> ok | {error, term()}.

init_db() ->
    logger:info(#{event => db_init_start}),
    _ = mnesia:start(),
    TableDef = [{attributes, record_info(fields, mission)},
                {index, [session_id, status]},
                {ram_copies, [node()]}],
    ensure_table(mission, TableDef).

-spec ensure_table(atom(), list()) -> ok |
                                      {error, term()}.

ensure_table(Name, Def) ->
    handle_create_result(mnesia:create_table(Name, Def),
                         Name).

-spec handle_create_result({atomic, ok} |
                           {aborted, term()},
                           atom()) -> ok | {error, term()}.

handle_create_result({atomic, ok}, Name) ->
    logger:info(#{event => table_created, table => Name}),
    mnesia:wait_for_tables([Name], 5000);
handle_create_result({aborted, {already_exists, Name}},
                     Name) ->
    mnesia:wait_for_tables([Name], 5000);
handle_create_result({aborted, Reason}, Name) ->
    logger:error(#{event => table_creation_failed,
                   table => Name, error => Reason}),
    {error, Reason}.

%% =============================================================================
%% Public API (Orchestration)
%% =============================================================================

-spec post_mission(binary(), binary(), binary(),
                   list()) -> {ok, integer()} | {error, term()}.

post_mission(SessionId, Intent, Prompt, Context) ->
    Id = erlang:unique_integer([positive, monotonic]),
    Record = #mission{id = Id, session_id = SessionId,
                      intent = Intent, raw_prompt = Prompt, status = pending,
                      context_tokens = Context,
                      timestamp = erlang:system_time(second)},
    execute_write(Record, Id).

-spec get_mission(integer()) -> {ok, mission()} |
                                {error, term()}.

get_mission(Id) -> execute_read(Id).

-spec get_latest_context(binary()) -> list().

get_latest_context(SessionId) ->
    process_context_read(mnesia:dirty_index_read(mission,
                                                 SessionId,
                                                 #mission.session_id)).

-spec process_context_read([mission()]) -> list().

process_context_read([]) -> [];
process_context_read(List) ->
    Sorted = sort_by_timestamp(List),
    extract_context(hd(Sorted)).

-spec update_status(integer(), atom()) -> ok |
                                          {error, term()}.

update_status(MissionId, NewStatus) ->
    modify_mission(MissionId,
                   fun (R) -> R#mission{status = NewStatus} end).

-spec complete_mission(integer(), term()) -> ok |
                                             {error, term()}.

complete_mission(MissionId, Result) ->
    modify_mission(MissionId,
                   fun (R) ->
                           R#mission{status = completed, result = Result}
                   end).

-spec get_pending_missions() -> {ok, [mission()]} |
                                {error, term()}.

get_pending_missions() ->
    Trans = fun () ->
                    mnesia:index_read(mission, pending, #mission.status)
            end,
    case handle_transaction(mnesia:transaction(Trans),
                            undefined)
        of
        {error, _} = Err -> Err;
        Results -> {ok, Results}
    end.

-spec fail_mission(integer(), term()) -> ok |
                                         {error, term()}.

fail_mission(MissionId, Error) ->
    modify_mission(MissionId,
                   fun (R) -> R#mission{status = failed, error = Error}
                   end).

%% =============================================================================
%% Internal Transaction Logic
%% =============================================================================

-spec modify_mission(integer(),
                     fun((mission()) -> mission())) -> ok | {error, term()}.

modify_mission(Id, UpdateFun) ->
    Trans = fun () ->
                    case mnesia:read(mission, Id) of
                        [Record] -> mnesia:write(UpdateFun(Record));
                        [] -> {error, not_found}
                    end
            end,
    handle_transaction(mnesia:transaction(Trans), Id).

-spec execute_write(mission(), integer()) -> {ok,
                                              integer()} |
                                             {error, term()}.

execute_write(Record, Id) ->
    Result = mnesia:transaction(fun () ->
                                        mnesia:write(Record)
                                end),
    handle_write_result(handle_transaction(Result, Id), Id).

-spec handle_write_result(ok | {error, term()},
                          integer()) -> {ok, integer()} | {error, term()}.

handle_write_result(ok, Id) -> {ok, Id};
handle_write_result(Error, _Id) -> Error.

-spec execute_read(integer()) -> {ok, mission()} |
                                 {error, term()}.

execute_read(Id) ->
    Result = mnesia:transaction(fun () ->
                                        mnesia:read(mission, Id)
                                end),
    handle_read_result(handle_transaction(Result, Id)).

-spec handle_read_result(list() |
                         {error, term()}) -> {ok, mission()} | {error, term()}.

handle_read_result([Result]) -> {ok, Result};
handle_read_result([]) -> {error, not_found};
handle_read_result(Error) -> Error.

-spec handle_transaction({atomic, term()} |
                         {aborted, term()},
                         integer() | undefined) -> term() | {error, term()}.

handle_transaction({atomic, Result}, _Id) -> Result;
handle_transaction({aborted, Reason}, Id) ->
    logger:error(#{event => db_transaction_failed,
                   mission_id => Id, error => Reason}),
    {error, Reason}.

%% =============================================================================
%% Pure Helpers
%% =============================================================================

-spec sort_by_timestamp([mission()]) -> [mission()].

sort_by_timestamp(List) ->
    lists:sort(fun (A, B) ->
                       A#mission.timestamp > B#mission.timestamp
               end,
               List).

-spec extract_context(mission()) -> list().

extract_context(#mission{context_tokens = Tokens}) ->
    Tokens.

-spec mission_id(mission()) -> integer().

mission_id(#mission{id = Id}) -> Id.

-spec mission_session_id(mission()) -> binary().

mission_session_id(#mission{session_id = SessionId}) ->
    SessionId.

-spec mission_intent(mission()) -> binary().

mission_intent(#mission{intent = Intent}) -> Intent.

-spec mission_status(mission()) -> pending |
                                   in_progress |
                                   completed |
                                   failed.

mission_status(#mission{status = Status}) -> Status.

-spec mission_result(mission()) -> term().

mission_result(#mission{result = Result}) -> Result.

-spec mission_error(mission()) -> term().

mission_error(#mission{error = Error}) -> Error.
