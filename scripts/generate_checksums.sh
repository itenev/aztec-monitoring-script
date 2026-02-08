#!/usr/bin/env bash
# Generate SHA256SUMS for start.sh, config.json, and scripts/*.sh
# Run from repo root. Output is written to stdout; redirect to SHA256SUMS for releases.
# Users can verify with: sha256sum -c SHA256SUMS

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

echo "# SHA-256 checksums for integrity verification. Generated: $(date -u +%Y-%m-%d)"
echo "# Verify with: sha256sum -c SHA256SUMS"
sha256sum start.sh config.json 2>/dev/null || true
for f in scripts/*.sh; do
  [ -f "$f" ] && sha256sum "$f"
done
