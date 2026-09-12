#!/usr/bin/env bash
# Cross-platform wrapper for the worktrunk CLI.
# If WORKTRUNK_BIN is set, uses that path exclusively.
# Otherwise, on Windows (MSYS/Cygwin), prefers git-wt.exe over wt and
# rejects wt if it resolves to Windows Terminal (.../WindowsApps/wt.exe).
# On other platforms, uses wt directly.
# Usage: wt.sh [args...]

# Clear WT before the branches below: on Windows they leave it unset when
# neither git-wt.exe nor wt is on PATH, and a hook is handed the caller's whole
# environment -- so an inherited WT would be what the final check accepts and
# runs, Windows Terminal included.
WT=""

if [[ -n "$WORKTRUNK_BIN" ]]; then
    if ! command -v "$WORKTRUNK_BIN" >/dev/null 2>&1; then
        echo "worktrunk: WORKTRUNK_BIN is set to '$WORKTRUNK_BIN' but it was not found" >&2
        exit 1
    fi
    WT="$WORKTRUNK_BIN"
elif [[ "$(uname -o 2>/dev/null)" =~ ^(Msys|Cygwin)$ ]]; then
    # check for bash on Windows (on Windows, Claude Code defaults to Git Bash)
    if command -v git-wt.exe >/dev/null 2>&1; then
        # prefer git-wt over wt if available
        WT=git-wt.exe
    elif command -v wt >/dev/null 2>&1; then
        # reject wt if it's the Windows Terminal alias
        if [[ "$(command -v wt)" == *WindowsApps* ]]; then
            echo "worktrunk: 'wt' resolves to Windows Terminal; install worktrunk as git-wt.exe or remove the Windows Terminal alias. See https://worktrunk.dev/worktrunk/#install" >&2
            exit 1
        fi

        WT=wt
    fi
else
    # non-Windows, always use wt
    WT=wt
fi

if [[ -z "$WT" ]] || ! command -v "$WT" >/dev/null 2>&1; then
    echo "worktrunk: could not find 'wt' in PATH" >&2
    exit 1
fi

# Codex hook stdin carries `cwd` (the session directory). Pin `-C` to that
# path so a `cd` mid-session cannot retarget the marker (#3921). Missing or
# empty `cwd` exits 0 without calling wt — falling through to the process
# cwd is the bug. jq handles escaped paths; sed covers Git Bash on Windows
# when jq is not installed.
if [[ "${1:-}" == "--stdin-cwd" ]]; then
    shift
    payload=$(cat)
    p=""
    if command -v jq >/dev/null 2>&1; then
        p=$(printf '%s' "$payload" | jq -er '.cwd // empty') || p=""
    fi
    if [[ -z "$p" ]]; then
        p=$(printf '%s' "$payload" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    fi
    [[ -n "$p" ]] || exit 0
    exec "$WT" -C "$p" "$@"
fi

"$WT" "$@"
