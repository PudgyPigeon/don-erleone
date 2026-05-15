


# Test 1 
curl -i -X POST http://localhost:8080/v1/chat/completions      -H "Content-Type: application/json"      -d '{
       "model": "nix-agent-001",
       "messages": [{"role": "user", "content": "Reconcile the GPU cluster."}]
     }'

# Test 2
curl -i -X POST http://localhost:8080/v1/chat/completions      -H "Content-Type: application/json"      -d '{
       "model": "nix-orchestrator-v1",
       "messages": [{"role": "user", "content": "Verify the current flake."}]
     }'

# Test 3
curl -X POST http://localhost:8080/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{
           "model": "don-erleone",
           "messages": [{"role": "user", "content": "Tell me a joke"}]
         }'


curl -N -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"don-erleone","stream":true,"messages":[{"role":"user","content":"Deploy nginx to k8s"}]}'
