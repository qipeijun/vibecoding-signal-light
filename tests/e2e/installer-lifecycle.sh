#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLI_BIN="${1:-$ROOT_DIR/.build/debug/signal-light-cli}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/signal-light-e2e.XXXXXX")"
TEST_HOME="$TEST_ROOT/home"
STATE_DIR="$TEST_ROOT/state"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

mkdir -p "$TEST_HOME/.claude" "$STATE_DIR" "$TEST_ROOT/usr/local/bin"

cat > "$TEST_ROOT/usr/local/bin/signal-light" <<SCRIPT
#!/usr/bin/env bash
exec "$CLI_BIN" "\$@"
SCRIPT
chmod +x "$TEST_ROOT/usr/local/bin/signal-light"

cat > "$TEST_HOME/.claude/settings.json" <<'JSON'
{
  "statusLine": { "type": "command", "command": "~/.claude/statusline.sh" },
  "hooks": {
    "PreToolUse": [{
      "hooks": [
        { "type": "command", "command": "/usr/local/bin/claude-code-signal-hook" },
        { "type": "command", "command": "/usr/local/bin/user-owned-hook" }
      ]
    }]
  }
}
JSON

env \
  SIGNAL_LIGHT_INSTALL_ROOT="$TEST_ROOT" \
  SIGNAL_LIGHT_INSTALL_TEST_MODE=1 \
  SIGNAL_LIGHT_CONSOLE_USER="$(id -un)" \
  SIGNAL_LIGHT_USER_HOME="$TEST_HOME" \
  SIGNAL_LIGHT_STATE_DIR="$STATE_DIR" \
  "$ROOT_DIR/scripts/installer-postinstall"

python3 -c '
import json, pathlib, sys
root = json.loads(pathlib.Path(sys.argv[1]).read_text())
commands = [item["command"] for group in root["hooks"]["PreToolUse"] for item in group["hooks"]]
assert commands == ["/usr/local/bin/user-owned-hook"], commands
assert root["statusLine"]["command"] == "~/.claude/statusline.sh"
' "$TEST_HOME/.claude/settings.json"

python3 -c '
import json, pathlib, sys
root = json.loads(pathlib.Path(sys.argv[1]).read_text())
required = {"SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "Stop", "SessionEnd"}
assert required.issubset(root["hooks"]), root["hooks"].keys()
' "$TEST_HOME/.codex/hooks.json"

grep -Fq "等待首次事件" "$TEST_HOME/Library/Application Support/Signal Light/hook-install-result.txt"

env HOME="$TEST_HOME" CFFIXED_USER_HOME="$TEST_HOME" SIGNAL_LIGHT_STATE_DIR="$STATE_DIR" \
  "$CLI_BIN" codex-hook SessionStart
test -f "$STATE_DIR/codex_hook_activity.json"

for name in current_status.json sessions.json history.json codex_hook_activity.json state.lock; do
  : > "$STATE_DIR/$name"
done
echo "keep" > "$STATE_DIR/user-project.txt"

env HOME="$TEST_HOME" CFFIXED_USER_HOME="$TEST_HOME" SIGNAL_LIGHT_STATE_DIR="$STATE_DIR" \
  "$CLI_BIN" _test-clean-state "$STATE_DIR"

test -d "$STATE_DIR"
test -f "$STATE_DIR/user-project.txt"
for name in current_status.json sessions.json history.json codex_hook_activity.json state.lock; do
  test ! -e "$STATE_DIR/$name"
done

OWNED_WRAPPER="$TEST_ROOT/owned-claude-code-signal-hook"
USER_WRAPPER="$TEST_ROOT/user-claude-code-signal-hook"
cat > "$OWNED_WRAPPER" <<'SCRIPT'
#!/usr/bin/env bash
exec "/Applications/Signal Light.app/Contents/Resources/bin/claude-code-signal-hook" "$@"
SCRIPT
cat > "$USER_WRAPPER" <<'SCRIPT'
#!/usr/bin/env bash
echo "user owned"
SCRIPT

env HOME="$TEST_HOME" CFFIXED_USER_HOME="$TEST_HOME" SIGNAL_LIGHT_STATE_DIR="$STATE_DIR" \
  "$CLI_BIN" cleanup-legacy-command --path "$OWNED_WRAPPER"
env HOME="$TEST_HOME" CFFIXED_USER_HOME="$TEST_HOME" SIGNAL_LIGHT_STATE_DIR="$STATE_DIR" \
  "$CLI_BIN" cleanup-legacy-command --path "$USER_WRAPPER"

test ! -e "$OWNED_WRAPPER"
test -f "$USER_WRAPPER"

echo "installer lifecycle e2e passed"
