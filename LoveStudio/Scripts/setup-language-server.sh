#!/bin/sh
# Fetches lua-language-server (pinned + checksummed) and extracts it for the
# build to bundle. Run once after cloning and in CI before xcodebuild — it lives
# outside Xcode so it can use the network. Nothing it produces is committed; the
# app falls back to static-table completion if it's skipped.

set -eu

VERSION="3.18.2"
BASE_URL="https://github.com/LuaLS/lua-language-server/releases/download/${VERSION}"

# Extract into Vendor/ (outside the synced source tree) so a Copy Files phase can
# add it to the bundle as a folder reference instead of folder-sync flattening it.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
DEST_DIR="${PROJECT_DIR}/Vendor/LuaLS"
CACHE_DIR="${SCRIPT_DIR}/.cache/LuaLS"

# arch name -> pinned tarball SHA256
sha_arm64="cec99d70b1f612acec4a10a79a03664e3aa0c229d4d8a586cb3f928ec37d509e"
sha_x64="e26cfefe423dd7326fc7c649539e4d4aaa4f35f34d2fefd8af2ed7090b72c556"

# Sign with whatever identity is provided, ad-hoc by default for local builds.
IDENTITY="${CODE_SIGN_IDENTITY:--}"

mkdir -p "${CACHE_DIR}"

setup_arch() {
    ARCH="$1"      # arm64 | x64
    EXPECTED="$2"  # pinned sha256
    NAME="lua-language-server-${VERSION}-darwin-${ARCH}.tar.gz"
    TARBALL="${CACHE_DIR}/${NAME}"
    OUT="${DEST_DIR}/${ARCH}"

    # Download to cache if missing or stale.
    if [ ! -f "${TARBALL}" ] || [ "$(shasum -a 256 "${TARBALL}" | awk '{print $1}')" != "${EXPECTED}" ]; then
        echo "Fetching ${NAME}"
        curl -fsSL "${BASE_URL}/${NAME}" -o "${TARBALL}"
    fi

    ACTUAL="$(shasum -a 256 "${TARBALL}" | awk '{print $1}')"
    if [ "${ACTUAL}" != "${EXPECTED}" ]; then
        echo "error: checksum mismatch for ${ARCH}: expected ${EXPECTED}, got ${ACTUAL}" >&2
        exit 1
    fi

    echo "Extracting ${ARCH} -> ${OUT}"
    rm -rf "${OUT}"
    mkdir -p "${OUT}"
    tar -xzf "${TARBALL}" -C "${OUT}"

    BIN="${OUT}/bin/lua-language-server"
    if [ -f "${BIN}" ]; then
        codesign --force --sign "${IDENTITY}" --timestamp=none "${BIN}"
    fi
}

setup_arch arm64 "${sha_arm64}"
setup_arch x64 "${sha_x64}"

echo "lua-language-server ${VERSION} ready in ${DEST_DIR}"
