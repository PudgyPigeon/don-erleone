# Next steps:
- "The Wire"
- Phoenix dashboard
- Telemetry
- BEAM VM cluster 
- Swarm Timeline - Coordination
- Document processing
- Decoupled context

```
don_erleone (Top-Level Supervisor | Strategy: one_for_one)
 │
 ├── the_front (Cowboy HTTP/SSE Ingress Worker)
 │    └── Purpose: Handles incoming API requests and holds streaming connections.
 │
 └── the_commission (Core Sub-Supervisor | Strategy: rest_for_one)
      │    └── Purpose: Enforces shared fate between reasoning and execution.
      │
      ├── underboss (Execution Supervisor | Starts First)
      │    │
      │    └── caporegime_pool (Poolboy Manager)
      │         └── Purpose: Workers that execute Nix/K8s tool calls via the small LLM.
      │
      └── consigliere_pool (Reasoning Poolboy Manager | Starts Second)
           │
           └── Purpose: Workers that hold the system prompt and route intents via the large LLM.
```

--------------

# Don Erleone — Architecture

> An Erlang/OTP agentic AI orchestrator with a Mafia-themed supervision hierarchy.
> Exposes an OpenAI-compatible HTTP API, routes user prompts through a "reasoning" LLM,
> and delegates infrastructure tasks to "execution" workers powered by a smaller LLM.

---

## 1. Supervision Tree

```mermaid
graph TD
    E["entrypoint (application)"] --> D

    D["don_erleone (supervisor)<br/>strategy: one_for_one"]
    D --> TF["the_front (gen_server)<br/>Cowboy HTTP on :8080"]
    D --> G["the_commission (supervisor)<br/>strategy: rest_for_one"]

    G --> U["underboss (supervisor)<br/>strategy: one_for_one"]
    G --> CP["consigliere_pool (poolboy)<br/>5 workers, max overflow 10"]

    U --> KP["caporegime_pool (poolboy)<br/>3 workers, max overflow 5"]

    CP -.->|workers| CW["consigliere_worker (gen_server)<br/>Large model: qwen2.5:7b"]
    KP -.->|workers| CR["caporegime (gen_server)<br/>Small model: qwen2.5:1.5b"]

    style D fill:#8B0000,color:#fff
    style G fill:#555,color:#fff
    style TF fill:#2E86C1,color:#fff
    style U fill:#555,color:#fff
    style CP fill:#1E8449,color:#fff
    style KP fill:#B7950B,color:#fff
    style CW fill:#1E8449,color:#fff
    style CR fill:#B7950B,color:#fff
```

**Key design choice:** `the_commission` uses `rest_for_one`. The underboss starts *first*. If it crashes, the consigliere pool is also restarted — preventing workers from holding stale references to a dead caporegime pool.

---

## 2. Request Flow

```mermaid
sequenceDiagram
    participant Client
    participant TF as the_front / openai_handler
    participant C as consigliere (dispatcher)
    participant CW as consigliere_worker
    participant OL as ollama_client (7b)
    participant MS as mission_store (Mnesia)
    participant UB as underboss
    participant CR as caporegime
    participant OLS as ollama_client (1.5b)

    Client->>TF: POST /v1/chat/completions (stream: true)
    TF->>TF: Parse body, extract prompt + session ID + stream flag
    TF->>TF: Start SSE stream (200, text/event-stream)
    TF->>C: handle_mission(SessionId, Prompt, {self(),Tag})
    C->>CW: poolboy:transaction -> gen_server:call

    CW->>MS: get_latest_context(SessionId)
    CW->>OL: generate(Prompt, SystemPrompt, Context)
    OL-->>CW: JSON with delegate_required, tool_intent, response

    alt delegate_required = false
        CW->>MS: post_mission(direct_answer)
        CW-->>TF: {Tag, {done, Response, MissionId}}
        TF-->>Client: SSE chunk (content) + [DONE]
    else delegate_required = true
        CW->>MS: post_mission(intent)
        CW-->>TF: {Tag, {chunk, Response, MissionId}}
        TF-->>Client: SSE chunk 1 (consigliere response)
        CW->>UB: dispatch_mission(MissionSpec incl. cowboy_from)
        UB->>CR: poolboy:transaction -> execute_mission
        CR->>MS: update_status(in_progress)
        CR->>OLS: generate(SubPrompt)
        OLS-->>CR: result
        CR->>MS: complete_mission / fail_mission
        CR-->>TF: {Tag, {done, Result, MissionId}}
        TF-->>Client: SSE chunk 2 (execution result) + [DONE]
    end
```

---

## 3. Module Map

