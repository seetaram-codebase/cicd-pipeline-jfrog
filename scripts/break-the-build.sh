#!/usr/bin/env bash
# Toggles app/base-image.env between a deliberately outdated Python base
# image (Debian Buster, EOL — trips the Xray Critical/High gate) and a
# current patched one. Run it, commit, push — that's the live "blocked
# promotion" demo moment.
set -euo pipefail

ENV_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/app/base-image.env"
VULNERABLE="3.9-slim-buster"
PATCHED="3.11-slim-bookworm"

current="$(grep -oP '(?<=PYTHON_VERSION=).*' "$ENV_FILE")"

if [[ "$current" == "$VULNERABLE" ]]; then
  echo "PYTHON_VERSION=$PATCHED" > "$ENV_FILE"
  echo "Switched to patched base image: $PATCHED"
  echo "Expect: Xray gate passes, promotion proceeds."
else
  echo "PYTHON_VERSION=$VULNERABLE" > "$ENV_FILE"
  echo "Switched to vulnerable base image: $VULNERABLE"
  echo "Expect: Xray gate blocks promotion at dev -> staging."
fi
