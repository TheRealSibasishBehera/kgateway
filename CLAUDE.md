# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Kgateway is an Envoy-powered, Kubernetes-native API gateway that provides ingress/edge routing, API gateway functionality, AI gateway capabilities, and serves as a waypoint proxy for ambient mesh. It translates Kubernetes Gateway API resources into Envoy configuration.

## Core Concepts

### Gateway API and Envoy Integration

Kgateway acts as a control plane that bridges Kubernetes Gateway API resources and Envoy proxy data plane:

```
┌─────────────────┐     ┌──────────────┐     ┌─────────────┐
│ Gateway API CRs │ --> │   Kgateway   │ --> │ Envoy xDS   │
│ (HTTPRoute etc) │     │ (Controller) │     │   Config    │
└─────────────────┘     └──────────────┘     └─────────────┘
                              │                      │
                              v                      v
                        ┌──────────┐          ┌──────────┐
                        │    IR    │          │  Envoy   │
                        │  Model   │          │  Proxy   │
                        └──────────┘          └──────────┘
```

### KRT (Kubernetes Runtime) Architecture

KRT is Istio's high-performance Kubernetes resource tracking system that kgateway uses for efficient resource watching:

```go
// Pseudo-code showing KRT collection flow
KRTCollection[Gateway] -->
  Transform(gateway => GatewayIR) -->
    Merge(routes, policies) -->
      Translate(ir => xDS) -->
        Snapshot.SetSnapshot(xdsConfig)
```

Key benefits:
- **Incremental processing**: Only changed resources trigger updates
- **Dependency tracking**: Automatic handling of resource relationships
- **Type safety**: Compile-time checked transformations
- **Batching**: Efficient bulk updates for performance

## Common Development Commands

### Build and Test
```bash
# Run all tests
make test

# Run unit tests only (non-E2E)
make run-tests

# Run specific test package
TEST_PKG=path/to/package make test

# Run tests with verbose output
GINKGO_USER_FLAGS="-vv" make test

# Run performance tests
make run-performance-tests

# Run Kubernetes E2E tests
make run-kube-e2e-tests
```

### Code Quality
```bash
# Format code with goimports
make fmt

# Run golangci-lint
make analyze

# Verify generated code is up to date
make verify

# Generate all code (protos, mocks, etc.)
make go-generate-apis

# Generate mocks only
make go-generate-mocks
```

### Local Development
```bash
# Set up complete development environment (Kind cluster + deployment)
make run

# Set up basic infrastructure only (Kind cluster, images, CRDs, MetalLB)
make setup

# Package Helm charts
make package-kgateway-charts

# Deploy to existing cluster
make deploy-kgateway
```

### Running Controller Locally
Set environment variables and run:
```bash
export KUBECONFIG=/path/to/kubeconfig
export KGW_LOG_LEVEL=info
export KGW_XDS_SERVICE_HOST=172.17.0.1  # Or 192.168.65.254 for Kind
export KGW_DEFAULT_IMAGE_REGISTRY=ghcr.io/kgateway-dev
export KGW_DEFAULT_IMAGE_TAG=2.0.0-dev
export KGW_DEFAULT_IMAGE_PULL_POLICY=IfNotPresent

go run cmd/kgateway/main.go
```

## Architecture Deep Dive

### Data Flow and Translation Pipeline

The complete data flow from Kubernetes resources to Envoy configuration:

```
1. Kubernetes API Server
   │
   ├─> KRT Collections (Watch & Cache)
   │   ├─> Gateways
   │   ├─> Routes (HTTP/TCP/TLS/gRPC)
   │   ├─> Services & Endpoints
   │   ├─> Policies
   │   └─> Secrets
   │
2. Gateway Translator (gwtranslator)
   │   ├─> Build Gateway IR
   │   ├─> Attach Routes
   │   ├─> Apply Policies
   │   └─> Resolve Backends
   │
3. IR Translator (irtranslator)
   │   ├─> Generate Listeners (LDS)
   │   ├─> Generate Routes (RDS)
   │   ├─> Generate Clusters (CDS)
   │   └─> Generate Endpoints (EDS)
   │
4. xDS Server
   │   └─> Stream to Envoy Proxies
   │
5. Envoy Data Plane
```

### Core Components Call Graph

