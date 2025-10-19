#!/bin/bash
set -e

echo "=== Testing ExtProc Disable Policy Behavior ==="
echo ""

# Ensure agentgateway is enabled
echo "1. Enabling agentgateway..."
kubectl set env deployment/kgateway -n kgateway-system KGW_ENABLE_AGENTGATEWAY=true

echo ""
echo "2. Applying test manifests..."
kubectl apply -f gateway.yaml
kubectl apply -f routes.yaml
kubectl apply -f backend.yaml
kubectl apply -f extproc.yaml
kubectl apply -f traffic-policies.yaml

echo ""
echo "3. Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=backend --timeout=60s || true
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=ext-proc-grpc --timeout=60s || true

echo ""
echo "4. Creating curl pod..."
kubectl run curl --image=curlimages/curl:latest --restart=Never --rm -it -- sh -c "
echo '=== Testing route WITH disable policy (should NOT have ExtProc header) ===' && \
echo 'Request to disabled.example.com/disabled:' && \
curl -s -v -H 'Host: disabled.example.com' \
  -H 'instructions: {\"addHeaders\":{\"extproctest\":\"true\"},\"removeHeaders\":null}' \
  http://test-gateway.default.svc.cluster.local:8080/disabled 2>&1 | grep -E '(< |extproctest)' && \
echo '' && \
echo '=== Testing route WITHOUT disable policy (SHOULD have ExtProc header) ===' && \
echo 'Request to enabled.example.com/enabled:' && \
curl -s -v -H 'Host: enabled.example.com' \
  -H 'instructions: {\"addHeaders\":{\"extproctest\":\"true\"},\"removeHeaders\":null}' \
  http://test-gateway.default.svc.cluster.local:8080/enabled 2>&1 | grep -E '(< |extproctest)'
" || true

echo ""
echo "5. Checking TrafficPolicy statuses..."
kubectl get trafficpolicies -o wide

echo ""
echo "6. Cleaning up..."
read -p "Press Enter to clean up resources..."
kubectl delete -f traffic-policies.yaml
kubectl delete -f extproc.yaml
kubectl delete -f backend.yaml
kubectl delete -f routes.yaml
kubectl delete -f gateway.yaml

echo "Test complete!"