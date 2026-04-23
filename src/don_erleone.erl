-module(don_erleone).
-include("records.hrl").
-behaviour(supervisor).

-export([start_link/0, init/1]).

%% ------------------------------------------------------------------------

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init(_Args) ->
    _ = inets:start(),
    _ = mnesia:start(),
    ok = mission_store:init_db(),

    Config = load_config(),

    SupFlags = #{
        strategy => one_for_one,
        intensity => 5,
        period => 10
    },

    ChildSpecs = [
        #{
            id => the_front,
            start => {the_front, start_link, []}
        },
        #{
            id => consigliere,
            start => {consigliere, start_link, [Config]}
        }
    ],

    {ok, {SupFlags, ChildSpecs}}.

%% ------------------------------------------------------------------------

load_config() ->
    ModelRaw   = application:get_env(don_erleone, ollama_model, "llama3.1:8b"),
    URLRaw     = application:get_env(don_erleone, ollama_url, "http://localhost:11434/api/generate"),
    TimeoutRaw = application:get_env(don_erleone, timeout, 3600000),
    
    #config{
        ollama_url   = clean_string(URLRaw),
        model        = clean_string(ModelRaw),
        timeout      = parse_timeout(TimeoutRaw),
        stream       = false,
        systemPrompt = get_system_prompt()
    }.

%% ------------------------------------------------------------------------

clean_string(S) when is_list(S); is_binary(S) ->
    C = re:replace(S, "[^a-zA-Z0-9\\.\\:\\/\\-_]", "", [global, {return, list}]),
    strip_ghost_chars(C);
clean_string(S) -> S.

strip_ghost_chars(S) ->
    case lists:suffix("ee", S) or lists:suffix("bb", S) of
        true  -> lists:droplast(S);
        false -> S
    end.

parse_timeout(T) when is_integer(T) -> T;
parse_timeout(T) when is_list(T); is_binary(T) ->
    list_to_integer(re:replace(T, "[^0-9]", "", [global, {return, list}]));
parse_timeout(_) -> 3600000.

get_system_prompt() ->
    <<"You are the Consigliere to Don Erleone - Don Corleone's long lost brother
      You have a fleet of agents that handles tasks.
      
      CRITICAL INSTRUCTIONS:
      1. When a user asks for a task, you do not say 'I cannot' - unless you cannot find the MCP tool. 
      2. Instead, you must set 'delegate_required': true and 'tool_intent': 'tool_name or atom'.
      3. Your 'response' field should be a confirmation to the user that you are initiating the mission.
      
      OUTPUT FORMAT (STRICT JSON ONLY):
      {
        \"reasoning\": \"internal logic\",
        \"response\": \"message to user\",
        \"delegate_required\": true,
        \"tool_intent\": \"intent_name\",
        \"mcp_args\": {}
      }">>.