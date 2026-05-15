%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

%% @doc Shared HTTP client for Ollama API calls via Gun.
-module(de_ollama_client).

-export([
  generate/3,
  generate/4,
  generate/5,
  generate_with_tools/5
]).

%% =============================================================================
%% API
%% =============================================================================

-spec generate(binary(), binary(), map()) -> {ok, term()} | {error, term()}.
generate(Prompt, System, Opts) ->
  generate(Prompt, System, [], Opts, undefined).

-spec generate(binary(), binary(), list(), map()) -> {ok, term()} | {error, term()}.
generate(Prompt, System, Context, Opts) ->
  generate(Prompt, System, Context, Opts, undefined).

-spec generate(binary(), binary(), list(), map(), function() | undefined) ->
  {ok, term()} | {error, term()}.
generate(Prompt, System, Context, Opts, Callback) ->
  execute_request(Prompt, System, Context, [], Opts, Callback).

-spec generate_with_tools(binary(), binary(), list(), list(), map()) ->
  {ok, term()} | {error, term()}.
generate_with_tools(Prompt, System, Context, Tools, Opts) ->
  execute_request(Prompt, System, Context, Tools, Opts, undefined).

%% =============================================================================
%% Request Flow
%% =============================================================================

execute_request(Prompt, System, Context, Tools, Opts, Callback) ->
  URL = maps:get(url, Opts),
  Model = maps:get(model, Opts),
  Timeout = maps:get(timeout, Opts, 120000),
  Stream = maps:get(stream, Opts, false),

  Payload = de_ollama_brain:build_payload(Model, Prompt, Context, System, Stream, Tools),
  Endpoint = resolve_chat_endpoint(URL),

  do_http_call(Endpoint, Payload, Timeout, Stream, Callback).

%% =============================================================================
%% HTTP Execution
%% =============================================================================

do_http_call(Endpoint, Payload, Timeout, IsStream, Callback) ->
  URI = uri_string:parse(Endpoint),
  Host = maps:get(host, URI),
  Port = maps:get(port, URI, 80),
  Path = maps:get(path, URI),

  StartTime = erlang:system_time(microsecond),
  telemetry:execute([don_erleone, ollama, request, start], #{time => StartTime},
    #{host => Host, path => Path}),

  case establish_conn(Host, Port) of
    {ok, ConnPid} ->
      Result = perform_request(ConnPid, Path, Payload, Timeout, IsStream, Callback, Host),

      telemetry:execute([don_erleone, ollama, request, stop],
        #{duration => erlang:system_time(microsecond) - StartTime},
        #{host => Host, success => (case Result of {ok, _} -> true; _ -> false end)}),

      gun:close(ConnPid),
      Result;
    {error, {Type, Reason}} ->
      telemetry:execute([don_erleone, ollama, request, error], #{},
        #{host => Host, reason => Type, error => Reason}),
      {error, {Type, Reason}}
  end.

establish_conn(Host, Port) ->
  case gun:open(to_list(Host), Port, #{connect_timeout => 10000, protocols => [http]}) of
    {ok, ConnPid} -> try_await_up(ConnPid);
    {error, Reason} -> {error, {open_failed, Reason}}
  end.

try_await_up(ConnPid) ->
  try gun:await_up(ConnPid, 10000) of
    {ok, _} -> {ok, ConnPid};
    {error, Reason} -> gun:close(ConnPid), {error, {await_up_failed, Reason}}
  catch
    _:Error -> gun:close(ConnPid), {error, {await_up_exception, Error}}
  end.

perform_request(ConnPid, Path, Payload, Timeout, IsStream, Callback, Host) ->
  Headers = [{<<"content-type">>, <<"application/json">>}],
  StreamRef = gun:post(ConnPid, Path, Headers, Payload),
  stream_loop(ConnPid, StreamRef, Timeout, IsStream, <<>>, <<>>, Callback, Host).

%% =============================================================================
%% Stream Loop
%% =============================================================================

stream_loop(Conn, Ref, Tmo, IsStream, Buffer, Acc, CB, Host) ->
  receive
    {gun_response, Conn, Ref, nofin, 200, _} ->
      stream_loop(Conn, Ref, Tmo, IsStream, Buffer, Acc, CB, Host);
    {gun_response, Conn, Ref, _, Status, _} when Status >= 400 ->
      {error, {http_status, Status}};
    {gun_data, Conn, Ref, nofin, Data} ->
      handle_data(Conn, Ref, Tmo, IsStream, <<Buffer/binary, Data/binary>>, Acc, CB, Host);
    {gun_data, Conn, Ref, fin, Data} ->
      handle_final_data(<<Buffer/binary, Data/binary>>, IsStream, Acc, CB);
    {gun_error, Conn, Ref, Reason} -> {error, {stream_err, Reason}};
    {gun_error, Conn, Reason} -> {error, {gun_err, Reason}};
    {gun_down, Conn, _, _, _, _} -> {error, connection_closed}
  after Tmo -> {error, timeout}
  end.

handle_data(Conn, Ref, Tmo, true, Buffer, Acc, CB, Host) ->
  {NextBuf, NewAcc} = process_ndjson(Buffer, Acc, CB),
  stream_loop(Conn, Ref, Tmo, true, NextBuf, NewAcc, CB, Host);
handle_data(Conn, Ref, Tmo, false, Buffer, Acc, CB, Host) ->
  stream_loop(Conn, Ref, Tmo, false, Buffer, Acc, CB, Host).

handle_final_data(FinalBody, true, Acc, CB) ->
  {Remainder, TempAcc} = process_ndjson(FinalBody, Acc, CB),
  {ok, finalize(Remainder, TempAcc, CB)};
handle_final_data(FinalBody, false, Acc, CB) ->
  case finalize(FinalBody, Acc, CB) of
    {error, _} = Err -> Err;
    Result -> {ok, Result}
  end.

process_ndjson(Buffer, Acc, CB) ->
  case binary:split(Buffer, <<"\n">>) of
    [Line, Rest] ->
      NewAcc = finalize(Line, Acc, CB),
      process_ndjson(Rest, NewAcc, CB);
    [Remainder] ->
      {Remainder, Acc}
  end.

finalize(Line, Acc, CB) ->
  case de_ollama_brain:decode_line(Line) of
    {ok, Msg} -> de_ollama_brain:accumulate(Acc, Msg, CB);
    {error, Reason} -> {error, Reason};
    skip -> Acc
  end.

%% =============================================================================
%% Utilities
%% =============================================================================

resolve_chat_endpoint(URL) ->
  L = to_list(URL),
  lists:flatten(string:replace(L, "/api/generate", "/api/chat")).

to_list(B) when is_binary(B) -> binary_to_list(B);
to_list(L) when is_list(L) -> L.