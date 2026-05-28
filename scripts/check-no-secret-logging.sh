#!/usr/bin/env bash
# Fails if any Swift source file contains a debug-style log call that
# captures something credential-shaped. This is the SECURITY guardrail
# against the "developer added print(passValue) to debug, forgot to
# remove it, shipped to TestFlight" failure mode.
#
# What we forbid:
#   print(...password...)
#   print(...passValue...)
#   print(...privateKey...)
#   print(...KeychainService.load...)
#   print(....rawRepresentation...)
#   plus the same for NSLog, dump, debugPrint
#
# Run modes:
#   ./scripts/check-no-secret-logging.sh              ← manual check
#   ln -s ../../scripts/check-no-secret-logging.sh .git/hooks/pre-commit
#   (or run scripts/install-git-hooks.sh)
#
# Exit codes:
#   0  clean
#   1  at least one violation
#   2  bad invocation
set -euo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null || dirname "$0")/.."

# Multi-line OR so each forbidden identifier is its own readable rule.
FORBIDDEN=(
    'password'
    'passValue'
    'privateKey'
    'KeychainService\.load'
    '\.rawRepresentation'
)

# Logging primitives we care about. NSLog covers Obj-C bridges.
LOGGERS='(print|NSLog|dump|debugPrint)'

# Build the combined regex: log_func(...one of the forbidden things...)
PATTERN="${LOGGERS}\([^)]*(${FORBIDDEN[0]}"
for term in "${FORBIDDEN[@]:1}"; do
    PATTERN="${PATTERN}|${term}"
done
PATTERN="${PATTERN})"

# Only check our own .swift sources. Skip:
#   - Citadel / NIOSSH vendored under DerivedData (not in repo anyway)
#   - This script itself (which contains the pattern in a comment)
#   - The audit script that documents the pattern
FILES=$(git ls-files '*.swift' 2>/dev/null || find . -name '*.swift' \
    -not -path './*/DerivedData/*' -not -path './scripts/*')

FAIL=0
while IFS= read -r f; do
    [ -z "$f" ] && continue
    matches=$(grep -nE "$PATTERN" "$f" 2>/dev/null || true)
    if [ -n "$matches" ]; then
        echo "❌ $f"
        echo "$matches" | sed 's/^/   /'
        FAIL=1
    fi
done <<< "$FILES"

if [ $FAIL -eq 0 ]; then
    echo "✅ no secret-logging patterns found"
    exit 0
fi

cat <<'EOF'

A debug log call appears to capture a credential-shaped value.
If you really need to print this (e.g. it's a metric value that
happens to share a name), rename the local variable or restructure
the log so the forbidden identifier isn't an argument to print().

Override (use sparingly, with a code-review comment explaining why):
    git commit --no-verify

EOF
exit 1
