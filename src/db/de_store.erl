%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_store).

-export([
  init_db/0,
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
  mission_error/1
]).

-export_type([mission/0]).

-record(mission, {
  id :: integer(),
  session_id :: binary(),
  intent :: binary(),
  raw_prompt :: binary(),
  status = pending :: pending | in_progress | completed | failed,
  result :: term(),
  error :: term(),
  context_tokens = [] :: list(),
  timestamp :: integer()
}).

-type mission() :: #mission{}.

%% =============================================================================
%% Database Lifecycle
%% =============================================================================

-spec init_db() -> ok | {error, term()}.
init_db() ->
  logger:info(#{event => db_init_start}),
  _ = mnesia:start(),
  TableDef = [
    {attributes, record_info(fields, mission)},
    {index, [session_id, status]},
    {ram_copies, [node()]}
  ],
  ensure_table(mission, TableDef).

-spec ensure_table(atom(), list()) -> ok | {error, term()}.
ensure_table(Name, Def) ->
  case mnesia:create_table(Name, Def) of
    {atomic, ok} ->
      logger:info(#{event => table_created, table => Name}),
      mnesia:wait_for_tables([Name], 5000);
    {aborted, {already_exists, Name}} ->
      mnesia:wait_for_tables([Name], 5000);
    {aborted, Reason} ->
      logger:error(#{event => table_creation_failed, table => Name, error => Reason}),
      {error, Reason}
  end.

%% =============================================================================
%% Public API (Orchestration)
%% =============================================================================

-spec post_mission(binary(), binary(), binary(), list()) -> {ok, integer()} | {error, term()}.
post_mission(SessionId, Intent, Prompt, Context) ->
  Id = erlang:unique_integer([positive, monotonic]),
  Record = #mission{
    id = Id,
    session_id = SessionId,
    intent = Intent,
    raw_prompt = Prompt,
    status = pending,
    context_tokens = Context,
    timestamp = erlang:system_time(second)
  },
  execute_write(Record, Id).

-spec get_mission(integer()) -> {ok, mission()} | {error, term()}.
get_mission(Id) ->
  execute_read(Id).

-spec get_latest_context(binary()) -> list().
get_latest_context(SessionId) ->
  case mnesia:dirty_index_read(mission, SessionId, #mission.session_id) of
    [] -> [];
    List ->
      Sorted = sort_by_timestamp(List),
      extract_context(hd(Sorted))
  end.

-spec update_status(integer(), atom()) -> ok | {error, term()}.
update_status(MissionId, NewStatus) ->
  modify_mission(MissionId, fun(R) -> R#mission{status = NewStatus} end).

-spec complete_mission(integer(), term()) -> ok | {error, term()}.
complete_mission(MissionId, Result) ->
  modify_mission(MissionId, fun(R) -> R#mission{status = completed, result = Result} end).

-spec fail_mission(integer(), term()) -> ok | {error, term()}.
fail_mission(MissionId, Error) ->
  modify_mission(MissionId, fun(R) -> R#mission{status = failed, error = Error} end).

-spec get_pending_missions() -> {ok, [mission()]} | {error, term()}.
get_pending_missions() ->
  Trans = fun() -> mnesia:index_read(mission, pending, #mission.status) end,
  case mnesia:transaction(Trans) of
    {atomic, Results} -> {ok, Results};
    {aborted, Reason} -> {error, Reason}
  end.

%% =============================================================================
%% Internal Transaction Logic
%% =============================================================================

-spec modify_mission(integer(), fun((mission()) -> mission())) -> ok | {error, term()}.
modify_mission(Id, UpdateFun) ->
  Trans = fun() ->
    case mnesia:read(mission, Id) of
      [Record] -> mnesia:write(UpdateFun(Record));
      [] -> {error, not_found}
    end
  end,
  case mnesia:transaction(Trans) of
    {atomic, ok} -> ok;
    {atomic, {error, _} = Err} -> Err;
    {aborted, Reason} -> {error, Reason}
  end.

-spec execute_write(mission(), integer()) -> {ok, integer()} | {error, term()}.
execute_write(Record, Id) ->
  case mnesia:transaction(fun() -> mnesia:write(Record) end) of
    {atomic, ok} -> {ok, Id};
    {aborted, Reason} ->
      logger:error(#{event => db_write_failed, mission_id => Id, error => Reason}),
      {error, Reason}
  end.

-spec execute_read(integer()) -> {ok, mission()} | {error, term()}.
execute_read(Id) ->
  case mnesia:transaction(fun() -> mnesia:read(mission, Id) end) of
    {atomic, [Result]} -> {ok, Result};
    {atomic, []} -> {error, not_found};
    {aborted, Reason} ->
      logger:error(#{event => db_read_failed, mission_id => Id, error => Reason}),
      {error, Reason}
  end.

%% =============================================================================
%% Pure Helpers
%% =============================================================================

-spec sort_by_timestamp([mission()]) -> [mission()].
sort_by_timestamp(List) ->
  lists:sort(fun(A, B) -> A#mission.timestamp > B#mission.timestamp end, List).

-spec extract_context(mission()) -> list().
extract_context(#mission{context_tokens = Tokens}) -> Tokens.

-spec mission_id(mission()) -> integer().
mission_id(#mission{id = Id}) -> Id.

-spec mission_session_id(mission()) -> binary().
mission_session_id(#mission{session_id = SessionId}) -> SessionId.

-spec mission_intent(mission()) -> binary().
mission_intent(#mission{intent = Intent}) -> Intent.

-spec mission_status(mission()) -> pending | in_progress | completed | failed.
mission_status(#mission{status = Status}) -> Status.

-spec mission_result(mission()) -> term().
mission_result(#mission{result = Result}) -> Result.

-spec mission_error(mission()) -> term().
mission_error(#mission{error = Error}) -> Error.