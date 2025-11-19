# ExtProc E2E Test Failure - Deep Dive Analysis

**Date**: November 19, 2025
**Status**: 🔍 INVESTIGATION IN PROGRESS

---

## Summary

The AgentGateway ExtProc integration test is failing because the external processor (extproc) service is not being invoked by the gateway, despite correct configuration. Requests go directly from gateway → backend without calling the extproc service, resulting in missing headers.

---

## Investigation Setup

I've created a comprehensive debugging environment with:

### 1. Standalone Test Environment
**Location**: `/Users/sibasishbehera/kgateway/debug-extproc/`

**Contents**:
- `manifests/` - All YAML files for reproducing the issue
- `scripts/` - Helper scripts for deployment, testing, and log collection
- `logs/` - Collected logs from all components

### 2. Scripts Created

| Script | Purpose |
|--------|---------|
| `01-deploy.sh` | Deploy all resources to `extproc-debug` namespace |
| `02-watch-logs.sh` | Monitor logs from all 4 components simultaneously |
| `03-test-request.sh` | Send test requests and validate responses |
| `04-check-xds.sh` | Inspect XDS configuration |
| `05-describe-resources.sh` | Show detailed resource status |
| `99-cleanup.sh` | Clean up test environment |
| `run-test-with-logging.sh` | Run E2E test with comprehensive log collection |

### 3. Log Collection

Currently collecting logs from:
- ✅ KGateway controller (agent-gateway-test namespace)
- ✅ AgentGateway pod (gateway data plane)
- ✅ ExtProc service (external processor)
- ✅ Backend service (echo server)
- ✅ Test output

**Current Log Session**: `debug-extproc/logs/20251119-231757/`

---

## Test Behavior Observed

### Expected Flow
```
Client → Gateway
           ↓
       ExtProc (adds "Extproctest" header)
           ↓
       Backend (receives header)
           ↓
       Client (sees header in response)
```

### Actual Flow
```
Client → Gateway
           ↓
       Backend (no header added)
           ↓
       Client (missing "Extproctest" header) ❌
```

### Sample Response (FAILING)
```json
{
  "headers": {
    "Accept": ["*/*"],
    "Instructions": ["{\"addHeaders\":{\"extproctest\":\"true\"},\"removeHeaders\":null}"],
    "User-Agent": ["curl/7.83.1-DEV"]
  }
}
```

**Missing**: `"Extproctest": ["true"]` header

---

## Key Findings So Far

### 1. No AgentgatewayPolicy Processing Logs ❌

Searched controller logs for:
- `"agentgatewaypolicy"` - **NO RESULTS**
- `"gateway-test"` (policy name) - **NO RESULTS**

**Implication**: The controller may not be processing AgentgatewayPolicy resources at all!

### 2. ExtProc Service Endpoints Found ✅

Controller logs show:
```json
{"msg":"building endpoints","kubesvc":{"Namespace":"default","Name":"ext-proc-grpc"}}
{"msg":"created endpoint","kubesvc":{"Namespace":"default","Name":"ext-proc-grpc"},"total_endpoints":1}
```

The controller knows about the extproc service.

### 3. Test Consistently Fails ✅

Multiple test runs show identical behavior:
- Gateway routes successfully
- Backend responds correctly
- ExtProc service is never called
- Expected header never appears

---

## Technical Details

### CRD Status
```bash
$ kubectl get crd agentgatewaypolicies.gateway.kgateway.dev
# CRD exists and is installed
```

### Resource Deployment
```yaml
apiVersion: gateway.kgateway.dev/v1alpha1
kind: AgentgatewayPolicy
metadata:
  name: gateway-test
  namespace: default
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: gw
  traffic:
    extProc:
      backendRef:
        name: ext-proc-grpc
        port: 4444
      failOpen: false
```

**Status**: Resource creates successfully, no errors

### Code Paths

ExtProc processing code EXISTS at:
- `pkg/agentgateway/plugins/traffic_plugin.go:372-379` - Policy conversion
- `pkg/agentgateway/plugins/traffic_plugin.go:815+` - ExtProc processor function

