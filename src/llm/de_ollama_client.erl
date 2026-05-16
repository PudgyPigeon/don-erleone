%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_ollama_client).

-export([
  generate/4,
  generate/5,
  generate_with_tools/5,
  handle_stream_event/4
]).

%% =============================================================================
%% API
%% =============================================================================

generate(Prompt, System, Context, Opts) ->
  generate(Prompt, System, Context, [], Opts).

generate(Prompt, System, Context, Tools, Opts) ->
  URL = maps:get(url, Opts),
  {Host, Port, Path} = de_utils:parse_url(URL),
  Payload = de_ollama_brain:build_payload(maps:get(model, Opts), Prompt, Context, System, maps:get(stream, Opts, false), Tools, Path),
  open_and_call(Host, Port, Path, Payload, Opts).

generate_with_tools(Prompt, System, Context, Tools, Opts) ->
  generate(Prompt, System, Context, Tools, Opts).

%% =============================================================================
%% HTTP Client (Gun)
%% =============================================================================

open_and_call(Host, Port, Path, Payload, Opts) ->
  case gun:open(Host, Port) of
    {ok, Conn} ->
      {ok, _} = gun:await_up(Conn, 10000),
      perform_call(Conn, Host, Path, Payload, Opts);
    {error, Reason} ->
      {error, {connection_failed, Reason}}
  end.

perform_call(Conn, Host, Path, Payload, Opts) ->
  Ref = gun:post(Conn, Path, [{<<"content-type">>, <<"application/json">>}], Payload),
  Ctx = build_context(Conn, Ref, Host, Opts),
  Result = message_loop(Ctx, <<>>, <<>>),
  gun:close(Conn),
  Result.

build_context(Conn, Ref, Host, Opts) ->
  #{
    conn => Conn,
    ref => Ref,
    host => Host,
    tmo => maps:get(timeout, Opts, 30000),
    is_stream => maps:get(stream, Opts, false),
    cb => maps:get(callback, Opts, undefined)
  }.

message_loop(#{tmo := Tmo, host := Host} = Ctx, Buffer, Acc) ->
  receive
    Msg -> dispatch(handle_stream_event(Msg, Ctx, Buffer, Acc), Ctx)
  after Tmo ->
    handle_timeout(Host, Tmo)
  end.

dispatch({next, B, A}, Ctx) -> message_loop(Ctx, B, A);
dispatch({ok, Result}, _) -> {ok, Result};
dispatch({error, Reason}, _) -> {error, Reason}.

%% =============================================================================
%% Event Handlers (Pure Directives)
%% =============================================================================

handle_stream_event({gun_response, C, R, IsFin, Status, _Headers}, #{conn := C, ref := R} = Ctx, B, A) ->
  handle_status(Status, IsFin, Ctx, B, A);
handle_stream_event({gun_data, C, R, nofin, Data}, #{conn := C, ref := R} = Ctx, Buffer, Acc) ->
  handle_data(Ctx, <<Buffer/binary, Data/binary>>, Acc);
handle_stream_event({gun_data, C, R, fin, Data}, #{conn := C, ref := R} = Ctx, Buffer, Acc) ->
  handle_final_data(<<Buffer/binary, Data/binary>>, Ctx, Acc);
handle_stream_event({gun_error, C, R, Reason}, #{conn := C, ref := R, host := Host}, _B, _A) ->
  logger:error(#{event => ollama_stream_error, host => Host, error => Reason}),
  {error, {stream_err, Reason}};
handle_stream_event({gun_error, C, Reason}, #{conn := C, host := Host}, _B, _A) ->
  logger:error(#{event => ollama_gun_error, host => Host, error => Reason}),
  {error, {gun_err, Reason}};
handle_stream_event({gun_down, C, _Proto, _Reason, _Killed, _Unprocessed}, #{conn := C, host := Host}, _B, _A) ->
  logger:error(#{event => ollama_connection_down, host => Host}),
  {error, connection_closed};
handle_stream_event({gun_down, C, _Proto, _Reason, _Killed}, #{conn := C, host := Host}, _B, _A) ->
  logger:error(#{event => ollama_connection_down, host => Host}),
  {error, connection_closed};
handle_stream_event(Unknown, _Ctx, Buffer, Acc) ->
  logger:warning(#{event => unknown_gun_event, msg => Unknown}),
  {next, Buffer, Acc}.

handle_status(200, _IsFin, _Ctx, B, A) -> {next, B, A};
handle_status(Status, _IsFin, _Ctx, _B, _A) -> {error, {http_status, Status}}.

%% =============================================================================
%% Data Logic Dispatch
%% =============================================================================

handle_data(#{is_stream := true} = Ctx, Buffer, Acc) ->
  {NextBuf, NewAcc} = de_ollama_client_logic:process_ndjson(Buffer, Acc, maps:get(cb, Ctx)),
  {next, NextBuf, NewAcc};
handle_data(#{is_stream := false}, Buffer, Acc) ->
  {next, Buffer, Acc}.

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

extract_message(#{<<"message">> := Msg}) -> Msg;
extract_message(Msg) -> Msg.

handle_timeout(Host, Tmo) ->
  logger:error(#{event => ollama_request_timeout, host => Host, timeout => Tmo}),
  {error, timeout}.