```mermaid
graph LR
    subgraph "HTTP Layer"
        TF[the_front]
        OH[openai_handler]
        HH[health_handler]
    end

    subgraph "Reasoning Layer"
        CON[consigliere]
        CW[consigliere_worker]
    end

    subgraph "Execution Layer"
        UB[underboss]
        CR[caporegime]
    end

    subgraph "Infrastructure"
        OC[ollama_client]
        MS[mission_store]
    end

    TF -->|routes| OH
    TF -->|routes| HH
    OH -->|dispatches| CON
    CON -->|pool checkout| CW
    CW -->|calls| OC
    CW -->|reads/writes| MS
    CW -->|delegates| UB
    UB -->|pool checkout| CR
    CR -->|calls| OC
    CR -->|reads/writes| MS
```

---

## 4. Module Details

| Module | OTP Behaviour | Role |
|---|---|---|
| `entrypoint` | `application` | Boots the app, calls `don_erleone:start_link()` |
| `don_erleone` | `supervisor` | Top-level sup. Inits Mnesia, loads configs, starts children |
| `the_front` | `gen_server` | Starts Cowboy HTTP listener on port 8080 |
| `openai_handler` | cowboy handler | Parses OpenAI-format requests, blocks on async reply from consigliere |
| `health_handler` | cowboy handler | Returns `{"status":"ok"}` on `/health` |
| `consigliere` | stateless module | Dispatches to `consigliere_pool` via `proc_lib:spawn` |
| `consigliere_worker` | `gen_server` + `poolboy_worker` | Calls the large LLM, parses JSON response, routes to direct answer or delegation |
| `the_commission` | `supervisor` | `rest_for_one` sub-supervisor owning underboss + consigliere pool |
| `underboss` | `supervisor` | Owns the caporegime pool. Exposes `dispatch_mission/1` |
| `caporegime` | `gen_server` + `poolboy_worker` | Executes delegated missions via the small LLM or MCP HTTP calls |
| `ollama_client` | stateless module | Shared HTTP client for Ollama `/api/generate` |
| `mission_store` | stateless module | Mnesia CRUD for mission records (ram_copies) |

---

## 5. Two-Model LLM Strategy

| | Consigliere (Reasoning) | Caporegime (Execution) |
|---|---|---|
| **Default model** | `qwen2.5:7b` | `qwen2.5:1.5b` |
| **Purpose** | Interpret user intent, decide routing | Execute specific tasks (k8s YAML, status checks) |
| **System prompt** | Yes — structured JSON output with `delegate_required` flag | Per-task prompts built by `build_sub_prompt/3` |
| **Timeout** | 3,600s (1 hour) | 120s |
| **Config record** | `#config{}` | `#sub_config{}` |

---

## 6. Data Records

