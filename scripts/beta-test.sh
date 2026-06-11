#!/usr/bin/env bash
set -euo pipefail

# Builds and launches the fork's daily-use beta app.
#
# - Installs as /Applications/muesli-beta.app
# - Uses bundle ID com.jr4y.muesli.beta
# - Stores data in ~/Library/Application Support/MuesliBeta/
# - Disables Sparkle feed lookup so local beta builds do not follow upstream
#   production or preprod appcasts
# - Requires a stable codesign identity by default so macOS privacy
#   permissions stay attached across beta reinstalls. Set MUESLI_SKIP_SIGN=1
#   only when you intentionally want an unsigned local install.
#
# Usage:
#   ./scripts/beta-test.sh         # Build and launch
#   ./scripts/beta-test.sh --reset # Reset onboarding only (keep data)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib/supabase_config.sh"
BETA_SUPPORT_DIR="$HOME/Library/Application Support/MuesliBeta"
BETA_APP="/Applications/muesli-beta.app"
LEGACY_BETA_APP="/Applications/MuesliBeta.app"
ONBOARDING_PROGRESS_FILE="$BETA_SUPPORT_DIR/onboarding-progress.json"
SUPABASE_CONFIG_FILE="${MUESLI_SUPABASE_CONFIG_FILE:-$ROOT/config/Supabase.xcconfig}"
DEFAULT_DEVELOPER_ID="Developer ID Application: Pranav Hari Guruvayurappan (58W55QJ567)"

find_codesign_identity() {
  local preferred_identity="${1:-}"
  local identities
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"

  if [[ -n "$preferred_identity" ]] && grep -Fq "$preferred_identity" <<<"$identities"; then
    printf '%s\n' "$preferred_identity"
    return 0
  fi

  if grep -Fq "$DEFAULT_DEVELOPER_ID" <<<"$identities"; then
    printf '%s\n' "$DEFAULT_DEVELOPER_ID"
    return 0
  fi

  sed -n 's/.*"\(Apple Development: .*\)".*/\1/p' <<<"$identities" | head -n 1
}

if ! muesli_has_supabase_sync_config "$SUPABASE_CONFIG_FILE" && [[ "$ROOT" == */.worktrees/* ]]; then
  PRIMARY_WORKTREE_ROOT="${ROOT%%/.worktrees/*}"
  PRIMARY_SUPABASE_CONFIG_FILE="$PRIMARY_WORKTREE_ROOT/config/Supabase.xcconfig"
  if muesli_has_supabase_sync_config "$PRIMARY_SUPABASE_CONFIG_FILE"; then
    SUPABASE_CONFIG_FILE="$PRIMARY_SUPABASE_CONFIG_FILE"
    export MUESLI_SUPABASE_CONFIG_FILE="$SUPABASE_CONFIG_FILE"
    echo "Using Supabase config from primary worktree: $SUPABASE_CONFIG_FILE"
  fi
fi

RESET=0
for arg in "$@"; do
  case "$arg" in
    --reset) RESET=1 ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

if [[ "${MUESLI_SKIP_SIGN:-0}" != "1" ]]; then
  SIGN_IDENTITY="$(find_codesign_identity "${MUESLI_SIGN_IDENTITY:-}")"
  if [[ -n "$SIGN_IDENTITY" ]]; then
    export MUESLI_SIGN_IDENTITY="$SIGN_IDENTITY"
    echo "Using codesign identity: $SIGN_IDENTITY"
  else
    echo "muesli-beta requires a valid codesign identity to preserve macOS privacy permissions." >&2
    echo "No Developer ID or Apple Development identity is visible to security find-identity." >&2
    echo "If you intentionally want to replace the app with an unsigned build, rerun with MUESLI_SKIP_SIGN=1." >&2
    exit 1
  fi
fi

if [[ "${MUESLI_REQUIRE_SUPABASE_CONFIG:-1}" == "1" ]] && ! muesli_has_supabase_sync_config "$SUPABASE_CONFIG_FILE"; then
  echo "muesli-beta requires config/Supabase.xcconfig with MUESLI_SUPABASE_URL and MUESLI_SUPABASE_ANON_KEY." >&2
  echo "Set MUESLI_REQUIRE_SUPABASE_CONFIG=0 if you intentionally want a beta build with sync disabled." >&2
  exit 1
fi

pkill -f "muesli-beta.app" 2>/dev/null || true
pkill -f "MuesliBeta.app" 2>/dev/null || true
sleep 0.5

if [[ "$RESET" -eq 1 ]] && [[ -f "$BETA_SUPPORT_DIR/config.json" ]]; then
  echo "Resetting onboarding flag..."
  python3 -c "
import json, os, pathlib
p = pathlib.Path('$BETA_SUPPORT_DIR/config.json')
c = json.loads(p.read_text())
c['has_completed_onboarding'] = False
mode = p.stat().st_mode & 0o777
p.write_text(json.dumps(c, indent=2) + '\n')
os.chmod(p, mode)
progress = pathlib.Path('$ONBOARDING_PROGRESS_FILE')
if progress.exists():
    progress.unlink()
    print('  Cleared transient onboarding progress')
print('  Onboarding reset (data preserved)')
"
fi

echo "Building muesli-beta (debug, signed unless explicitly skipped)..."
MUESLI_APP_NAME=muesli-beta \
MUESLI_BUNDLE_ID=com.jr4y.muesli.beta \
MUESLI_SUPPORT_DIR_NAME=MuesliBeta \
MUESLI_DISPLAY_NAME="muesli-beta" \
MUESLI_EXECUTABLE_NAME=muesli-beta \
MUESLI_APP_BUNDLE_NAME=muesli-beta.app \
MUESLI_SPARKLE_FEED_URL="" \
MUESLI_SUPABASE_CONFIG_FILE="$SUPABASE_CONFIG_FILE" \
"$ROOT/scripts/build_native_app.sh" debug

if [[ -d "$LEGACY_BETA_APP" ]]; then
  echo "Removing legacy beta bundle: $LEGACY_BETA_APP"
  rm -rf "$LEGACY_BETA_APP"
fi

echo ""
echo "Launching muesli-beta..."
open "$BETA_APP"

echo ""
echo "=== Beta Test Ready ==="
echo "  App: $BETA_APP"
echo "  Data: $BETA_SUPPORT_DIR"
echo "  DB: $BETA_SUPPORT_DIR/muesli.db"
echo "  Sparkle feed: disabled for local beta builds"
echo ""
echo "Tips:"
echo "  ./scripts/beta-test.sh --reset  # Re-run onboarding (keep data)"
echo "  pkill -f muesli-beta           # Kill beta app"
