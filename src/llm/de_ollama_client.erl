%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_ollama_client).

-export([
  generate/4,
  generate/5,
  generate_with_tools/5,
  handle_stream_event/4
]).

-type context() :: #{
  conn := pid(),
  ref := reference(),
  host := string(),
  tmo := integer(),
  is_stream := boolean(),
  cb := function() | undefined
}.

%% =============================================================================
%% API
%% =============================================================================

-spec generate(binary(), binary(), list(), map()) -> {ok, map()} | {error, term()}.
generate(Prompt, System, Context, Opts) ->
  generate(Prompt, System, Context, [], Opts).

-spec generate(binary(), binary(), list(), list(), map()) -> {ok, map()} | {error, term()}.
generate(Prompt, System, Context, Tools, Opts) ->
  URL = maps:get(url, Opts),
  {Host, Port, Path} = de_utils:parse_url(URL),
  Payload = de_ollama_brain:build_payload(maps:get(model, Opts), Prompt, Context, System, maps:get(stream, Opts, false), Tools, Path),
  open_and_call(Host, Port, Path, Payload, Opts).

-spec generate_with_tools(binary(), binary(), list(), list(), map()) -> {ok, map()} | {error, term()}.
generate_with_tools(Prompt, System, Context, Tools, Opts) ->
  generate(Prompt, System, Context, Tools, Opts).

%% =============================================================================
%% HTTP Client (Gun)
%% =============================================================================

-spec open_and_call(string(), integer(), string(), binary(), map()) -> {ok, map()} | {error, term()}.
open_and_call(Host, Port, Path, Payload, Opts) ->
  case gun:open(Host, Port) of
    {ok, Conn} ->
      {ok, _} = gun:await_up(Conn, 10000),
      perform_call(Conn, Host, Path, Payload, Opts);
    {error, Reason} ->
      {error, {connection_failed, Reason}}
  end.

-spec perform_call(pid(), string(), string(), binary(), map()) -> {ok, map()} | {error, term()}.
perform_call(Conn, Host, Path, Payload, Opts) ->
  Ref = gun:post(Conn, Path, [{<<"content-type">>, <<"application/json">>}], Payload),
  Ctx = build_context(Conn, Ref, Host, Opts),
  Result = message_loop(Ctx, <<>>, <<>>),
  gun:close(Conn),
  Result.

-spec build_context(pid(), reference(), string(), map()) -> context().
build_context(Conn, Ref, Host, Opts) ->
  #{
    conn => Conn,
    ref => Ref,
    host => Host,
    tmo => maps:get(timeout, Opts, 30000),
    is_stream => maps:get(stream, Opts, false),
    cb => maps:get(callback, Opts, undefined)
  }.

-spec message_loop(context(), binary(), term()) -> {ok, map()} | {error, term()}.
message_loop(#{tmo := Tmo, host := Host} = Ctx, Buffer, Acc) ->
  receive
    Msg -> dispatch(handle_stream_event(Msg, Ctx, Buffer, Acc), Ctx)
  after Tmo ->
    handle_timeout(Host, Tmo)
  end.

-spec dispatch({next, binary(), term()} | {ok, map()} | {error, term()}, context()) ->
  {ok, map()} | {error, term()}.
dispatch({next, B, A}, Ctx) -> message_loop(Ctx, B, A);

dispatch({ok, Result}, _) -> {ok, Result};

dispatch({error, Reason}, _) -> {error, Reason}.

%% =============================================================================
%% Event Handlers (Pure Directives)
%% =============================================================================

-spec handle_stream_event(term(), context(), binary(), term()) ->
  {next, binary(), term()} | {ok, map()} | {error, term()}.

%% --- Happy Paths ---
handle_stream_event({gun_response, C, R, IsFin, Status, _Headers}, #{conn := C, ref := R} = Ctx, B, A) ->
  handle_status(Status, IsFin, Ctx, B, A);

handle_stream_event({gun_data, C, R, nofin, Data}, #{conn := C, ref := R} = Ctx, Buffer, Acc) ->
  handle_data(Ctx, <<Buffer/binary, Data/binary>>, Acc);

handle_stream_event({gun_data, C, R, fin, Data}, #{conn := C, ref := R} = Ctx, Buffer, Acc) ->
  handle_final_data(<<Buffer/binary, Data/binary>>, Ctx, Acc);

%% --- Error Paths ---
handle_stream_event({gun_error, C, R, Reason}, #{conn := C, ref := R, host := Host}, _B, _A) ->
  logger:error(#{event => ollama_stream_error, host => Host, error => Reason}),
  {error, {stream_err, Reason}};

handle_stream_event({gun_error, C, Reason}, #{conn := C, host := Host}, _B, _A) ->
  logger:error(#{event => ollama_gun_error, host => Host, error => Reason}),
  {error, {gun_err, Reason}};

%% Combined gun_down handlers using a generic tuple match with connection verification
handle_stream_event(GunDown, #{conn := C, host := Host}, _B, _A) 
  when element(1, GunDown) =:= gun_down, element(2, GunDown) =:= C ->
  logger:error(#{event => ollama_connection_down, host => Host}),
  {error, connection_closed};

%% --- Fallback ---
handle_stream_event(Unknown, _Ctx, Buffer, Acc) ->
  logger:warning(#{event => unknown_gun_event, msg => Unknown}),
  {next, Buffer, Acc}.

handle_status(200, _IsFin, _Ctx, B, A) -> {next, B, A};

handle_status(Status, _IsFin, _Ctx, _B, _A) -> {error, {http_status, Status}}.

%% =============================================================================
%% Data Logic Dispatch
%% =============================================================================

-spec handle_data(context(), binary(), term()) -> {next, binary(), term()}.
handle_data(#{is_stream := true} = Ctx, Buffer, Acc) ->
  {NextBuf, NewAcc} = de_ollama_client_logic:process_ndjson(Buffer, Acc, maps:get(cb, Ctx)),
  {next, NextBuf, NewAcc};

handle_data(#{is_stream := false}, Buffer, Acc) ->
  {next, Buffer, Acc}.

-spec handle_final_data(binary(), context(), term()) -> {ok, map()} | {error, term()}.
handle_final_data(FinalBody, #{is_stream := true, cb := CB}, Acc) ->
  {Remainder, TempAcc} = de_ollama_client_logic:process_ndjson(FinalBody, Acc, CB),
  {ok, extract_message(de_ollama_client_logic:finalize(Remainder, TempAcc, CB))};

handle_final_data(FinalBody, #{is_stream := false, cb := CB}, Acc) ->
  case de_ollama_client_logic:finalize(FinalBody, Acc, CB) of
    {error, _} = Err -> Err;
    Result -> {ok, extract_message(Result)}
  end.

%% =============================================================================
%% Utilities
%% =============================================================================

-spec extract_message(map()) -> map().
extract_message(#{<<"message">> := Msg}) -> Msg;

extract_message(Msg) -> Msg.

-spec handle_timeout(string(), integer()) -> {error, timeout}.
handle_timeout(Host, Tmo) ->
  logger:error(#{event => ollama_request_timeout, host => Host, timeout => Tmo}),
  {error, timeout}.