```go
// Main initialization flow
main.go
  └─> setup.Start()
      ├─> NewServerContext()           // Initialize core context
      ├─> extensions.NewRegistry()     // Load plugins
      ├─> NewCombinedTranslator()      // Create translation pipeline
      │   ├─> gwtranslator.New()      // Gateway API → IR
      │   └─> irtranslator.New()      // IR → xDS
      ├─> xdsserver.New()              // Start xDS server
      └─> controller.Start()           // Begin reconciliation

// Translation call flow
CombinedTranslator.Translate()
  ├─> gwtranslator.TranslateGateway()
  │   ├─> buildListeners()            // Process Gateway listeners
  │   ├─> attachRoutes()              // Attach routes to listeners
  │   └─> applyPolicies()             // Apply attached policies
  └─> irtranslator.TranslateIR()
      ├─> translateListeners()        // IR → Envoy Listeners
      ├─> translateRoutes()           // IR → Envoy Routes
      └─> translateClusters()         // IR → Envoy Clusters
```

### Plugin System Architecture

```go
// Plugin interface pseudo-code
type Plugin interface {
    // Contribute custom policies
    ContributePolicies() map[GVK]PolicyPlugin
    
    // Contribute custom backends
    ContributeBackends() map[GVK]BackendPlugin
    
    // Extend Gateway translation
    ContributeGwTranslator() GwTranslatorPlugin
    
    // Extend IR translation
    ContributeIrTranslator() IrTranslatorPlugin
}

// Policy attachment flow
PolicyAttachment:
  Resource (Gateway/Route)
    └─> targetRef
        └─> Policy
            └─> Plugin.TranslatePolicy()
                └─> IR modifications
```

## Key Directories and Components

### Core Translation Pipeline
- `internal/kgateway/translator/`: Main translation logic
  - `gwtranslator/`: Gateway API → IR translation
    - `listener.go`: Gateway listener processing
    - `route.go`: Route attachment and processing
    - `policy.go`: Policy attachment resolution
  - `irtranslator/`: IR → Envoy xDS translation
    - `listener_translator.go`: Generate Envoy listeners
    - `route_translator.go`: Generate Envoy routes
    - `cluster_translator.go`: Generate Envoy clusters

### KRT Collections and State Management
- `internal/kgateway/krtcollections/`: KRT-based resource collections
  - `gateway.go`: Gateway resource tracking
  - `routes.go`: Route resource tracking (HTTP/TCP/TLS/gRPC)
  - `backends.go`: Backend service discovery
  - `policies.go`: Policy attachment tracking

### Plugin System
- `pkg/pluginsdk/`: Plugin SDK interfaces
  - `types.go`: Core plugin interfaces
  - `policy.go`: Policy plugin interface
  - `backend.go`: Backend plugin interface
- `internal/kgateway/extensions2/plugins/`: Built-in plugins
  - `backend/`: Standard Kubernetes Service backend
  - `backendtlspolicy/`: TLS configuration for backends
  - `istio/`: Istio integration (ServiceEntry, PeerAuthentication)
  - `waypoint/`: Ambient mesh waypoint proxy support
  - `inference/`: AI/ML inference routing

### xDS Server and Envoy Integration
- `internal/kgateway/xdsserver/`: xDS server implementation
  - `server.go`: gRPC xDS server
  - `callbacks.go`: Per-client configuration callbacks
  - `snapshot.go`: Configuration snapshot management

### Testing Infrastructure
- `test/kubernetes/e2e/`: End-to-end tests
  - `features/`: Feature-specific test suites
  - `defaults/`: Default behavior tests
- `test/helpers/`: Test utilities and fixtures

### Development Resources
- `devel/`: Development documentation
  - `architecture/`: Architecture design docs
  - `debugging/`: Debugging guides
  - `contributing/`: Contribution guidelines

## Understanding the Codebase

### Entry Points for Code Navigation

1. **Start with main.go**: `cmd/kgateway/main.go`
   - Follow setup.Start() to understand initialization
   - Trace through NewServerContext() for component wiring

2. **Follow the translation pipeline**:
   - Start at `CombinedTranslator.Translate()` in `internal/kgateway/translator/combined.go`
   - Trace through Gateway → IR → xDS transformations

3. **Understand KRT collections**:
   - Begin with `internal/kgateway/krtcollections/gateway.go`
   - See how resources are tracked and transformed

