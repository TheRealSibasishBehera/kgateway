# AgentGateway ExtProc E2E Test Failure Investigation Report

**Date**: November 19, 2025
**Test**: `TestAgentgatewayIntegration/Extproc/TestExtProcWithGatewayTargetRef`
**Status**: ❌ **FAILED**
**Duration**: ~245 seconds (4 minutes)

---

## Executive Summary

The agentgateway extproc (external processing) E2E test is failing because **the external processor is not being invoked** despite the AgentgatewayPolicy being correctly configured. The gateway routes traffic directly to the backend service without calling the extproc gRPC service, resulting in the expected header ("Extproctest") never appearing in responses.

---

## Test Overview

### What the Test Does
1. Deploys a Gateway (`gw`) with agentgateway class
2. Deploys a backend echo service
3. Deploys an external processor gRPC service (`ext-proc-grpc`)
4. Creates an AgentgatewayPolicy with extProc configuration targeting the Gateway
5. Makes HTTP requests expecting the extproc service to add a header ("Extproctest")
6. Validates that the header appears in the backend response

### Expected Behavior
```
Client → Gateway (agentgateway)
              ↓
         ExtProc Service (adds "Extproctest" header)
              ↓
         Backend Service (echoes headers)
              ↓
         Client (sees "Extproctest" header)
```

### Actual Behavior
```
Client → Gateway (agentgateway)
              ↓
         Backend Service (no header added)
              ↓
         Client (missing "Extproctest" header)
```

---

## Root Cause Analysis

### Primary Finding
**The agentgateway proxy is NOT calling the external processor service**, even though:
- ✅ The AgentgatewayPolicy CRD exists and is valid
- ✅ The extProc field is properly defined in the CRD schema
- ✅ Code exists to process extProc policies (`pkg/agentgateway/plugins/traffic_plugin.go:815`)
- ✅ The extproc gRPC service is running and listening on port 18080
- ✅ The AgentgatewayPolicy resource is created successfully

### Evidence

#### 1. Gateway Logs Show Direct Backend Routing
```
2025-11-19T17:18:49.498070Z info request gateway=default/gw listener=http
  route=default/route-1 endpoint=10.244.0.9:3000 src.addr=10.244.0.8:52120
  http.method=GET http.host=www.example.com http.path=/
  http.version=HTTP/1.1 http.status=200 protocol=http duration=1ms
```
**Observation**: No mention of extproc service calls in the request logs.

#### 2. ExtProc Service Receives No Traffic
```bash
kubectl logs ext-proc-grpc-6765586f4f-6wrws
# Output:
Starting gRPC server on port :18080
# (No subsequent request logs)
```

#### 3. Backend Responses Missing Expected Header
The test expects responses to contain:
```json
{
  "headers": {
    "Extproctest": ["true"],  // ❌ MISSING
    "Accept": ["*/*"],
    "User-Agent": ["curl/7.83.1-DEV"]
  }
}
```

---

## Configuration Analysis

### Resources Deployed

#### AgentgatewayPolicy
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
**Status**: ✅ Created successfully, valid schema

#### Services
| Service | Type | ClusterIP | Port Mapping |
|---------|------|-----------|--------------|
| `gw` | LoadBalancer | 10.96.4.212 | 8080:30768 |
| `ext-proc-grpc` | ClusterIP | 10.96.9.166 | 4444 → 18080 (h2c) |
| `backend` | ClusterIP | 10.96.225.100 | 3000 |

#### Pods
| Pod | Status | Container Ports |
|-----|--------|----------------|
| `gw-84ff7d7796-n57qz` | Running | 8080 |
| `ext-proc-grpc-6765586f4f-6wrws` | Running | 18080 |
| `backend-0-756dd7d576-g89cq` | Running | 3000 |

---

## Code Investigation

### ExtProc Processing Code Exists
Location: `/Users/sibasishbehera/kgateway/pkg/agentgateway/plugins/traffic_plugin.go`

