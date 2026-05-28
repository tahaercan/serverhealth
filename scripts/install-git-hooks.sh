#!/usr/bin/env bash
# Installs the security-check script as a git pre-commit hook.
# Idempotent — safe to re-run after pulling new hooks.
#
# After running once, every `git commit` runs the secret-logging check
# automatically. To skip in an emergency: `git commit --no-verify`.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
HOOKS_DIR="$REPO_ROOT/.git/hooks"
HOOK_PATH="$HOOKS_DIR/pre-commit"
TARGET="$REPO_ROOT/scripts/check-no-secret-logging.sh"

mkdir -p "$HOOKS_DIR"

# Wrapper rather than direct symlink — lets us chain additional checks
# later without rewriting the symlink, and works correctly even when the
# user moves the repo (no broken absolute symlinks).
cat > "$HOOK_PATH" <<'EOF'
#!/usr/bin/env bash
# Auto-installed by scripts/install-git-hooks.sh — do not edit by hand.
# Re-run that script after pulling new hooks.
set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"
"$REPO_ROOT/scripts/check-no-secret-logging.sh"
EOF

chmod +x "$HOOK_PATH"
chmod +x "$TARGET"

echo "✅ Installed pre-commit hook at $HOOK_PATH"
echo "   Every \`git commit\` will now run scripts/check-no-secret-logging.sh"
