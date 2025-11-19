#!/bin/bash
set -e

echo "=== Deploying ExtProc Debug Environment ==="
echo ""

echo "Step 1: Creating namespace..."
kubectl apply -f manifests/00-namespace.yaml

echo ""
echo "Step 2: Deploying backend service..."
kubectl apply -f manifests/01-backend-service.yaml

echo ""
echo "Step 3: Deploying extproc service..."
kubectl apply -f manifests/02-extproc-service.yaml

echo ""
echo "Step 4: Deploying gateway..."
kubectl apply -f manifests/03-gateway.yaml

echo ""
echo "Step 5: Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=backend-0 -n extproc-debug --timeout=60s
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=ext-proc-grpc -n extproc-debug --timeout=60s
kubectl wait --for=condition=ready pod -l gateway.networking.k8s.io/gateway-name=gw -n extproc-debug --timeout=120s

echo ""
echo "Step 6: Deploying routes and policy..."
kubectl apply -f manifests/04-routes-and-policy.yaml

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Pod Status:"
kubectl get pods -n extproc-debug -o wide

echo ""
echo "Service Status:"
kubectl get svc -n extproc-debug

echo ""
echo "Gateway Status:"
kubectl get gateway -n extproc-debug

echo ""
echo "AgentgatewayPolicy Status:"
kubectl get agentgatewaypolicy -n extproc-debug

echo ""
echo "=== Ready for testing ==="
echo "Run './scripts/02-watch-logs.sh' to monitor all logs"
echo "Run './scripts/03-test-request.sh' to send test requests"
