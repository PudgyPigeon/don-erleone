-module(mission_store).

-include("records.hrl").

-export([init_db/0, post_mission/2, get_mission/1, get_pending/0]).

%% disc_copies -> Persist to disk for durability -> RAM for POC
init_db() ->
    case
        mnesia:create_table(mission, [
            {attributes, record_info(fields, mission)},
            {ram_copies, [node()]}
        ])
    of
        {atomic, ok} -> ok;
        {aborted, {already_exists, mission}} -> ok;
        {aborted, Reason} -> {error, Reason}
    end.

post_mission(Intent, Prompt) ->
    Id = make_ref(),
    Record = #mission{
        id = Id,
        intent = Intent,
        raw_prompt = Prompt,
        timestamp = erlang:system_time(second)
    },
    F = fun() -> mnesia:write(Record) end,
    case mnesia:transaction(F) of
        {atomic, ok} -> {ok, Id};
        {aborted, Reason} -> {error, Reason}
    end.

get_mission(Id) ->
    F = fun() -> mnesia:read(mission, Id) end,
    case mnesia:transaction(F) of
        {atomic, [Result]} -> {ok, Result};
        {atomic, []} -> {error, not_found};
        {aborted, Reason} -> {error, Reason}
    end.

get_pending() ->
    ok.
