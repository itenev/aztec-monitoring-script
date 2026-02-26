#!/usr/bin/env bash
# =============================================================================
# make_dist.sh — Build a distribution tarball for the Aztec monitoring toolkit
# =============================================================================
#
# USAGE:
#   ./make_dist.sh
#
# WHAT IT DOES:
#   Reads the version from start.sh, copies only the files needed by end users
#   into a clean staging directory, then produces a gzip tarball named:
#       aztec-monitoring-script-v<VERSION>.tar.gz
#   in the repository root.
#
# WHAT IS EXCLUDED (dev/backup/legacy — not needed at runtime):
#   - scripts/generate_checksums.sh      (maintainer tool)
#   - other/aztec-logs-dev.sh / -old.sh  (pre-refactor monolithic scripts)
#   - other/aztec-logs-dev.sh.backup
#   - other/check-validator-*.sh         (old standalone scripts)
#   - other/install_aztec-*.sh           (old standalone scripts)
#   - other/logo.sh
#   - other/aztec-script-files/          (older duplicate JSON copies)
#   - other/Aztec-Install-by-Script.md   (duplicated in en/ and tr/)
#   - other/BLS-gen-Approve-Stake.md     (duplicated in en/ and tr/)
#   - other/Aztec-Install-by-Script/     (screenshot assets)
#   - other/*.png / other/Скриншот*.png  (screenshots)
#   - SECURITY_IMPROVEMENT_PLAN.md       (internal audit doc)
#   - .git/
#   - Any .env* files
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# 0. Resolve repo root (the directory containing this script)
# ---------------------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# 1. Read version from start.sh
# ---------------------------------------------------------------------------
VERSION_LINE="$(grep '^SCRIPT_VERSION=' "${REPO_ROOT}/start.sh" | head -1)"
VERSION="${VERSION_LINE#SCRIPT_VERSION=}"   # strip key=
VERSION="${VERSION//\"/}"                   # strip surrounding quotes
VERSION="${VERSION//\'/}"                   # strip surrounding single-quotes

if [[ -z "${VERSION}" ]]; then
    echo "ERROR: Could not parse SCRIPT_VERSION from start.sh" >&2
    exit 1
fi

echo "Building distribution for version: ${VERSION}"

# ---------------------------------------------------------------------------
# 2. Define output tarball name
# ---------------------------------------------------------------------------
DIST_NAME="aztec-monitoring-script-v${VERSION}"
OUTPUT_TAR="${REPO_ROOT}/${DIST_NAME}.tar.gz"

# Warn and remove if the tarball already exists
if [[ -f "${OUTPUT_TAR}" ]]; then
    echo "WARNING: ${OUTPUT_TAR} already exists — overwriting."
    rm -f "${OUTPUT_TAR}"
fi

# ---------------------------------------------------------------------------
# 3. Create a temporary staging directory
# ---------------------------------------------------------------------------
STAGING_DIR="$(mktemp -d)"
# Ensure staging is cleaned up on exit (normal or error)
trap 'rm -rf "${STAGING_DIR}"' EXIT

STAGE="${STAGING_DIR}/${DIST_NAME}"
mkdir -p "${STAGE}"

echo "Staging into: ${STAGE}"

# ---------------------------------------------------------------------------
# Helper: copy a file preserving its relative directory structure
# ---------------------------------------------------------------------------
stage_file() {
    local rel_path="$1"          # path relative to REPO_ROOT
    local src="${REPO_ROOT}/${rel_path}"
    local dst="${STAGE}/${rel_path}"

    if [[ ! -f "${src}" ]]; then
        echo "WARNING: expected file not found, skipping: ${rel_path}" >&2
        return
    fi

    mkdir -p "$(dirname "${dst}")"
    cp -p "${src}" "${dst}"
}

# ---------------------------------------------------------------------------
# 4. Copy essential files into staging
# ---------------------------------------------------------------------------

# Top-level files
stage_file "start.sh"
stage_file "config.json"
stage_file "SHA256SUMS"
stage_file "README.md"

# scripts/*.sh — everything EXCEPT generate_checksums.sh
while IFS= read -r -d '' script_file; do
    rel="scripts/$(basename "${script_file}")"
    if [[ "$(basename "${script_file}")" == "generate_checksums.sh" ]]; then
        echo "  (skipping maintainer tool: ${rel})"
        continue
    fi
    stage_file "${rel}"
done < <(find "${REPO_ROOT}/scripts" -maxdepth 1 -name '*.sh' -print0 | sort -z)

# other/ — only the two canonical JSON files
stage_file "other/error_definitions.json"
stage_file "other/version_control.json"

# English docs
stage_file "en/README.md"
stage_file "en/Aztec-Install-by-Script.md"
stage_file "en/BLS-gen-Approve-Stake.md"

# Turkish docs
stage_file "tr/README.md"
stage_file "tr/Aztec-Install-by-Script.md"
stage_file "tr/BLS-gen-Approve-Stake.md"

# ---------------------------------------------------------------------------
# 5. Print manifest of included files (sorted, relative to dist root)
# ---------------------------------------------------------------------------
echo ""
echo "=== Manifest (files included in tarball) ==="
find "${STAGE}" -type f | sed "s|${STAGE}/||" | sort
echo "============================================"
echo ""

# ---------------------------------------------------------------------------
# 6. Create the gzip tarball from the staging directory
#    The tarball extracts into a single top-level directory: ${DIST_NAME}/
# ---------------------------------------------------------------------------
tar -czf "${OUTPUT_TAR}" -C "${STAGING_DIR}" "${DIST_NAME}"

# ---------------------------------------------------------------------------
# 7. Print summary
# ---------------------------------------------------------------------------
CHECKSUM="$(sha256sum "${OUTPUT_TAR}" | awk '{print $1}')"

echo "Output file : ${OUTPUT_TAR}"
echo "SHA-256     : ${CHECKSUM}"
echo ""
echo "Done."
