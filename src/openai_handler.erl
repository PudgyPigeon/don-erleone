-module(openai_handler).
-export([init/2]).

-define(JSON_TYPE, #{<<"content-type">> => <<"application/json">>}).

init(Req0, State) ->
    {ok, Body, Req} = cowboy_req:read_body(Req0),
    try
        #{<<"messages">> := Messages} = jsx:decode(Body, [return_maps]),
        #{<<"content">> := Prompt} = lists:last(Messages),

        handle_mission_response(consigliere:handle_mission(Prompt), Req, State)
    catch
        _:Error:Stack ->
            io:format("CRITICAL: Handler crash: ~p~nStack: ~p~n", [Error, Stack]),
            {ok, cowboy_req:reply(400, Req0), State}
    end.


handle_mission_response({ok, Answer, Meta}, Req, State) ->
    MissionId = maps:get(mission_id, Meta, null),
    
    IdStr = case MissionId of
        null -> <<"null">>;
        _    -> iolist_to_binary(io_lib:format("~p", [MissionId]))
    end,

    Resp = jsx:encode(#{
        <<"choices">> => [
            #{<<"message">> => #{
                <<"role">> => <<"assistant">>,
                <<"content">> => Answer
            }}
        ],
        <<"mission_id">> => IdStr
    }),

    {ok, cowboy_req:reply(200, ?JSON_TYPE, Resp, Req), State};


handle_mission_response({error, Reason}, Req, State) ->
    io:format("ALERT: Consigliere failed: ~p~n", [Reason]),
    ErrorResp = jsx:encode(#{
        <<"error">> => iolist_to_binary(io_lib:format("~p", [Reason]))
    }),
    {ok, cowboy_req:reply(500, ?JSON_TYPE, ErrorResp, Req), State}.