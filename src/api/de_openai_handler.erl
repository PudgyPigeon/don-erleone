%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_openai_handler).

-behaviour(cowboy_rest).

-export([
  init/2,
  allowed_methods/2,
  content_types_accepted/2,
  handle_post/2
]).

-record(de_openai_handler_state, {}).

-type state() :: #de_openai_handler_state{}.

%% =============================================================================
%% Cowboy Callbacks
%% =============================================================================

-spec init(cowboy_req:req(), state()) -> {cowboy_rest, cowboy_req:req(), state()}.
init(Req, State) ->
  {cowboy_rest, Req, State}.

-spec allowed_methods(cowboy_req:req(), state()) -> {list(), cowboy_req:req(), state()}.
allowed_methods(Req, State) ->
  {[<<"POST">>], Req, State}.

-spec content_types_accepted(cowboy_req:req(), state()) -> {list(), cowboy_req:req(), state()}.
content_types_accepted(Req, State) ->
  {[{{<<"application">>, <<"json">>, []}, handle_post}], Req, State}.

%% =============================================================================
%% Request Handling
%% =============================================================================

-spec handle_post(cowboy_req:req(), state()) -> {true, cowboy_req:req(), state()} | {stop, cowboy_req:req(), state()}.
handle_post(Req, State) ->
  {ok, Body, Req1} = cowboy_req:read_body(Req),
  try jsx:decode(Body, [return_maps]) of
    Params ->
      process_request(Params, Req1, State)
  catch
    _:_ ->
      send_error(400, <<"Invalid JSON">>, Req1, State)
  end.

process_request(Params, Req, State) ->
  Prompt = extract_prompt(Params),
  SessionId = maps:get(<<"user">>, Params, <<"default_session">>),
  IsStream = maps:get(<<"stream">>, Params, false),

  %% The Tag for async communication
  Ref = make_ref(),
  Self = self(),
  From = {Self, Ref},

  %% Orchestration: Hand off to de_consigliere
  de_consigliere:handle_mission(SessionId, Prompt, From),

  case IsStream of
    true ->
      execute_stream(Req, Ref, State);
    false ->
      execute_sync(Req, Ref, State)
  end.

%% =============================================================================
%% Sync Execution
%% =============================================================================

execute_sync(Req, Ref, State) ->
  receive
    {Ref, {done, Answer, MissionId}} ->
      Payload = de_openai_formatter:build_success(Answer, MissionId),
      Req1 = cowboy_req:set_resp_body(Payload, Req),
      {true, Req1, State};
    {Ref, {error, Reason}} ->
      Payload = de_openai_formatter:build_error(Reason),
      Req1 = cowboy_req:set_resp_body(Payload, Req),
      {true, Req1, State}
  after 300000 ->
      send_error(504, <<"Gateway Timeout">>, Req, State)
  end.

%% =============================================================================
%% Stream Execution
%% =============================================================================

execute_stream(Req, Ref, State) ->
  Req1 = cowboy_req:stream_reply(200, #{
    <<"content-type">> => <<"text/event-stream">>,
    <<"cache-control">> => <<"no-cache">>
  }, Req),

  run_stream_loop(undefined, Ref, Req1, null),
  {stop, Req1, State}.

run_stream_loop(Conn, Ref, Req, MissionId) ->
  receive
    Msg -> handle_stream_msg(Msg, Conn, Ref, Req, MissionId)
  after 300000 ->
    de_openai_formatter:stream_error(Req, timeout, MissionId)
  end.

handle_stream_msg({Ref, {chunk, Content, Mid}}, Conn, Ref, Req, _Mid) ->
  de_openai_formatter:stream_chunk(Req, Content, Mid),
  run_stream_loop(Conn, Ref, Req, Mid);
handle_stream_msg({Ref, {done, Content, Mid}}, _Conn, Ref, Req, _Mid) ->
  de_openai_formatter:stream_chunk(Req, Content, Mid),
  de_openai_formatter:stream_done(Req, Mid);
handle_stream_msg({Ref, {error, Reason}}, _Conn, Ref, Req, MissionId) ->
  de_openai_formatter:stream_error(Req, Reason, MissionId);
handle_stream_msg({'DOWN', _, process, Conn, Reason}, Conn, _Ref, Req, MissionId) ->
  logger:error(#{event => process_died, pid => Conn, reason => Reason}),
  de_openai_formatter:stream_error(Req, process_died, MissionId);
handle_stream_msg(Unexpected, Conn, Ref, Req, MissionId) ->
  logger:warning(#{event => unexpected_msg, msg => Unexpected}),
  run_stream_loop(Conn, Ref, Req, MissionId).

%% =============================================================================
%% Helpers
%% =============================================================================

extract_prompt(#{<<"messages">> := Msgs}) ->
  LastMsg = lists:last(Msgs),
  maps:get(<<"content balance">>, LastMsg, maps:get(<<"content">>, LastMsg, <<>>));
extract_prompt(_) ->
  <<>>.

send_error(Code, Msg, Req, State) ->
  Payload = de_openai_formatter:build_error(Msg),
  Req1 = cowboy_req:reply(Code, #{<<"content-type">> => <<"application/json">>}, Payload, Req),
  {stop, Req1, State}.