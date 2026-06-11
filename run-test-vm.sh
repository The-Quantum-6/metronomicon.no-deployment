#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -f "$SCRIPT_DIR/.env" ]; then
  echo "Error: .env not found at $SCRIPT_DIR/.env" >&2
  exit 1
fi

export ENV_DIR="$SCRIPT_DIR"

echo "Starting VM with .env from $ENV_DIR"
exec "$(nix build ./deployment#nixosConfigurations.test-vm.config.system.build.vm --no-link --print-out-paths)/bin/run-nixos-vm"