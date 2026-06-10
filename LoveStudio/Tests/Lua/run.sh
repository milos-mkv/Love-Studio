#!/bin/bash
# TestKit regression harness.
#
# Runs every Tests/Lua/*.test.lua fixture through the TestKit facade under the
# bundled headless `love`, then checks the overall pass/fail/error totals against
# the expected values below. Re-run after ANY change to the TestKit bundle.
#
#   ./Tests/Lua/run.sh
#
# Exit 0 = all expectations met; non-zero = a regression.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)/LoveStudio"   # .../LoveStudio/LoveStudio
KIT="$APP_DIR/Resources/TestKit.bundle"
LOVE="$APP_DIR/Resources/LoveRuntime/love.app/Contents/MacOS/love"

# --- expected totals across ALL fixtures (update when fixtures change) ----------
# structure  : 5 / 0 / 0
# hooks      : 4 / 0 / 0
# assertions : 7 / 1 / 1   (one deliberate fail, one deliberate error)
# doubles    : 6 / 0 / 0
# love       : 6 / 0 / 0
# std        : 5 / 0 / 0
# isolation  : 3 / 0 / 0
EXPECT_PASSED=36
EXPECT_FAILED=1
EXPECT_ERROR=1

if [ ! -x "$LOVE" ]; then echo "love binary not found at $LOVE" >&2; exit 2; fi
if [ ! -d "$KIT" ]; then echo "TestKit not found at $KIT" >&2; exit 2; fi

RUN="$(mktemp -d)"
trap 'rm -rf "$RUN"' EXIT

cat > "$RUN/conf.lua" <<'EOF'
function love.conf(t)
  t.window = false; t.modules.graphics = false; t.modules.audio = false
  t.modules.window = false; t.modules.sound = false; t.modules.physics = false
  t.modules.joystick = false
end
EOF

# Collect the fixture files (absolute paths) into the bootstrap.
FILES_LUA=""
for f in "$SCRIPT_DIR"/*.test.lua; do
  FILES_LUA="$FILES_LUA  \"$f\",\n"
done

cat > "$RUN/main.lua" <<EOF
function love.load()
  local realExit, realWrite = os.exit, io.write
  package.path = "$KIT/?.lua;$KIT/?/init.lua;" .. package.path
  local lt = require("lovetest")
  lt.configure{ emit = realWrite }
  lt.expose(_G)
  local files = {
$(printf "$FILES_LUA")
  }
  for _, f in ipairs(files) do
    local ok, err = pcall(function() lt.loadFile(f) end)
    if not ok then realWrite("LOADFAIL: " .. tostring(err) .. "\n") end
  end
  lt.run{}
  realExit(0)
end
function love.update() os.exit(0) end
function love.draw() end
EOF

OUT="$("$LOVE" "$RUN" 2>&1)"

# The TestKit prints a TAP summary line: "# passed N  failed N  error N"
SUMMARY="$(echo "$OUT" | grep -E '^# passed [0-9]+  failed [0-9]+  error [0-9]+' | tail -1)"
P=$(echo "$SUMMARY" | sed -E 's/^# passed ([0-9]+).*/\1/')
F=$(echo "$SUMMARY" | sed -E 's/.*failed ([0-9]+).*/\1/')
E=$(echo "$SUMMARY" | sed -E 's/.*error ([0-9]+).*/\1/')

echo "TestKit self-test: passed=$P failed=$F error=$E  (expected $EXPECT_PASSED/$EXPECT_FAILED/$EXPECT_ERROR)"

if [ -z "$SUMMARY" ]; then
  echo "FAIL: no TAP summary emitted — TestKit did not run." >&2
  echo "----- raw output -----" >&2
  echo "$OUT" >&2
  exit 1
fi

if [ "$P" = "$EXPECT_PASSED" ] && [ "$F" = "$EXPECT_FAILED" ] && [ "$E" = "$EXPECT_ERROR" ]; then
  echo "PASS: all TestKit functionality accounted for."
  exit 0
else
  echo "FAIL: totals do not match expectations." >&2
  echo "----- raw output -----" >&2
  echo "$OUT" >&2
  exit 1
fi
