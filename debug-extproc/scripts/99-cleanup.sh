#!/bin/bash

echo "=== Cleaning Up ExtProc Debug Environment ==="
echo ""

echo "Deleting namespace extproc-debug..."
kubectl delete namespace extproc-debug

echo ""
echo "Cleanup complete!"
