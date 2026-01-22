#!/usr/bin/env bash
# Run Docker-based tests for mise-postgres-binary
#
# Usage:
#   ./test/run-docker-tests.sh           # Run all tests
#   ./test/run-docker-tests.sh debian    # Run Debian tests only
#   ./test/run-docker-tests.sh alpine    # Run Alpine tests only
#   ./test/run-docker-tests.sh arm64     # Run ARM64 tests (requires QEMU or ARM host)

set -euo pipefail

cd "$(dirname "$0")/.."

FILTER="${1:-all}"
COMPOSE_FILE="test/docker-compose.yml"

echo "=== mise-postgres-binary Docker Tests ==="
echo "Filter: $FILTER"
echo ""

run_test() {
    local service="$1"
    echo "--- Testing: $service ---"
    if docker compose -f "$COMPOSE_FILE" build "$service" && \
       docker compose -f "$COMPOSE_FILE" run --rm "$service"; then
        echo "PASS: $service"
        return 0
    else
        echo "FAIL: $service"
        return 1
    fi
}

FAILED=0

case "$FILTER" in
    debian)
        run_test debian-pg15 || FAILED=1
        run_test debian-pg16 || FAILED=1
        run_test debian-pg17 || FAILED=1
        ;;
    alpine)
        run_test alpine-pg15 || FAILED=1
        run_test alpine-pg16 || FAILED=1
        ;;
    arm64)
        run_test debian-arm64-pg15 || FAILED=1
        run_test alpine-arm64-pg15 || FAILED=1
        ;;
    all)
        run_test debian-pg15 || FAILED=1
        run_test debian-pg16 || FAILED=1
        run_test debian-pg17 || FAILED=1
        run_test alpine-pg15 || FAILED=1
        run_test alpine-pg16 || FAILED=1
        ;;
    *)
        run_test "$FILTER" || FAILED=1
        ;;
esac

echo ""
if [ "$FAILED" -eq 0 ]; then
    echo "=== All tests passed ==="
    exit 0
else
    echo "=== Some tests failed ==="
    exit 1
fi
