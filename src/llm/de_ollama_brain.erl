%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_ollama_brain).

-export([build_payload/7,
         decode_line/1,
         accumulate/3,
         to_bin/1]).

%% =============================================================================
%% Payload Construction
%% =============================================================================

-spec build_payload(binary(), binary(), list(),
                    binary(), boolean(), list(), binary()) -> binary().

build_payload(Model, Prompt, Context, System, Stream,
              Tools, Path) ->
    Base = #{<<"model">> => to_bin(Model),
             <<"stream">> => Stream},
    Payload = case binary:match(to_bin(Path),
                                <<"/api/chat">>)
                  of
                  nomatch ->
                      %% /api/generate format
                      Base#{<<"prompt">> => to_bin(Prompt),
                            <<"system">> => to_bin(System),
                            <<"context">> => extract_context_ids(Context)};
                  _ ->
                      %% /api/chat format
                      Base#{<<"messages">> =>
                                build_messages(System, Context, Prompt)}
              end,
    jsx:encode(maybe_add_tools(Payload, Tools)).

-spec extract_context_ids(list()) -> list().

extract_context_ids([]) -> [];
extract_context_ids([H | _] = _Ctx) when is_map(H) ->
    %% /api/generate expects integers. If we have maps (chat history), drop them to avoid 400 errors.
    [];
extract_context_ids(Ctx) when is_list(Ctx) -> Ctx;
extract_context_ids(_) -> [].

-spec build_messages(binary(), list(),
                     binary()) -> list().

build_messages(System, Context, Prompt) ->
    Msgs = maybe_add_system(to_bin(System), Context),
    maybe_add_user(to_bin(Prompt), Msgs).

-spec maybe_add_system(binary(), list()) -> list().

maybe_add_system(<<>>, Context) -> Context;
maybe_add_system(_S,
                 [#{<<"role">> := <<"system">>} | _] = Context) ->
    Context;
maybe_add_system(S, Context) ->
    [#{<<"role">> => <<"system">>, <<"content">> => S}
     | Context].

-spec maybe_add_user(binary(), list()) -> list().

maybe_add_user(<<>>, Messages) -> Messages;
maybe_add_user(P, Messages) ->
    Messages ++
        [#{<<"role">> => <<"user">>, <<"content">> => P}].

%% =============================================================================
%% Stream Processing
%% =============================================================================

-spec decode_line(binary()) -> {ok, map()} |
                               {error, term()} |
                               skip.

decode_line(<<>>) -> skip;
decode_line(Line) ->
    try jsx:decode(Line, [return_maps]) of
        #{<<"error">> := Err} -> {error, {ollama_error, Err}};
        Msg -> {ok, Msg}
    catch
        _:_ -> skip
    end.

-spec accumulate(term(), map(),
                 function() | undefined) -> map().

accumulate(<<>>, Msg, CB) ->
    maybe_callback(CB, get_msg_content(Msg)),
    Msg;
accumulate(AccMap, #{<<"message">> := NewMsg}, CB)
    when is_map(AccMap) ->
    OldMsg = maps:get(<<"message">>, AccMap, #{}),
    maybe_callback(CB,
                   maps:get(<<"content">>, NewMsg, <<>>)),
    AccMap#{<<"message">> =>
                merge_messages(OldMsg, NewMsg)};
accumulate(_Acc, Msg, _CB) -> Msg.

-spec merge_messages(map(), map()) -> map().

merge_messages(Old, New) ->
    Merged = maps:merge(Old, New),
    Merged#{<<"content">> =>
                <<(maps:get(<<"content">>, Old, <<>>))/binary,
                  (maps:get(<<"content">>, New, <<>>))/binary>>,
            <<"tool_calls">> =>
                merge_tool_calls(maps:get(<<"tool_calls">>, Old, []),
                                 maps:get(<<"tool_calls">>, New, []))}.

-spec merge_tool_calls(list(), list()) -> list().

merge_tool_calls(Old, New) ->
    case {is_indexable(Old), is_indexable(New)} of
        {true, true} -> perform_index_merge(Old, New);
        _ -> Old ++ New
    end.

-spec is_indexable(list()) -> boolean().

is_indexable(L) ->
    lists:all(fun (I) ->
                      is_map(I) andalso maps:is_key(<<"index">>, I)
              end,
              L).

-spec perform_index_merge(list(), list()) -> list().

perform_index_merge(Old, New) ->
    OldMap = to_index_map(Old),
    NewMap = to_index_map(New),
    Indices = lists:usort(maps:keys(OldMap) ++
                              maps:keys(NewMap)),
    [merge_call(maps:get(I, OldMap, undefined),
                maps:get(I, NewMap, undefined))
     || I <- Indices].

-spec to_index_map(list()) -> map().

to_index_map(L) ->
    maps:from_list([{maps:get(<<"index">>, C, 0), C}
                    || C <- L]).

-spec merge_call(map() | undefined,
                 map() | undefined) -> map().

merge_call(undefined, New) -> New;
merge_call(Old, undefined) -> Old;
merge_call(Old, New) ->
    Merged = maps:merge(Old, New),
    Merged#{<<"function">> =>
                merge_function(maps:get(<<"function">>, Old, #{}),
                               maps:get(<<"function">>, New, #{}))}.

-spec merge_function(map(), map()) -> map().

merge_function(Old, New) ->
    Merged = maps:merge(Old, New),
    Merged#{<<"arguments">> =>
                <<(maps:get(<<"arguments">>, Old, <<>>))/binary,
                  (maps:get(<<"arguments">>, New, <<>>))/binary>>}.

-spec get_msg_content(map()) -> binary().

get_msg_content(#{<<"message">> :=
                      #{<<"content">> := C}}) ->
    C;
get_msg_content(_) -> <<>>.

%% =============================================================================
%% Helpers
%% =============================================================================

-spec maybe_add_tools(map(), list()) -> map().

maybe_add_tools(Payload, []) -> Payload;
maybe_add_tools(Payload, Tools) ->
    Payload#{<<"tools">> => Tools}.

-spec maybe_callback(function() | undefined,
                     binary()) -> ok.

maybe_callback(undefined, _) -> ok;
maybe_callback(CB, Content) -> CB(Content).

-spec to_bin(term()) -> binary().

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> list_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(Any) ->
    iolist_to_binary(io_lib:format("~p", [Any])).