Source: [records.hrl](file:///home/nixos/Documents/agent_project/localhost_agent/apps/don-erleone/include/records.hrl)

```erlang
%% Consigliere config
-record(config, {ollama_url, model, timeout, stream, system_prompt}).

%% Caporegime config
-record(sub_config, {ollama_url, model, timeout}).

%% Mission ledger (Mnesia table, ram_copies)
-record(mission, {
    id,              %% unique monotonic integer
    session_id,      %% peer IP string
    intent,          %% <<"k8s_deploy">>, <<"check_mcp">>, <<"direct_answer">>
    raw_prompt,      %% original user input
    status,          %% pending -> in_progress -> completed | failed
    result,          %% final result map from caporegime
    error,           %% error reason if failed
    context_tokens,  %% Ollama context array for conversational memory
    timestamp        %% erlang:system_time(second)
}).
```

**Mission lifecycle:** `pending` → `in_progress` → `completed` | `failed`

---

## 7. Async Reply Pattern (with SSE Streaming)

The `openai_handler` cannot wait on a normal `gen_server:call` through poolboy (that would hold the pool worker hostage for the entire HTTP request). Instead:

1. Handler creates `Tag = make_ref()` and passes `{self(), Tag}` as `CowboyFrom`
2. Handler starts an SSE stream with `cowboy_req:stream_reply(200, SSE headers, Req)` (when `stream: true`)
3. `consigliere:handle_mission/3` spawns a process that checks out a pool worker
4. The worker does its work, then sends `CowboyPid ! {CowboyTag, Result}` directly
   - Direct answers: `{Tag, {direct, Response, Meta}}`
   - Delegated missions: `{Tag, {delegated, Response, Meta}}`
5. The pool worker returns `{reply, ok, State}` to release itself back to poolboy
6. For delegated missions, the `CowboyFrom` is included in the `MissionSpec` and threaded through to the caporegime
7. After execution, the caporegime sends `{Tag, {execution_complete, Result}}` to the handler
8. The handler streams each message as an SSE chunk in OpenAI `chat.completion.chunk` format

**Streaming mode** (`stream: true`): The consigliere's response arrives as SSE chunk 1, then the caporegime's execution result as chunk 2, followed by `[DONE]`. This gives Open WebUI users real-time feedback.

**Non-streaming mode** (`stream: false`): The handler waits for both messages and returns a single combined JSON response. Falls back to the consigliere response only if the caporegime times out.

This decouples the HTTP request lifecycle from the pool worker lifecycle while ensuring execution results reach the client.

---

## 8. Supported Intents

The caporegime dispatches on the `tool_intent` string from the consigliere's LLM output:

| Intent | Behaviour |
|---|---|
| `k8s_deploy` | Builds a k8s-specific sub-prompt, calls small LLM for YAML manifest generation |
| `check_mcp` | If `mcp_args` contains an `endpoint` URL, makes a direct HTTP POST to that MCP endpoint. Otherwise falls back to sub-model reasoning |
| *(any other)* | Generic sub-agent prompt with intent + args, calls small LLM |

---

## 9. External Dependencies

| Dependency | Purpose |
|---|---|
| **Cowboy** | HTTP server |
| **Poolboy** | Worker pool management |
| **JSX** | JSON encode/decode |
| **Mnesia** | In-memory mission store |
| **Ollama** | Local LLM inference (external service) |


----

Alternate look at design:

```mermaid
graph TD
    subgraph External
        USER["curl / Frontend / OpenWebUI"]
        MCP_EXT["External MCP Servers"]
        WEBHOOKS["Webhooks / Events"]
    end

    subgraph "don_erleone (top supervisor)"
        subgraph "The Front"
            COWBOY["the_front (gen_server)"]
            HANDLER["openai_handler"]
            SSE["SSE streaming handler"]
            HEALTH["health + metrics handler"]
            WS["WebSocket handler"]
        end

        subgraph "Consigliere Pool (poolboy)"
            CW["consigliere_workers"]
        end

        subgraph "Underboss (supervisor)"
            DISPATCH["dispatch + routing logic"]
            subgraph "Caporegime Pool (poolboy)"
                CAP["caporegime_workers"]
            end
            subgraph "Fan-out Supervisor (simple_one_for_one)"
                LT1["mission_crew (supervisor)"]
                LT2["mission_crew (supervisor)"]
            end
        end

        subgraph "MCP Client Registry"
            MCP_REG["mcp_registry (gen_server)"]
            MCP_K8S["k8s_mcp_client"]
            MCP_NIX["nix_mcp_client"]
            MCP_GIT["git_mcp_client"]
        end

        subgraph "Persistence"
            MNESIA["mission_store (mnesia disc_copies)"]
            CONTEXT["context_store (conversation history)"]
        end

        subgraph "Observability"
            METRICS["prometheus_metrics"]
            TRACES["opentelemetry spans"]
        end
    end

    subgraph "Ollama Backend"
        BIG["Large Model (reasoning)"]
        MED["Medium Model (tasks)"]
        SMALL["Small Model (extraction)"]
    end

    USER -->|"POST + SSE"| COWBOY
    WEBHOOKS -->|"async events"| WS
    COWBOY --> HANDLER
    COWBOY --> SSE
    HANDLER --> CW
    CW --> BIG
    CW -->|"simple task"| CAP
    CW -->|"complex multi-step"| LT1
    CAP --> MED
    LT1 -->|"step 1: generate"| MED
    LT1 -->|"step 2: validate"| MCP_K8S
    LT1 -->|"step 3: apply"| MCP_K8S
    MCP_REG --> MCP_K8S
    MCP_REG --> MCP_NIX
    MCP_REG --> MCP_GIT
    MCP_K8S --> MCP_EXT
    CAP --> MNESIA
    LT1 --> MNESIA
    CW --> CONTEXT

    style BIG fill:#e74c3c,color:#fff
    style MED fill:#e67e22,color:#fff
    style SMALL fill:#3498db,color:#fff
    style MNESIA fill:#2ecc71,color:#fff
    style CONTEXT fill:#2ecc71,color:#fff
    style MCP_REG fill:#f39c12,color:#fff
```

# License

        Don Erleone - Erlang Orchestrator for Agentic Swarm
        Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

        This program is free software: you can redistribute it and/or modify
        it under the terms of the GNU Affero General Public License as
        published by the Free Software Foundation, either version 3 of the
        License, or (at your option) any later version.

        This program is distributed in the hope that it will be useful,
        but WITHOUT ANY WARRANTY; without even the implied warranty of
        MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
        GNU Affero General Public License for more details.

        You should have received a copy of the GNU Affero General Public License
        along with this program.  If not, see <https://www.gnu.org/licenses/>.