%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_config).

-export([
  load_main_config/0,
  load_sub_agent_config/0,
  get_system_prompt/0,
  get_env_string/2,
  get_env_integer/2
]).

%% Accessors for config()
-export([
  config_ollama_url/1,
  config_model/1,
  config_timeout/1,
  config_stream/1,
  config_system_prompt/1
]).

%% Accessors for sub_config()
-export([
  sub_config_ollama_url/1,
  sub_config_mcp_url/1,
  sub_config_model/1,
  sub_config_timeout/1,
  sub_config_max_steps/1
]).

-export_type([config/0, sub_config/0]).

-record(config, {
  ollama_url :: string(),
  model :: string(),
  timeout :: integer(),
  stream :: boolean(),
  system_prompt :: binary()
}).

-record(sub_config, {
  ollama_url :: string(),
  mcp_url :: string(),
  model :: string(),
  timeout :: integer(),
  max_steps :: integer()
}).

-type config() :: #config{}.
-type sub_config() :: #sub_config{}.

%% =============================================================================
%% API
%% =============================================================================

-spec load_main_config() -> config().
load_main_config() ->
  #config{
    ollama_url = get_env_string(ollama_url,
      "http://localhost:11434/api/generate"),
    model = get_env_string(ollama_model, "qwen3.5:9b"),
    timeout = get_env_integer(timeout, 3600000),
    stream = false,
    system_prompt = get_system_prompt()
  }.

-spec load_sub_agent_config() -> sub_config().
load_sub_agent_config() ->
  #sub_config{
    ollama_url = get_env_string(ollama_url,
      "http://localhost:11434/api/generate"),
    model = get_env_string(sub_model, "qwen3.5:9b"),
    timeout = get_env_integer(sub_timeout, 120000),
    max_steps = get_env_integer(sub_max_steps, 10),
    mcp_url = get_env_string(mcp_url,
      "http://localhost:30090/mcp")
  }.

-spec get_system_prompt() -> binary().
get_system_prompt() ->
  <<
    "You are the Consigliere, the high-level controller of the Don Erleone SRE infrastructure.\n"
    "You delegate technical execution to your Caporegimes (autonomous agents).\n\n"
    "CRITICAL INSTRUCTIONS:\n"
    "1. For ANY task involving Kubernetes, Nix, or Infrastructure investigation, "
    "use tool_intent: 'autonomous'.\n"
    "2. Do not attempt to solve technical cluster issues yourself. Delegate them.\n"
    "3. You do not need to specify exact tool names; the Caporegime will discover them "
    "via the Haskell MCP.\n"
    "4. If a user asks for a 'deploy', 'query', or 'debug', use the 'autonomous' intent.\n"
    "5. Output STRICT JSON only.\n\n"
    "FORMAT:\n"
    "{\n"
    "  \"reasoning\": \"Why you are delegating\",\n"
    "  \"response\": \"Message to the user about the mission start\",\n"
    "  \"delegate_required\": true,\n"
    "  \"tool_intent\": \"autonomous\",\n"
    "  \"mcp_args\": {} \n"
    "}"
  >>.

%% =============================================================================
%% Accessors
%% =============================================================================

-spec config_ollama_url(config()) -> string().
config_ollama_url(#config{ollama_url = V}) -> V.

-spec config_model(config()) -> string().
config_model(#config{model = V}) -> V.

-spec config_timeout(config()) -> integer().
config_timeout(#config{timeout = V}) -> V.

-spec config_stream(config()) -> boolean().
config_stream(#config{stream = V}) -> V.

-spec config_system_prompt(config()) -> binary().
config_system_prompt(#config{system_prompt = V}) -> V.

-spec sub_config_ollama_url(sub_config()) -> string().
sub_config_ollama_url(#sub_config{ollama_url = V}) -> V.

-spec sub_config_mcp_url(sub_config()) -> string().
sub_config_mcp_url(#sub_config{mcp_url = V}) -> V.

-spec sub_config_model(sub_config()) -> string().
sub_config_model(#sub_config{model = V}) -> V.

-spec sub_config_timeout(sub_config()) -> integer().
sub_config_timeout(#sub_config{timeout = V}) -> V.

-spec sub_config_max_steps(sub_config()) -> integer().
sub_config_max_steps(#sub_config{max_steps = V}) -> V.

%% =============================================================================
%% Internal Helpers
%% =============================================================================

-spec get_env_string(atom(), string()) -> string().
get_env_string(Key, Default) ->
  OSKey = string:uppercase(atom_to_list(Key)),
  case os:getenv(OSKey) of
    false ->
      case application:get_env(don_erleone, Key) of
        {ok, Val} -> de_utils:to_list(Val);
        _ -> Default
      end;

    Val -> Val
  end.

-spec get_env_integer(atom(), integer()) -> integer().
get_env_integer(Key, Default) ->
  OSKey = string:uppercase(atom_to_list(Key)),
  case os:getenv(OSKey) of
    false ->
      case application:get_env(don_erleone, Key) of
        {ok, Val} when is_integer(Val) -> Val;
        {ok, Val} ->
          try de_utils:any_to_int(Val) catch _:_ -> Default end;
        _ -> Default
      end;

    Val ->
      try de_utils:any_to_int(Val) catch _:_ -> Default end
  end.
