-module(entrypoint).

-behaviour(application).

-export([start/2, stop/1]).

start(_Type, _Args) -> don_erleone:start_link().

stop(_State) -> ok.
