#!/bin/bash
# FRIDAY — EDA Intelligence System Launcher
# Usage: bash /proj/rtg_oss_feint1/FEINT_AI_AGENT/genie_agent/start_friday.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT=5100

echo "============================================================"
echo "  FRIDAY — EDA Intelligence System"
echo "============================================================"
echo "  Dir  : $SCRIPT_DIR"
echo "  Port : $PORT"
echo "============================================================"

# Check Flask is available
python3 -c "import flask" 2>/dev/null || {
  echo "  Installing Flask..."
  pip3 install flask --user -q
}

# Kill any existing FRIDAY server on this port
lsof -ti:$PORT 2>/dev/null | xargs kill -9 2>/dev/null
sleep 0.5

# Check for API key
if [ -z "$ANTHROPIC_API_KEY" ]; then
  echo "  WARNING: ANTHROPIC_API_KEY not set — AI responses disabled."
  echo "  Run: export ANTHROPIC_API_KEY=your-key-here"
fi

# Start server in background
cd "$SCRIPT_DIR"
ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" python3 friday_server.py &
SERVER_PID=$!
echo "  Server PID: $SERVER_PID"

# Wait for server to be ready
echo -n "  Waiting for server"
for i in $(seq 1 10); do
  sleep 0.5
  if curl -s http://localhost:$PORT/api/health >/dev/null 2>&1; then
    echo " ready."
    break
  fi
  echo -n "."
done

# Open Chrome (try multiple binary names)
URL="http://localhost:$PORT"
echo "  Opening: $URL"
for BIN in google-chrome google-chrome-stable chromium-browser chromium; do
  if command -v $BIN &>/dev/null; then
    $BIN "$URL" &>/dev/null &
    break
  fi
done

echo "============================================================"
echo "  FRIDAY is running at $URL"
echo "  Press Ctrl+C to stop."
echo "============================================================"

# Keep script alive, kill server on Ctrl+C
trap "echo '  Shutting down FRIDAY...'; kill $SERVER_PID 2>/dev/null; exit 0" INT TERM
wait $SERVER_PID
