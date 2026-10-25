#!/usr/bin/env bash
# Computes the full multi-instance desktop dev environment.
# Source this file from desktop dev commands; it exports:
#   BUZZ_VITE_PORT, BUZZ_HMR_PORT, VITE_PORT, VITE_HMR_PORT
#   BUZZ_RELAY_PORT, BUZZ_RELAY_URL
#   BUZZ_INSTANCE_SLUG, BUZZ_WORKTREE_LABEL, VITE_DEV_BRANCH (worktrees only)
#   BUZZ_TAURI_CONFIG
#   BUZZ_PRIVATE_KEY (worktrees only, when BUZZ_SHARE_IDENTITY=1)

WORKTREE_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# macOS dev: route all cargo invocations (including tauri dev) through the
# codesign wrapper so buzz-desktop keeps a stable Apple Development signature.
if [[ "$(uname)" == Darwin ]]; then
    BUZZ_SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    export CARGO="${BUZZ_SCRIPTS_DIR}/cargo-dev-wrapper/cargo"
    export PATH="${BUZZ_SCRIPTS_DIR}/cargo-dev-wrapper:${PATH}"
    export CARGO_TARGET_AARCH64_APPLE_DARWIN_LINKER="${BUZZ_SCRIPTS_DIR}/dev-macos-linker.sh"
    export CARGO_TARGET_X86_64_APPLE_DARWIN_LINKER="${BUZZ_SCRIPTS_DIR}/dev-macos-linker.sh"
fi

# Derive a stable base port from the worktree root so the same worktree always
# gets the same ports. This keeps the Tauri dev config stable between runs and
# preserves Cargo's build cache.
BASE_PORT=$(python3 -c "import hashlib,sys; h=int(hashlib.sha256(sys.argv[1].encode()).hexdigest(), 16); print(10000 + h % 55000)" "$WORKTREE_ROOT")
export BUZZ_VITE_PORT=$BASE_PORT
export BUZZ_HMR_PORT=$((BASE_PORT + 1))
export BUZZ_RELAY_PORT=3000
export VITE_PORT="$BUZZ_VITE_PORT"
export VITE_HMR_PORT="$BUZZ_HMR_PORT"
export BUZZ_RELAY_URL="${BUZZ_RELAY_URL:-ws://localhost:3000}"

DEV_URL="http://localhost:${BUZZ_VITE_PORT}"
if [[ "${BUZZ_RESET_WEBVIEW_STATE:-0}" == "1" ]]; then
    DEV_URL="${DEV_URL}?resetDevState=1"
fi

BUZZ_TAURI_CONFIG="{\"build\":{\"devUrl\":\"${DEV_URL}\",\"beforeDevCommand\":\"exec ../scripts/vite-before-dev.sh\"},\"identifier\":\"xyz.block.buzz.app.dev\",\"productName\":\"Buzz Dev\"}"
unset VITE_DEV_BRANCH

# In worktrees, extract a label from the branch name and derive a unique app
# identity and icon so multiple local desktop instances can run side by side.
#
# Worktree detection: compare --git-dir to --git-common-dir. In the main
# working tree these identify the same directory; in any linked worktree
# (whether under .worktrees/, .claude/worktrees/, or elsewhere) they differ.
# Normalize both paths: callers run from desktop/, where Git can otherwise
# return an absolute --git-dir but a relative --git-common-dir for the same .git.
if git rev-parse --is-inside-work-tree &>/dev/null; then
    GIT_DIR=$(git rev-parse --path-format=absolute --git-dir)
    GIT_COMMON_DIR=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
    if [[ -n "$GIT_COMMON_DIR" && "$GIT_DIR" != "$GIT_COMMON_DIR" ]]; then
        BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)
        export BUZZ_WORKTREE_LABEL="${BRANCH_NAME##*/}"
        export BUZZ_INSTANCE_SLUG=$(echo "$BRANCH_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//')

        # BUZZ_SHARE_IDENTITY=1: reuse the main dev checkout's Nostr key so
        # worktrees skip onboarding and share the same identity. The per-worktree
        # identifier is kept so concurrent instances don't collide on
        # tauri-plugin-single-instance or the app data directory.
        if [[ "${BUZZ_SHARE_IDENTITY:-0}" == "1" ]]; then
            # Prefer relay-env cache / identity.key before keychain (avoids macOS password spam).
            RELAY_ENV_SCRIPT="$WORKTREE_ROOT/scripts/relay-env.sh"
            if [[ -f "$RELAY_ENV_SCRIPT" ]]; then
                # shellcheck disable=SC1090
                source "$RELAY_ENV_SCRIPT" || true
            fi
            if [[ -z "${BUZZ_PRIVATE_KEY:-}" ]]; then
                echo "⚠ BUZZ_SHARE_IDENTITY=1 but relay-env could not resolve BUZZ_PRIVATE_KEY — run: source scripts/relay-env.sh" >&2
            fi
        fi

        ICON_DIR="$WORKTREE_ROOT/desktop/src-tauri/target/dev-icons"
        mkdir -p "$ICON_DIR"
        DEV_ICON="$ICON_DIR/icon.icns"
        GENERATE_DEV_ICON="$WORKTREE_ROOT/scripts/generate-dev-icon.swift"
        BASE_ICON="$WORKTREE_ROOT/desktop/src-tauri/icons/icon.icns"

        if swift "$GENERATE_DEV_ICON" "$BASE_ICON" "$DEV_ICON" "$BUZZ_WORKTREE_LABEL"; then
            echo "🌳 Worktree: ${BUZZ_WORKTREE_LABEL}"
            export VITE_DEV_BRANCH="$BUZZ_WORKTREE_LABEL"
            BUZZ_TAURI_CONFIG="{\"build\":{\"devUrl\":\"${DEV_URL}\",\"beforeDevCommand\":\"exec ./node_modules/.bin/vite --port ${BUZZ_VITE_PORT} --strictPort\"},\"identifier\":\"xyz.block.buzz.app.dev.${BUZZ_INSTANCE_SLUG}\",\"productName\":\"Buzz Dev (${BUZZ_WORKTREE_LABEL})\",\"bundle\":{\"icon\":[\"$DEV_ICON\"]}}"
        fi
    fi
fi

export BUZZ_TAURI_CONFIG

# Desktop dev keyring: instance-scoped service (must match Justfile desktop-standalone).
export BUZZ_DEV_KEYRING_SERVICE="${BUZZ_DEV_KEYRING_SERVICE:-buzz-desktop-dev.${BUZZ_INSTANCE_SLUG:-main}}"
export BUZZ_KEYRING_SERVICE="${BUZZ_KEYRING_SERVICE:-$BUZZ_DEV_KEYRING_SERVICE}"
