%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_openai_models_handler).

-export([init/2]).

-spec init(cowboy_req:req(), term()) -> {ok, cowboy_req:req(), term()}.
init(Req0, State) ->
  Models = [
    #{
      <<"id">> => <<"de_consigliere">>,
      <<"object">> => <<"model">>,
      <<"created">> => 1677610602,
      <<"owned_by">> => <<"don-erleone">>
    }
  ],
  RespBody = jsx:encode(#{
    <<"object">> => <<"list">>,
    <<"data">> => Models
  }),
  Req = cowboy_req:reply(200, #{<<"content-type">> => <<"application/json">>}, RespBody, Req0),
  {ok, Req, State}.