4. **Explore plugin integration**:
   - Start with `pkg/pluginsdk/types.go` for interfaces
   - Look at `internal/kgateway/extensions2/registry.go` for registration

### Key Patterns and Conventions

1. **Immutable IR Pattern**:
   ```go
   // Resources flow through immutable transformations
   Gateway API → Gateway IR → Envoy xDS
   // Each stage produces new objects, never modifies inputs
   ```

2. **Plugin Extension Points**:
   ```go
   // Plugins can hook into multiple stages
   PolicyPlugin.TranslatePolicy() → Modify IR
   GwTranslatorPlugin.TranslateGateway() → Extend Gateway translation
   IrTranslatorPlugin.TranslateIR() → Extend xDS generation
   ```

3. **KRT Transform Pattern**:
   ```go
   // KRT collections use functional transformations
   collection.Transform(func(resource T) U {
       // Transform resource type T to type U
   }).Filter(func(resource U) bool {
       // Filter resources
   }).Index(func(resource U) []string {
       // Create indices for efficient lookup
   })
   ```

### Envoy Configuration Generation

Kgateway programmatically builds Envoy configuration using the go-control-plane library:

1. **Listener Configuration**:
   - HTTP listeners with HCM (HTTP Connection Manager)
   - HTTPS listeners with TLS contexts
   - TCP/TLS passthrough listeners

2. **Route Configuration**:
   - Virtual hosts for HTTP routing
   - Route matching (path, header, method)
   - Route actions (forward, redirect, direct response)

3. **Cluster Configuration**:
   - Service discovery via EDS
   - Load balancing policies
   - Health checking
   - Circuit breaking

4. **Advanced Features**:
   - Request/response transformations
   - Authentication/authorization filters
   - Rate limiting
   - Observability (tracing, metrics, access logs)

### Debugging and Troubleshooting

1. **KRT Snapshot**: `http://localhost:9097/snapshots/krt`
   - Shows current state of all KRT collections
   - Useful for understanding what resources are being tracked

2. **xDS Snapshot**: `http://localhost:9097/snapshots/xds`
   - Shows generated Envoy configuration
   - Useful for debugging translation issues

3. **Translation Tracing**:
   - Set `KGW_LOG_LEVEL=debug` for detailed translation logs
   - Look for "Translating Gateway" and "Generated xDS" messages

## Testing Approach

- Uses Ginkgo/Gomega BDD-style testing framework
- Unit tests should be self-contained and not modify global state
- Prefer table-driven tests for multiple scenarios
- E2E tests run against Kind clusters
- Use `envtest` for controller tests (in-memory K8s API server)

## Debugging

- Access KRT snapshot: `http://localhost:9097/snapshots/krt`
- Access XDS snapshot: `http://localhost:9097/snapshots/xds`
- Use VSCode debugger configuration from `devel/debugging/local-controller.md`

## Performance Considerations

### KRT Optimizations
- **Batched Updates**: Multiple K8s events are batched before processing
- **Incremental Processing**: Only changed resources trigger translations
- **Indexed Lookups**: O(1) lookups for common queries (e.g., routes by gateway)
- **Lazy Evaluation**: Transformations only run when data is accessed

### Translation Optimizations
- **Parallel Processing**: Independent gateways translated concurrently
- **Caching**: Reuse unchanged xDS resources across updates
- **Selective Updates**: Only send changed xDS resources to Envoy

### Scalability Patterns
- **Per-Gateway Isolation**: Each gateway's configuration is independent
- **Horizontal Scaling**: Multiple controller replicas with leader election
- **Resource Filtering**: Controllers can watch specific namespaces

## Security Considerations

1. **Secret Handling**:
   - TLS secrets are watched via KRT
   - Secrets are only accessible to authorized gateways
   - Never logged or exposed in debug output

2. **RBAC Integration**:
   - Gateway permissions checked via K8s RBAC
   - Route attachment requires namespace permissions

3. **Policy Enforcement**:
   - Policies can restrict route attachments
   - Backend access can be controlled via policies

## Important Notes

- The project was previously known as Gloo (migration ongoing)
- Based on Envoy proxy (v1.35.0-patch1)
- Requires Go 1.24.6
- Main branch is `main` for PRs
- Uses Istio's KRT library for Kubernetes resource tracking
- Follows Kubernetes Gateway API v1.2.0 specification