```go
// Line 372-379
if traffic.ExtProc != nil {
    extProcPolicies, err := processExtProcPolicy(ctx, policy, policyName, policyTarget)
    if err != nil {
        logger.Error("error processing ExtProc policy", "error", err)
        return nil, err
    }
    agwPolicies = append(agwPolicies, extProcPolicies...)
}
```

**Question**: Is this code path being reached?

---

## Hypotheses

### Hypothesis 1: AgentgatewayPolicy Not Watched
**Evidence**:
- No logs about AgentgatewayPolicy processing
- No errors about the policy
- Controller logs show other resources being processed

**Next Step**: Check if controller watches AgentgatewayPolicy CRD

### Hypothesis 2: Policy Not Being Applied
**Evidence**:
- ExtProc code exists but may not be invoked
- No errors suggest the policy is silently ignored

**Next Step**: Add debug logging to `processExtProcPolicy` function

### Hypothesis 3: XDS Translation Bug
**Evidence**:
- Controller generates XDS configuration
- Configuration may not include extProc filter

**Next Step**: Dump and analyze XDS snapshots

### Hypothesis 4: AgentGateway Version Issue
**Evidence**:
- Using version: `0.10.4`
- Location: `pkg/deployer/wellknown.go:20`

**Next Step**: Check if this agentgateway version supports extProc

---

## Next Steps

###  Critical Analysis Needed

1. **Check Controller Watches**
   ```bash
   grep -r "AgentgatewayPolicy" internal/kgateway/controller/
   ```

2. **Analyze XDS Configuration**
   - Dump XDS from controller
   - Check for ext_proc filter
   - Compare with working extAuth configuration

3. **Inspect Gateway Config**
   ```bash
   kubectl exec -n default gw-pod -- curl localhost:19000/config_dump
   ```

4. **Add Debug Logging**
   - Instrument `processExtProcPolicy` function
   - Add logs to confirm function is called
   - Log the generated XDS configuration

5. **Compare with ExtAuth**
   - ExtAuth works correctly
   - ExtProc uses similar structure
   - Find the difference

---

## Resources

### Test Files
- Test Suite: `test/e2e/features/agentgateway/extproc/suite.go`
- Manifests: `test/e2e/features/agentgateway/extproc/testdata/`

### Code Locations
- CRD Definition: `install/helm/kgateway-crds/templates/gateway.kgateway.dev_agentgatewaypolicies.yaml`
- API Types: `api/v1alpha1/agentgateway_policy_types.go`
- Plugin Implementation: `pkg/agentgateway/plugins/traffic_plugin.go`
- Controller: `internal/kgateway/controller/gw_controller.go`

### Log Files (Current Session)
```
debug-extproc/logs/20251119-231757/
├── kgateway-controller.log  (178K, 774 lines)
├── gateway.log              (126B, 1 line)
├── extproc.log              (137B, 1 line)
├── backend.log              (129B, 1 line)
└── test-output.log          (108K, 1959 lines)
```

---

## Environment

- **Kubernetes**: kind cluster
- **KGateway**: 1.0.1-dev
- **AgentGateway**: 0.10.4
- **Test Namespace**: default
- **Controller Namespace**: agent-gateway-test

---

## Debug Commands

```bash
# Check policy status
kubectl get agentgatewaypolicy -A -o yaml

# Check gateway status
kubectl describe gateway gw -n default

# Check controller logs
kubectl logs -n agent-gateway-test -l app=kgateway --tail=100

# Check gateway logs
kubectl logs -n default -l gateway.networking.k8s.io/gateway-name=gw

# Send test request
kubectl exec -n curl curl -- curl -H "Host: www.example.com" \
  -H 'instructions: {"addHeaders":{"extproctest":"true"}}' \
  http://gw.default.svc.cluster.local:8080/
```

---

## Status: Awaiting Test Completion

The test is currently running with full log collection. Once completed, I will:
1. Analyze all collected logs
2. Search for XDS configuration
3. Identify the exact point of failure
4. Provide specific fixes

**Estimated completion**: 2-3 minutes (test includes 2-minute sleep)
