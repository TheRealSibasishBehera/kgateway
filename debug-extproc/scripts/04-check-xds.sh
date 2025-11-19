#!/bin/bash

echo "=== Checking XDS Configuration ==="
echo ""

GATEWAY_POD=$(kubectl get pod -n extproc-debug -l gateway.networking.k8s.io/gateway-name=gw -o jsonpath='{.items[0].metadata.name}')

if [ -z "$GATEWAY_POD" ]; then
    echo "ERROR: Gateway pod not found"
    exit 1
fi

echo "Gateway Pod: $GATEWAY_POD"
echo ""

# Check if agentgateway has admin interface
echo "Attempting to access agentgateway admin interface..."
echo "-----------------------------------------------------------"
echo ""

# First, let's see what ports are available
echo "Available ports on gateway pod:"
kubectl get pod -n extproc-debug "$GATEWAY_POD" -o json | jq -r '.spec.containers[].ports[]? | "\(.name // "unnamed"): \(.containerPort)"'
echo ""

# Try to get config dump (agentgateway typically exposes admin on 19000 or 15000)
for port in 19000 15000 9901; do
    echo "Trying port $port..."
    kubectl exec -n extproc-debug "$GATEWAY_POD" -- curl -s "http://localhost:$port/config_dump" 2>/dev/null > /tmp/config_dump_${port}.json

    if [ -s /tmp/config_dump_${port}.json ]; then
        echo "✅ Found admin interface on port $port"
        echo ""

        echo "Searching for ExtProc configuration..."
        if grep -qi "ext_proc" /tmp/config_dump_${port}.json; then
            echo "✅ Found ext_proc in configuration!"
            echo ""
            echo "ExtProc Configuration:"
            jq '.configs[] | select(.["@type"] | contains("HttpConnectionManager"))? | .dynamic_route_configs[].route_config.virtual_hosts[].routes[].typed_per_filter_config? | select(. != null)' /tmp/config_dump_${port}.json 2>/dev/null
        else
            echo "❌ No ext_proc found in configuration"
            echo ""
            echo "Full config saved to /tmp/config_dump_${port}.json for manual inspection"
        fi

        echo ""
        echo "Clusters (backends):"
        jq -r '.configs[] | select(.["@type"] | contains("Cluster"))? | .dynamic_active_clusters[]?.cluster.name // .static_clusters[]?.name' /tmp/config_dump_${port}.json 2>/dev/null | sort | uniq

        break
    fi
done

echo ""
echo "-----------------------------------------------------------"

# Also check the kgateway controller's XDS snapshots if possible
KGATEWAY_NS=$(kubectl get pods -A -l app=kgateway 2>/dev/null | grep -v NAME | head -1 | awk '{print $1}')
KGATEWAY_POD=$(kubectl get pods -n "$KGATEWAY_NS" -l app=kgateway -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$KGATEWAY_POD" ]; then
    echo ""
    echo "Checking KGateway Controller XDS Snapshots..."
    echo "-----------------------------------------------------------"
    echo ""

    # KGateway typically exposes debug endpoint on 9095
    kubectl exec -n "$KGATEWAY_NS" "$KGATEWAY_POD" -- curl -s "http://localhost:9095/snapshots/xds" 2>/dev/null > /tmp/kgateway_xds.json

    if [ -s /tmp/kgateway_xds.json ]; then
        echo "✅ Retrieved XDS snapshot from controller"

        if grep -qi "extproc\|ext_proc" /tmp/kgateway_xds.json; then
            echo "✅ Found extproc in XDS snapshot!"
            echo ""
            echo "Full XDS snapshot saved to /tmp/kgateway_xds.json"
        else
            echo "❌ No extproc found in XDS snapshot"
            echo ""
            echo "This suggests the controller is not generating extproc configuration"
            echo "Full XDS snapshot saved to /tmp/kgateway_xds.json for inspection"
        fi
    else
        echo "⚠️  Could not retrieve XDS snapshot (may not be exposed)"
    fi
fi

echo ""
echo "=== XDS Check Complete ==="
