#!/bin/bash

echo "=== Sending Test Requests ==="
echo ""

# Get gateway pod and service details
GATEWAY_POD=$(kubectl get pod -n extproc-debug -l gateway.networking.k8s.io/gateway-name=gw -o jsonpath='{.items[0].metadata.name}')
GATEWAY_SVC=$(kubectl get svc -n extproc-debug gw -o jsonpath='{.spec.clusterIP}')

echo "Gateway: $GATEWAY_POD ($GATEWAY_SVC:8080)"
echo ""

# Create a temporary curl pod if it doesn't exist
if ! kubectl get pod curl -n extproc-debug &>/dev/null; then
    echo "Creating curl pod for testing..."
    kubectl run curl -n extproc-debug --image=curlimages/curl:latest --restart=Never -- sleep infinity
    kubectl wait --for=condition=ready pod/curl -n extproc-debug --timeout=60s
    echo ""
fi

echo "Test 1: Request with extproc instructions (should add header)"
echo "-----------------------------------------------------------"
echo ""

INSTRUCTIONS='{"addHeaders":{"extproctest":"true"}}'

kubectl exec -n extproc-debug curl -- curl -s -v \
    -H "Host: www.example.com" \
    -H "instructions: $INSTRUCTIONS" \
    "http://gw.extproc-debug.svc.cluster.local:8080/" 2>&1 | tee /tmp/test-output-1.txt

echo ""
echo "-----------------------------------------------------------"
echo ""

# Parse the response to check for the header
if grep -q "Extproctest" /tmp/test-output-1.txt; then
    echo "✅ SUCCESS: ExtProc header found in response!"
else
    echo "❌ FAILURE: ExtProc header NOT found in response"
    echo ""
    echo "Expected to see 'Extproctest' in the headers section"
fi

echo ""
echo "Test 2: Simple request to / path"
echo "-----------------------------------------------------------"
echo ""

kubectl exec -n extproc-debug curl -- curl -s \
    -H "Host: www.example.com" \
    "http://gw.extproc-debug.svc.cluster.local:8080/" | jq .

echo ""
echo "Test 3: Request to /myapp path"
echo "-----------------------------------------------------------"
echo ""

kubectl exec -n extproc-debug curl -- curl -s \
    -H "Host: www.example.com" \
    "http://gw.extproc-debug.svc.cluster.local:8080/myapp" | jq .

echo ""
echo "=== Test Complete ==="
echo ""
echo "Check the logs in logs/ directory for detailed information"
