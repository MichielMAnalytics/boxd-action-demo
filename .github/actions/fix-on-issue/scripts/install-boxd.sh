#!/usr/bin/env bash
# Install the boxd CLI onto the GitHub runner.
set -euo pipefail

curl -fsSL https://boxd.sh/downloads/cli/install.sh | sh
echo "$HOME/.local/bin" >> "$GITHUB_PATH"
