%% Global config for the agent
-record(config, {
    ollama_url   :: string(),
    model        :: string(),
    timeout      :: integer(),
    stream       :: boolean(), 
    systemPrompt :: binary()
}).

%% The mission ledger entry
-record(mission, {
    id,               %% Unique reference (ref or uuid)
    intent,           %% k8s_status, check_mcp, etc.
    raw_prompt,       %% Original user input
    status = pending, %% pending, in_progress, completed, failed
    timestamp
}).