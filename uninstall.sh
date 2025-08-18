#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="${BTOR_HOME:-$HOME/.btor}"
BIN_LINK="/usr/local/bin/btor"

echo "Uninstalling BTor..."
sudo rm -f "${BIN_LINK}" || true
rm -rf "${TARGET_DIR}" || true
echo "Done."
