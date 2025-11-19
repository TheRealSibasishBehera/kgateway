# ExtProc Debug Environment

This directory contains a standalone test environment for debugging the AgentGateway ExtProc integration.

## Overview

The test deploys:
1. **Backend Service** - Echo server that returns request details
2. **ExtProc Service** - External processor gRPC service (adds headers based on instructions)
3. **Gateway** - AgentGateway instance
4. **AgentgatewayPolicy** - Policy that configures extProc for the gateway

All resources are deployed in the `extproc-debug` namespace for isolation.

## Quick Start

### 1. Deploy the Environment

```bash
cd debug-extproc
./scripts/01-deploy.sh
```

This will:
- Create the `extproc-debug` namespace
- Deploy all services and the gateway
- Wait for all pods to be ready
- Apply the routes and AgentgatewayPolicy

### 2. Monitor Logs

In a separate terminal, start log monitoring:

```bash
./scripts/02-watch-logs.sh
```

This will:
- Collect logs from all 4 components in real-time
- Save logs to `debug-extproc/logs/` with timestamps
- Press Ctrl+C to stop

The monitored components are:
- **Control Plane**: kgateway controller (reconciles policies)
- **Gateway**: agentgateway pod (data plane)
- **ExtProc**: ext-proc-grpc service (external processor)
- **Backend**: backend service (echo server)

### 3. Send Test Requests

```bash
./scripts/03-test-request.sh
```

This will:
- Send requests through the gateway
- Check if extproc adds the expected header
- Display results

### 4. Check XDS Configuration

```bash
./scripts/04-check-xds.sh
```

This will:
- Dump the agentgateway configuration
- Check if extProc configuration is present
- Inspect XDS snapshots from the controller

### 5. Describe Resources

```bash
./scripts/05-describe-resources.sh
```

This will show detailed status of all deployed resources.

## Investigation Workflow

1. **Deploy** the environment with `01-deploy.sh`
2. **Start log monitoring** with `02-watch-logs.sh` in a separate terminal
3. **Send requests** with `03-test-request.sh`
4. **Observe logs** in real-time across all components
5. **Check XDS config** with `04-check-xds.sh` to verify configuration
6. **Describe resources** with `05-describe-resources.sh` for status

## What to Look For

### In Control Plane Logs (kgateway)
- [ ] AgentgatewayPolicy being reconciled
- [ ] ExtProc configuration being generated
- [ ] XDS snapshots being pushed to gateway
- [ ] Any errors related to policy processing

### In Gateway Logs (agentgateway)
- [ ] XDS configuration updates received
- [ ] ExtProc filter being configured
- [ ] Requests to extproc service
- [ ] Any errors about extproc communication

### In ExtProc Logs
- [ ] Incoming gRPC requests from gateway
- [ ] Processing of request/response headers
- [ ] Instructions being processed

### In Backend Logs
- [ ] Incoming requests
- [ ] Headers received (should include extproc-added headers)

## Expected vs Actual Behavior

### Expected Flow
```
Client → Gateway (receives request)
           ↓
      ExtProc Service (adds "Extproctest" header)
           ↓
      Backend Service (receives request with header)
           ↓
      Client (sees "Extproctest" in response)
```

### Current Issue
The gateway is bypassing the ExtProc service and sending requests directly to the backend.

## Cleanup

```bash
./scripts/99-cleanup.sh
```

This deletes the `extproc-debug` namespace and all resources.

## Files Structure

```
debug-extproc/
├── manifests/
│   ├── 00-namespace.yaml           # Creates extproc-debug namespace
│   ├── 01-backend-service.yaml     # Backend echo service
│   ├── 02-extproc-service.yaml     # ExtProc gRPC service
│   ├── 03-gateway.yaml             # Gateway with agentgateway class
│   └── 04-routes-and-policy.yaml   # HTTPRoutes + AgentgatewayPolicy
├── scripts/
│   ├── 01-deploy.sh                # Deploy everything
│   ├── 02-watch-logs.sh            # Monitor logs
│   ├── 03-test-request.sh          # Send test requests
│   ├── 04-check-xds.sh             # Check XDS configuration
│   ├── 05-describe-resources.sh    # Show resource status
│   └── 99-cleanup.sh               # Delete everything
├── logs/                           # Created by watch-logs.sh
└── README.md                       # This file
```

## Manual Testing

You can also test manually using kubectl:

```bash
# Get a shell in the curl pod
kubectl exec -it -n extproc-debug curl -- sh

# Send a request
curl -v -H "Host: www.example.com" \
  -H 'instructions: {"addHeaders":{"extproctest":"true"}}' \
  http://gw.extproc-debug.svc.cluster.local:8080/

# Check the response for "Extproctest" header
```

## Troubleshooting

### Gateway pod not starting
Check if Gateway API CRDs are installed:
```bash
kubectl get crd gateways.gateway.networking.k8s.io
```

If not, run:
```bash
make setup-base
```

### Logs not appearing
Make sure all pods are running:
```bash
kubectl get pods -n extproc-debug
```

### ExtProc service not receiving traffic
1. Check XDS configuration has extProc filter
2. Check gateway logs for extproc-related errors
3. Verify service endpoints are healthy
