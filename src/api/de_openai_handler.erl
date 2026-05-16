%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_openai_handler).

-behaviour(cowboy_handler).

-export([init/2]).

%% =============================================================================
%% Cowboy Callbacks
%% =============================================================================

-spec init(cowboy_req:req(), term()) -> {ok,
                                         cowboy_req:req(), term()}.

init(Req, State) ->
    handle_method(cowboy_req:method(Req), Req, State).

-spec handle_method(binary(), cowboy_req:req(),
                    term()) -> {ok, cowboy_req:req(), term()}.

handle_method(<<"POST">>, Req, State) ->
    decode_and_process(Req, State);
handle_method(_, Req, State) ->
    send_error(405, <<"Method Not Allowed">>, Req, State).

%% =============================================================================
%% Request Handling
%% =============================================================================

-spec decode_and_process(cowboy_req:req(),
                         term()) -> {ok, cowboy_req:req(), term()}.

decode_and_process(Req, State) ->
    {ok, Body, Req1} = cowboy_req:read_body(Req),
    process_body(safe_decode(Body), Req1, State).

-spec process_body({ok, map()} | {error, term()},
                   cowboy_req:req(), term()) -> {ok, cowboy_req:req(),
                                                 term()}.

process_body({ok, Params}, Req, State) ->
    dispatch_mission(Params, Req, State);
process_body({error, _}, Req, State) ->
    send_error(400, <<"Invalid JSON">>, Req, State).

-spec safe_decode(binary()) -> {ok, map()} |
                               {error, bad_json}.

safe_decode(Body) ->
    try {ok, jsx:decode(Body, [return_maps])} catch
        _:_ -> {error, bad_json}
    end.

-spec dispatch_mission(map(), cowboy_req:req(),
                       term()) -> {ok, cowboy_req:req(), term()}.

dispatch_mission(Params, Req, State) ->
    Prompt = extract_prompt(Params),
    Sid = maps:get(<<"user">>,
                   Params,
                   <<"default_session">>),
    IsStream = maps:get(<<"stream">>, Params, false),
    Ref = make_ref(),
    de_consigliere:handle_mission(Sid,
                                  Prompt,
                                  {self(), Ref}),
    execute_by_mode(IsStream, Req, Ref, State).

-spec execute_by_mode(boolean(), cowboy_req:req(),
                      reference(), term()) -> {ok, cowboy_req:req(), term()}.

execute_by_mode(true, Req, Ref, State) ->
    execute_stream(Req, Ref, State);
execute_by_mode(false, Req, Ref, State) ->
    execute_sync(Req, Ref, State).

%% =============================================================================
%% Sync Execution
%% =============================================================================

-spec execute_sync(cowboy_req:req(), reference(),
                   term()) -> {ok, cowboy_req:req(), term()}.

execute_sync(Req, Ref, State) ->
    receive
        Msg -> handle_sync_msg(Msg, Ref, Req, State)
        after 300000 ->
                  send_error(504, <<"Gateway Timeout">>, Req, State)
    end.

-spec handle_sync_msg(term(), reference(),
                      cowboy_req:req(), term()) -> {ok, cowboy_req:req(),
                                                    term()}.

handle_sync_msg({Ref, {done, Answer, Mid}}, Ref, Req,
                State) ->
    reply_json(200,
               de_openai_formatter:build_success(Answer, Mid),
               Req,
               State);
handle_sync_msg({Ref, {error, Reason}}, Ref, Req,
                State) ->
    reply_json(200,
               de_openai_formatter:build_error(Reason),
               Req,
               State);
handle_sync_msg(_, _Ref, Req, State) ->
    execute_sync(Req, _Ref, State).

%% =============================================================================
%% Stream Execution
%% =============================================================================

-spec execute_stream(cowboy_req:req(), reference(),
                     term()) -> {ok, cowboy_req:req(), term()}.

execute_stream(Req, Ref, State) ->
    Headers = #{<<"content-type">> =>
                    <<"text/event-stream">>,
                <<"cache-control">> => <<"no-cache">>},
    Req1 = cowboy_req:stream_reply(200, Headers, Req),
    stream_loop(Ref, Req1, null),
    {ok, Req1, State}.

-spec stream_loop(reference(), cowboy_req:req(),
                  term()) -> ok.

stream_loop(Ref, Req, Mid) ->
    receive
        Msg -> handle_stream_event(Msg, Ref, Req, Mid)
        after 300000 ->
                  de_openai_formatter:stream_error(Req, timeout, Mid)
    end.

-spec handle_stream_event(term(), reference(),
                          cowboy_req:req(), term()) -> ok.

handle_stream_event({Ref, {chunk, Content, NewMid}},
                    Ref, Req, _Mid) ->
    de_openai_formatter:stream_chunk(Req, Content, NewMid),
    stream_loop(Ref, Req, NewMid);
handle_stream_event({Ref, {done, Content, NewMid}}, Ref,
                    Req, _Mid) ->
    de_openai_formatter:stream_chunk(Req, Content, NewMid),
    de_openai_formatter:stream_done(Req, NewMid);
handle_stream_event({Ref, {error, Reason}}, Ref, Req,
                    Mid) ->
    de_openai_formatter:stream_error(Req, Reason, Mid);
handle_stream_event({'DOWN', _, process, _, Reason},
                    _Ref, Req, Mid) ->
    de_openai_formatter:stream_error(Req,
                                     {process_died, Reason},
                                     Mid);
handle_stream_event(_Unexpected, Ref, Req, Mid) ->
    stream_loop(Ref, Req, Mid).

%% =============================================================================
%% Helpers
%% =============================================================================

-spec extract_prompt(map()) -> binary().

extract_prompt(#{<<"messages">> := Msgs}) ->
    maps:get(<<"content">>, lists:last(Msgs), <<>>);
extract_prompt(_) -> <<>>.

-spec reply_json(integer(), binary(), cowboy_req:req(),
                 term()) -> {ok, cowboy_req:req(), term()}.

reply_json(Code, Payload, Req, State) ->
    Req1 = cowboy_req:reply(Code,
                            #{<<"content-type">> => <<"application/json">>},
                            Payload,
                            Req),
    {ok, Req1, State}.

-spec send_error(integer(), binary(), cowboy_req:req(),
                 term()) -> {ok, cowboy_req:req(), term()}.

send_error(Code, Msg, Req, State) ->
    reply_json(Code,
               de_openai_formatter:build_error(Msg),
               Req,
               State).
