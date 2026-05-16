%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_ollama_client_logic).

-export([
  process_ndjson/3,
  finalize/3
]).

%% =============================================================================
%% Pure Logic: JSON Stream Processing
%% =============================================================================

-spec process_ndjson(binary(), term(), function() | undefined) -> {binary(), term()}.
process_ndjson(Buffer, Acc, CB) ->
  case binary:split(Buffer, <<"\n">>) of
    [Line, Rest] ->
      NewAcc = finalize(Line, Acc, CB),
      process_ndjson(Rest, NewAcc, CB);
    [Remainder] ->
      {Remainder, Acc}
  end.

-spec finalize(binary(), term(), function() | undefined) -> term().
finalize(Line, Acc, CB) ->
  handle_line_decode(de_ollama_brain:decode_line(Line), Acc, CB).

-spec handle_line_decode({ok, map()} | {error, term()} | skip, term(), function() | undefined) -> term().
handle_line_decode({ok, Msg}, Acc, CB) ->
  de_ollama_brain:accumulate(Acc, Msg, CB);
handle_line_decode({error, Reason}, _Acc, _CB) ->
  {error, Reason};
handle_line_decode(skip, Acc, _CB) ->
  Acc.
