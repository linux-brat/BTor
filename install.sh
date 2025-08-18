#!/usr/bin/env bash
set -euo pipefail

REPO_RAW="${BTOR_REPO:-https://raw.githubusercontent.com/youruser/btor/main}"
TARGET_DIR="${BTOR_HOME:-$HOME/.btor}"
BIN_LINK="/usr/local/bin/btor"

echo "Installing BTor to ${TARGET_DIR}..."

mkdir -p "${TARGET_DIR}"
curl -fsSL "${REPO_RAW}/btor" -o "${TARGET_DIR}/btor"
chmod +x "${TARGET_DIR}/btor"

# Fetch version
if curl -fsSL "${REPO_RAW}/VERSION" -o "${TARGET_DIR}/VERSION"; then
  :
else
  echo "0.0.0" > "${TARGET_DIR}/VERSION"
fi

# Create symlink
if [[ ! -e "${BIN_LINK}" ]]; then
  echo "Linking ${BIN_LINK} (requires sudo)..."
  sudo ln -sf "${TARGET_DIR}/btor" "${BIN_LINK}"
else
  echo "Updating ${BIN_LINK} (requires sudo)..."
  sudo ln -sf "${TARGET_DIR}/btor" "${BIN_LINK}"
fi

echo "BTor installed."
echo
echo "Usage:"
echo "  btor            # interactive menu"
echo "  btor status     # status summary"
echo
