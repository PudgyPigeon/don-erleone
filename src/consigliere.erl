-module(consigliere).
-include("records.hrl").
-behaviour(gen_server).

-export([start_link/1, handle_mission/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

%% ------------------------------------------------------------------------

start_link(Config) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Config, []).

handle_mission(Prompt) ->
    gen_server:call(?MODULE, {ollama, Prompt}, infinity).

init(Config) ->
    {ok, Config}.   

%% ------------------------------------------------------------------------

handle_call({ollama, Prompt}, _From, Config) ->
    Result = case call_ollama(Prompt, Config) of
        {ok, Data} -> process_llm_response(Data, Prompt); 
        {error, _} = Err -> Err
    end,
    {reply, Result, Config};

handle_call(_Req, _From, Config) ->
    {reply, {error, unknown_call}, Config}.

handle_cast(_Msg, Config) -> {noreply, Config}.
handle_info(_Msg, Config) -> {noreply, Config}.

%% ------------------------------------------------------------------------

call_ollama(Prompt, Config) ->
    Payload = prepare_payload(Prompt, Config),
    perform_request(Payload, Config).

prepare_payload(Prompt, #config{model = M, stream = S, systemPrompt = SP}) ->
    jsx:encode(#{
        <<"model">> => iolist_to_binary(M),
        <<"prompt">> => iolist_to_binary(Prompt),
        <<"stream">> => S,
        <<"system">> => SP,
        <<"format">> => <<"json">>,
        <<"options">> => #{
            <<"num_predict">> => 4096,
            <<"temperature">> => 0.2
        }
    }).

perform_request(Payload, #config{ollama_url = URL, timeout = T}) ->
    io:format("Consigliere: Consulting brain at ~s~n", [URL]),
    Options = [{timeout, T}],
    Request = {URL, [], "application/json", Payload},
    
    case httpc:request(post, Request, Options, []) of
        {ok, {{_, 200, _}, _Headers, Body}} ->
            io:format("RAW OLLAMA DATA: ~s~n", [Body]),
            decode_json(Body);
        {ok, {{_, Status, _}, _, Body}} ->
            {error, {http_error, Status, Body}};
        {error, Reason} ->
            handle_error(Reason)
    end.

%% ------------------------------------------------------------------------

decode_json(Body) ->
    Bin = iolist_to_binary(Body),
    try
        Data = jsx:decode(Bin, [return_maps]),
        case maps:find(<<"reasoning">>, Data) of
            {ok, Thoughts} -> io:format("~n[BRAIN REASONING]:~n~s~n", [Thoughts]);
            _ -> ok
        end,
        {ok, Data}
    catch
       Error:Reason:Stack -> 
            io:format("CRITICAL: JSON Decode Failed!~nBody: ~s~nError: ~p:~p~nStack: ~p~n", 
                      [Bin, Error, Reason, Stack]),
            {error, malformed_json}
    end.
    
%% ------------------------------------------------------------------------

process_llm_response(OllamaData, Prompt) ->
    %% Different models put JSON in 'response', or 'thinking', or 'content'
    RawOptions = [
        maps:get(<<"response">>, OllamaData, <<>>),
        maps:get(<<"thinking">>, OllamaData, <<>>),
        maps:get(<<"content">>, OllamaData, <<>>)
    ],

    ActualData = find_json_payload(RawOptions),

    Response = maps:get(<<"response">>, ActualData, <<"Acknowledged.">>),
    IsDelegated = maps:get(<<"delegate_required">>, ActualData, false),
    
    route_mission(IsDelegated, ActualData, Response, Prompt).

find_json_payload([]) -> #{};
find_json_payload([<<>> | T]) -> find_json_payload(T);
find_json_payload([Bin | T]) ->
    try 
        jsx:decode(Bin, [return_maps])
    catch _:_ -> 
        find_json_payload(T)
    end.

%% ------------------------------------------------------------------------

route_mission(true, Data, Response, Prompt) ->
    Intent = maps:get(<<"tool_intent">>, Data, <<"unknown">>),
    {ok, Id} = mission_store:post_mission(Intent, Prompt),
    io:format("DEBUG: Mission ~p logged for: ~s~n", [Id, Intent]),
    {ok, Response, #{mission_id => Id}};

route_mission(false, _Data, Response, _Prompt) ->
    {ok, Response, #{mission_id => null}}.

%% ------------------------------------------------------------------------

handle_error(Reason) ->
    io:format("Consigliere Network Error: ~p~n", [Reason]),
    {error, Reason}.