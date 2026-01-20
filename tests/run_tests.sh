#!/bin/bash
# Run all patchview.nvim tests
# Usage: ./tests/run_tests.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "Running patchview.nvim tests..."
echo "================================"
echo ""

# Run diff tests
echo "--- Diff Module Tests ---"
nvim --headless -u NONE \
  -c "set rtp+=." \
  -c "lua dofile('tests/test_diff.lua')" \
  -c "q"

echo ""

# Run hunks tests
echo "--- Hunks Module Tests ---"
nvim --headless -u NONE \
  -c "set rtp+=." \
  -c "lua dofile('tests/test_hunks.lua')" \
  -c "q"

echo ""

# Run integration test if exists
if [ -f "tests/test_integration.lua" ]; then
  echo "--- Integration Tests ---"
  nvim --headless -u NONE \
    -c "set rtp+=." \
    -c "lua dofile('tests/test_integration.lua')" \
    -c "q"
  echo ""
fi

echo "================================"
echo "All tests completed!"
