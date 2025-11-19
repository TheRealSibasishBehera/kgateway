#!/bin/bash

echo "=== Resource Status ==="
echo ""

echo "Namespace:"
kubectl get ns extproc-debug
echo ""

echo "Pods:"
kubectl get pods -n extproc-debug -o wide
echo ""

echo "Services:"
kubectl get svc -n extproc-debug
echo ""

echo "Gateway:"
kubectl get gateway -n extproc-debug -o yaml
echo ""

echo "HTTPRoutes:"
kubectl get httproute -n extproc-debug -o yaml
echo ""

echo "AgentgatewayPolicy:"
kubectl get agentgatewaypolicy -n extproc-debug -o yaml
echo ""

echo "=== Detailed Resource Descriptions ==="
echo ""

echo "Gateway gw:"
kubectl describe gateway gw -n extproc-debug
echo ""

echo "AgentgatewayPolicy gateway-test:"
kubectl describe agentgatewaypolicy gateway-test -n extproc-debug
echo ""

echo "=== Events ==="
kubectl get events -n extproc-debug --sort-by='.lastTimestamp'
