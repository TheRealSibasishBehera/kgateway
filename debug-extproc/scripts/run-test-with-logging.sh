#!/bin/bash
set -e

echo "=== ExtProc Test with Comprehensive Logging ==="
echo ""

# Get the repo root directory (assumes script is in kgateway/debug-extproc/scripts/)
REPO_ROOT="$(cd "$(dirname "$0")/../../" && pwd)"
cd "$REPO_ROOT"

# Create logs directory in debug-extproc
DEBUG_DIR="$REPO_ROOT/debug-extproc"
mkdir -p "$DEBUG_DIR/logs"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_DIR="$DEBUG_DIR/logs/${TIMESTAMP}"
mkdir -p "$LOG_DIR"

echo "Repository root: $REPO_ROOT"
echo "Logs will be saved to: $LOG_DIR"
echo ""

# Function to collect logs from a pod
collect_logs() {
    local namespace=$1
    local label=$2
    local logname=$3
    local max_wait=$4

    echo "Waiting for pod with label $label in namespace $namespace..."

    local waited=0
    while [ $waited -lt $max_wait ]; do
        POD=$(kubectl get pod -n "$namespace" -l "$label" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [ -n "$POD" ]; then
            echo "Found pod: $POD"
            kubectl logs -f -n "$namespace" "$POD" > "$LOG_DIR/${logname}.log" 2>&1 &
            echo "Started logging $logname to $LOG_DIR/${logname}.log"
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
    done

    echo "WARNING: Could not find pod with label $label in namespace $namespace after ${max_wait}s"
    return 1
}

# Start the test in background
echo "Starting extproc test from: $REPO_ROOT"
echo ""

(go test -tags e2e -v ./test/e2e/tests -run TestAgentgatewayIntegration/Extproc/TestExtProcWithGatewayTargetRef -timeout 30m 2>&1 | tee "$LOG_DIR/test-output.log") &
TEST_PID=$!

echo "Test started with PID: $TEST_PID"
echo ""

# Wait for test to set up namespace and resources
echo "Waiting for test infrastructure to be created..."
sleep 15

# Try to find and log the controller
echo ""
echo "Looking for kgateway controller..."
for namespace in agent-gateway-test kgateway-system kube-system default; do
    POD=$(kubectl get pods -n "$namespace" -l app=kgateway -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$POD" ]; then
        echo "Found kgateway controller in namespace $namespace: $POD"
        kubectl logs -f --all-containers=true -n "$namespace" "$POD" > "$LOG_DIR/kgateway-controller.log" 2>&1 &
        echo "Started logging controller to $LOG_DIR/kgateway-controller.log"
        CONTROLLER_NS=$namespace
        break
    fi
done

# Collect logs from test pods
echo ""
echo "Collecting logs from test pods..."
echo ""

collect_logs "default" "gateway.networking.k8s.io/gateway-name=gw" "gateway" 60 &
collect_logs "default" "app.kubernetes.io/name=ext-proc-grpc" "extproc" 60 &
collect_logs "default" "app.kubernetes.io/name=backend-0" "backend" 60 &

# Wait a bit for logs to start
sleep 5

echo ""
echo "=== Log collection started ==="
echo ""
echo "Monitoring test progress. The test will sleep for 2 minutes during execution."
echo "Press Ctrl+C to stop (logs will be saved)"
echo ""

# Function to cleanup on exit
cleanup() {
    echo ""
    echo "Stopping log collection..."
    jobs -p | xargs -r kill 2>/dev/null || true

    # Give a moment for logs to flush
    sleep 2

    echo ""
    echo "=== Log Collection Summary ==="
    echo ""
    echo "Logs saved to: $LOG_DIR"
    echo ""
    ls -lh "$LOG_DIR"
    echo ""
    echo "Test output: $LOG_DIR/test-output.log"
    echo ""

    # Check if test is still running
    if ps -p $TEST_PID > /dev/null 2>&1; then
        echo "Test is still running (PID: $TEST_PID)"
        echo "You can check its progress with: tail -f $LOG_DIR/test-output.log"
    else
        wait $TEST_PID
        TEST_EXIT=$?
        if [ $TEST_EXIT -eq 0 ]; then
            echo "✅ Test completed successfully"
        else
            echo "❌ Test failed with exit code: $TEST_EXIT"
        fi
    fi

    echo ""
    echo "To analyze logs:"
    echo "  - Controller: cat $LOG_DIR/kgateway-controller.log"
    echo "  - Gateway:    cat $LOG_DIR/gateway.log"
    echo "  - ExtProc:    cat $LOG_DIR/extproc.log"
    echo "  - Backend:    cat $LOG_DIR/backend.log"
    echo ""
    echo "Quick analysis:"
    echo "  grep -i 'extproc\|ext_proc' $LOG_DIR/*.log"
    echo ""
}

trap cleanup EXIT INT TERM

# Wait for test to complete or user interrupt
wait $TEST_PID
