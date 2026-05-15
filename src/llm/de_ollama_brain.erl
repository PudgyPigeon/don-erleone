%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_ollama_brain).

-export([
  build_payload/6,
  decode_line/1,
  accumulate/3,
  to_bin/1
]).

%% =============================================================================
%% Payload Construction
%% =============================================================================

-spec build_payload(binary(), binary(), list(), binary(), boolean(), list()) -> binary().
build_payload(Model, Prompt, Context, System, Stream, Tools) ->
  Messages = build_messages(System, Context, Prompt),
  Base = #{
    <<"model">> => to_bin(Model),
    <<"messages">> => Messages,
    <<"stream">> => Stream
  },
  jsx:encode(maybe_add_tools(Base, Tools)).

build_messages(System, Context, Prompt) ->
  Sys = case to_bin(System) of <<>> -> []; S -> [#{<<"role">> => <<"system">>, <<"content">> => S}] end,
  User = case to_bin(Prompt) of <<>> -> []; P -> [#{<<"role">> => <<"user">>, <<"content">> => P}] end,
  Sys ++ Context ++ User.

%% =============================================================================
%% Stream Processing
%% =============================================================================

-spec decode_line(binary()) -> {ok, map()} | {error, term()} | skip.
decode_line(<<>>) -> skip;
decode_line(Line) ->
  try jsx:decode(Line, [return_maps]) of
    #{<<"error">> := Err} -> {error, {ollama_error, Err}};
    Msg -> {ok, Msg}
  catch _:_ -> skip end.

-spec accumulate(term(), map(), function() | undefined) -> term().
accumulate(Acc, #{<<"message">> := #{<<"content">> := C} = Msg}, CB) ->
  maybe_callback(CB, C),
  case Acc of
    Prefix when is_binary(Prefix) -> [Prefix, C];
    Prefix when is_list(Prefix) -> [Prefix, C];
    _ -> Msg
  end;
accumulate(Acc, Msg, _CB) ->
  Msg.

%% =============================================================================
%% Helpers
%% =============================================================================

maybe_add_tools(Payload, []) -> Payload;
maybe_add_tools(Payload, Tools) -> Payload#{<<"tools">> => Tools}.

maybe_callback(undefined, _) -> ok;
maybe_callback(CB, Content) -> CB(Content).

-spec to_bin(term()) -> binary().
to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> list_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(Any) -> iolist_to_binary(io_lib:format("~p", [Any])).