```go
// Line 372-379: ExtProc policy conversion
if traffic.ExtProc != nil {
    extProcPolicies, err := processExtProcPolicy(ctx, policy, policyName, policyTarget)
    if err != nil {
        logger.Error("error processing ExtProc policy", "error", err)
        return nil, err
    }
    agwPolicies = append(agwPolicies, extProcPolicies...)
}

// Line 815: ExtProc policy processor
func processExtProcPolicy(ctx PolicyCtx, policy *v1alpha1.AgentgatewayPolicy,
    policyName string, policyTarget *api.PolicyTarget) ([]AgwPolicy, error) {
    extProc := policy.Spec.Traffic.ExtProc

    be, err := buildBackendRef(ctx, extProc.BackendRef, policy.Namespace)
    if err != nil {
        return nil, fmt.Errorf("failed to build extProc: %v", err)
    }

    failureMode := api.TrafficPolicySpec_ExtProc_FAIL_CLOSED
    if extProc.FailOpen != nil && *extProc.FailOpen {
        failureMode = api.TrafficPolicySpec_ExtProc_FAIL_OPEN
    }

    spec := &api.TrafficPolicySpec_ExtProc{
        // ... configuration
    }
    // ... generates policy
}
```

### Controller Logs Analysis
The kgateway controller logs show:
- ✅ Policy collections being synced (TrafficPolicy, HTTPListenerPolicy, etc.)
- ✅ Gateway reconciliation occurring
- ✅ XDS push events to agentgateway pod
- ❌ **NO specific logs for AgentgatewayPolicy processing**
- ❌ **NO errors or warnings about extProc configuration**

---

## Comparison with Working ExtAuth Tests

### ExtAuth Configuration (Working)
```yaml
apiVersion: gateway.kgateway.dev/v1alpha1
kind: AgentgatewayPolicy
metadata:
  name: gw-policy
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: super-gateway
  traffic:
    extAuth:  # ← Uses extAuth instead of extProc
      backendRef:
        name: ext-authz
        port: 4444
```

### ExtProc Configuration (Not Working)
```yaml
apiVersion: gateway.kgateway.dev/v1alpha1
kind: AgentgatewayPolicy
metadata:
  name: gateway-test
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: gw
  traffic:
    extProc:  # ← Uses extProc
      backendRef:
        name: ext-proc-grpc
        port: 4444
```

**Observation**: The structure is identical except for `extAuth` vs `extProc`. Both should work the same way.

---

## Hypothesis

The issue is likely one of the following:

### 1. AgentgatewayPolicy Not Being Watched/Reconciled
The controller may not be watching AgentgatewayPolicy resources or the watch is not triggering reconciliation properly. Evidence:
- Controller logs show TrafficPolicy syncing but no AgentgatewayPolicy-specific logs
- No errors about policy processing

### 2. XDS Translation Bug
The extProc configuration may not be properly translated into agentgateway-compatible XDS configuration. The code exists but may have a bug preventing it from:
- Being included in the XDS snapshot
- Being pushed to the agentgateway data plane
- Being applied by agentgateway at runtime

### 3. AgentGateway Data Plane Issue
The agentgateway proxy (running in the `gw` pod) may not support extProc functionality in the current version:
- Version: `0.11.0-alpha.54763bfe02e1e0a023d3835a5fc2a46f7571d740`
- Location: Hardcoded in `pkg/deployer/wellknown.go:20`

---

## Prerequisites That Were Missing (Resolved)

### Gateway API CRDs
**Initial Issue**: Tests failed because Gateway API CRDs were not installed.

**Error**:
```
watch error in cluster : failed to list *v1.GatewayClass:
the server could not find the requested resource
```

**Fix**: Run `make setup-base` which installs:
```bash
kubectl apply --server-side -f "https://github.com/kubernetes-sigs/gateway-api/\
releases/download/v1.4.0/experimental-install.yaml"
```

This resolved the initial test failure and allowed tests to progress to the current extproc-specific failure.

---

## Test Files Location

### ExtProc Test Files
```
test/e2e/features/agentgateway/extproc/
├── suite.go                                    # Test suite implementation
├── resources.go                                # Resource constants
├── testdata/
    ├── gateway.yaml                           # Gateway definition
    ├── backend-service.yaml                   # Backend echo service
    ├── extproc-service.yaml                   # ExtProc gRPC service
    ├── gateway-targetref.yaml                 # Policy + Routes
    ├── httproute-targetref.yaml               # Alternative policy config
    └── failopen-test.yaml                     # Fail-open test config
```

### Key Test Code
**File**: `test/e2e/features/agentgateway/extproc/suite.go:66-139`

