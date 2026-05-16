%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_health_handler).

-export([init/2]).

-spec init(cowboy_req:req(), term()) -> {ok,
                                         cowboy_req:req(), term()}.

init(Req0, State) ->
    Body = jsx:encode(#{<<"status">> => <<"ok">>}),
    Req = cowboy_req:reply(200,
                           #{<<"content-type">> => <<"application/json">>},
                           Body,
                           Req0),
    {ok, Req, State}.
