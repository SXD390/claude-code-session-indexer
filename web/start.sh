#!/usr/bin/env bash
#
# Claude Code Session Indexer — Web  ·  launcher for macOS / Linux
# Starts the local server and opens your browser. Zero dependencies.
#
set -e

# Move to this script's directory so relative paths resolve.
cd "$(dirname "$0")"

if ! command -v node >/dev/null 2>&1; then
  echo ""
  echo "  Node.js 18+ is required but was not found on your PATH."
  echo "  Install it from https://nodejs.org and try again."
  echo ""
  exit 1
fi

PORT="${PORT:-4747}"
URL="http://127.0.0.1:${PORT}"

echo ""
echo "  Starting Claude Code Session Indexer on ${URL}"
echo "  (Press Ctrl+C to stop.)"
echo ""

# Open the browser shortly after the server binds.
(
  sleep 1.5
  if command -v open >/dev/null 2>&1; then
    open "$URL"                 # macOS
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$URL" >/dev/null 2>&1   # Linux
  fi
) &

exec node server.js
