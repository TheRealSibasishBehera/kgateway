#!/bin/bash

echo "=== Starting Log Monitoring ==="
echo ""
echo "This will open 4 terminal windows/panes to monitor:"
echo "  1. Control Plane (kgateway controller)"
echo "  2. Agent Gateway (gw pod)"
echo "  3. ExtProc Service"
echo "  4. Backend Service"
echo ""

# Get pod names
BACKEND_POD=$(kubectl get pod -n extproc-debug -l app.kubernetes.io/name=backend-0 -o jsonpath='{.items[0].metadata.name}')
EXTPROC_POD=$(kubectl get pod -n extproc-debug -l app.kubernetes.io/name=ext-proc-grpc -o jsonpath='{.items[0].metadata.name}')
GATEWAY_POD=$(kubectl get pod -n extproc-debug -l gateway.networking.k8s.io/gateway-name=gw -o jsonpath='{.items[0].metadata.name}')

# Try to find kgateway controller pod
KGATEWAY_NS=$(kubectl get pods -A -l app=kgateway | grep -v NAME | head -1 | awk '{print $1}')
KGATEWAY_POD=$(kubectl get pods -n "$KGATEWAY_NS" -l app=kgateway -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$KGATEWAY_POD" ]; then
    echo "WARNING: Could not find kgateway controller pod. Looking in common namespaces..."
    for ns in kgateway-system kube-system default; do
        KGATEWAY_POD=$(kubectl get pods -n "$ns" -l control-plane=kgateway -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [ -n "$KGATEWAY_POD" ]; then
            KGATEWAY_NS=$ns
            break
        fi
    done
fi

echo "Pod Names:"
echo "  Backend:     $BACKEND_POD"
echo "  ExtProc:     $EXTPROC_POD"
echo "  Gateway:     $GATEWAY_POD"
echo "  KGateway:    $KGATEWAY_POD (namespace: $KGATEWAY_NS)"
echo ""

# Create log directory
mkdir -p logs
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

echo "Starting log collection in background..."
echo "Logs will be saved to logs/ directory"
echo ""

# Start log collection
if [ -n "$KGATEWAY_POD" ]; then
    kubectl logs -f -n "$KGATEWAY_NS" "$KGATEWAY_POD" > "logs/${TIMESTAMP}-kgateway.log" 2>&1 &
    echo "Control Plane logs -> logs/${TIMESTAMP}-kgateway.log"
else
    echo "WARNING: KGateway controller pod not found, skipping control plane logs"
fi

kubectl logs -f -n extproc-debug "$GATEWAY_POD" > "logs/${TIMESTAMP}-gateway.log" 2>&1 &
echo "Gateway logs       -> logs/${TIMESTAMP}-gateway.log"

kubectl logs -f -n extproc-debug "$EXTPROC_POD" > "logs/${TIMESTAMP}-extproc.log" 2>&1 &
echo "ExtProc logs       -> logs/${TIMESTAMP}-extproc.log"

kubectl logs -f -n extproc-debug "$BACKEND_POD" > "logs/${TIMESTAMP}-backend.log" 2>&1 &
echo "Backend logs       -> logs/${TIMESTAMP}-backend.log"

echo ""
echo "=== Log monitoring started ==="
echo "Press Ctrl+C to stop all log collection"
echo ""

# Keep script running and handle Ctrl+C
trap 'echo ""; echo "Stopping log collection..."; jobs -p | xargs kill 2>/dev/null; echo "Done"; exit 0' INT

# Wait indefinitely
while true; do
    sleep 1
done
