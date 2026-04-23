# Don Erleone: An Erlang/OTP AI Agent Orchestration Framework (First Draft)

Don Erleone is a supervisor-tree based framework designed to bridge the gap between Large Language Models (LLMs) and systems-level orchestration (Kubernetes, Nix, etc.). It uses the BEAM for its native concurrency and fault isolation when managing agentic tasks.

He's also Don Corleone's long lost LLM brother.

## Architecture

This repository contains the **open-core** components of the framework:

*   **`consigliere`:** A gen_server that interfaces with Ollama. It parses prompts into structured JSON intents.
*   **`mission_store`:** A local Mnesia implementation for tracking mission state and ensuring data persistence across node restarts.
*   **`the_front`:** A Cowboy-based HTTP gateway providing an OpenAI-compatible interface

## Project Scope

This repository provides the entry interface. It handles intent parsing and pushing to Mnesia for future mission state management.

The specific logic for swarm consensus is maintained in a private fork. Like Paulie in the joint, the Don uses a razor to slice the garlic so thin that it liquifies in the pan with just a little oil. It’s a very good system.

## Setup and Execution

### Prerequisites
* Docker
* Nix + Flakes which is used to provide the following:
* Erlang/OTP 24+ 
* `rebar3`
* Ollama running locally (or remotely) with the default model pulled (`ollama pull llama3.1:8b`).

### Configuration
Adjust config/sys.config for your local environment:

```erlang
{don_erleone, [
    {ollama_model, "llama3.1:8b"}, 
    {ollama_url, "http://localhost:11434/api/generate"},
    {timeout, 3600000}
]}
```

### Building and Running
To see justfile commands:
```bash
just
```

Compile the project and start the OTP application in an interactive shell manually:

```bash
docker compose up
rebar3 shell # Or you can use the justfile too

# Then send this 
curl -X POST http://localhost:8080/v1/chat/completions -H "Content-Type: application/json" -d '{
           "model": "don-erleone",
           "messages": [{"role": "user", "content": "Can you delegate a task into the Mnesia queue please?"}^C
         }'
```
On startup, the framework will initialize Mnesia, start the Cowboy-powered Front, and spin up the Consigliere.

```bash
# You can check the Mnesia table in the REPL:
 mnesia:dirty_all_keys(mission).
```

## 🛠️ The Consigliere's Strict Output
The Consigliere enforces a strict JSON schema to ensure predictable delegation to sub-agents:

```json
{
  "reasoning": "internal logic",
  "response": "message to user",
  "delegate_required": true,
  "tool_intent": "intent_name",
  "mcp_args": {}
}
```