```go
func (s *testingSuite) TestExtProcWithGatewayTargetRef() {
    // Wait for gateway to be ready...

    testCases := []struct {
        name string
        opts []curl.Option
        resp *testmatchers.HttpResponse
    }{
        {
            name: "first route should have ExtProc applied via Gateway policy",
            opts: []curl.Option{
                curl.WithHost(kubeutils.ServiceFQDN(gatewayService)),
                curl.WithHostHeader("www.example.com"),
                curl.WithPath("/"),
                curl.WithPort(8080),
                curl.WithHeader("instructions", getInstructionsJson(instructions{
                    AddHeaders: map[string]string{"extproctest": "true"},
                })),
            },
            resp: &testmatchers.HttpResponse{
                StatusCode: http.StatusOK,
                Body: gomega.WithTransform(transforms.WithJsonBody(),
                    gomega.And(
                        // Expects "Extproctest" key in headers
                        gomega.HaveKeyWithValue("headers", gomega.HaveKey("Extproctest")),
                    ),
                ),
            },
        },
        // ...
    }
}
```

---

## Recommendations

### Immediate Actions
1. **Enable Debug Logging** on kgateway controller to see AgentgatewayPolicy processing
2. **Check XDS Snapshots** to verify extProc configuration is being generated
3. **Verify AgentGateway Version** supports extProc (check upstream agentgateway docs)
4. **Add Logging** to `processExtProcPolicy` function to confirm it's being called

### Investigation Steps
```bash
# 1. Check if AgentgatewayPolicy is being watched
kubectl logs -n agent-gateway-test <kgateway-pod> | grep -i "agentgatewaypolicy"

# 2. Verify XDS configuration includes extProc
kubectl exec -n agent-gateway-test <kgateway-pod> -- \
  curl localhost:9095/snapshots/xds | jq '.

 | grep -i extproc'

# 3. Check agentgateway admin interface
kubectl port-forward -n default <gw-pod> 15000:15000
curl localhost:15000/config_dump | jq '. | grep -i ext_proc'
```

### Potential Fixes
1. **Add AgentgatewayPolicy to controller watch list** if it's missing
2. **Fix XDS translation** if extProc config isn't being pushed
3. **Upgrade agentgateway** to a version that supports extProc
4. **Add integration between kgateway and AgentgatewayPolicy** reconciliation

---

## Related Files

### CRD Definition
- `install/helm/kgateway-crds/templates/gateway.kgateway.dev_agentgatewaypolicies.yaml`

### API Types
- `api/v1alpha1/agentgateway_policy_types.go`

### Plugin Implementation
- `pkg/agentgateway/plugins/traffic_plugin.go` (lines 372-379, 815+)
- `pkg/agentgateway/plugins/collection.go`

### Controller Code
- `internal/kgateway/agentgatewaysyncer/status_syncer.go`
- `internal/kgateway/controller/gw_controller.go`

### Version Configuration
- `pkg/deployer/wellknown.go:20` (agentgateway version)

---

## Test Execution Commands

### Run ExtProc Tests
```bash
# Setup cluster (one-time)
make setup-base

# Run extproc tests
go test -tags e2e -v ./test/e2e/tests \
  -run TestAgentgatewayIntegration/Extproc \
  -timeout 30m

# Run all agentgateway tests
go test -tags e2e -v ./test/e2e/tests \
  -run TestAgentgatewayIntegration \
  -timeout 30m
```

### Manual Debugging
```bash
# Deploy resources manually
kubectl apply -f test/e2e/features/agentgateway/extproc/testdata/

# Check policy status
kubectl get agentgatewaypolicy gateway-test -o yaml

# Test manually from curl pod
kubectl exec -n curl curl -- curl -v \
  -H "Host: www.example.com" \
  -H "instructions: {\"addHeaders\":{\"extproctest\":\"true\"}}" \
  http://gw.default.svc.cluster.local:8080/
```

---

## Conclusion

The extproc E2E test failure is caused by the agentgateway proxy not invoking the external processor service despite proper configuration. While the code infrastructure exists to support extProc policies, there appears to be a gap in either:
- The controller's reconciliation of AgentgatewayPolicy resources
- The XDS translation of extProc configuration
- The agentgateway data plane's support for extProc in the current version

Further debugging with enhanced logging and XDS snapshot inspection is required to pinpoint the exact issue in the policy processing pipeline.
