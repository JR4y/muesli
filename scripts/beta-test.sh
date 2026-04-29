#!/usr/bin/env bash
set -euo pipefail

# Builds and launches the fork's daily-use beta app.
#
# - Installs as /Applications/MuesliBeta.app
# - Uses bundle ID com.jr4y.muesli.beta
# - Stores data in ~/Library/Application Support/MuesliBeta/
# - Disables Sparkle feed lookup so local beta builds do not follow upstream
#   production or preprod appcasts
#
# Usage:
#   ./scripts/beta-test.sh         # Build and launch
#   ./scripts/beta-test.sh --reset # Reset onboarding only (keep data)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BETA_SUPPORT_DIR="$HOME/Library/Application Support/MuesliBeta"
BETA_APP="/Applications/MuesliBeta.app"
ONBOARDING_PROGRESS_FILE="$BETA_SUPPORT_DIR/onboarding-progress.json"

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

echo "Building MuesliBeta (debug, signed when identity is available)..."
MUESLI_APP_NAME=MuesliBeta \
MUESLI_BUNDLE_ID=com.jr4y.muesli.beta \
MUESLI_SUPPORT_DIR_NAME=MuesliBeta \
MUESLI_DISPLAY_NAME="Muesli Beta" \
MUESLI_EXECUTABLE_NAME=MuesliBeta \
MUESLI_SPARKLE_FEED_URL="" \
"$ROOT/scripts/build_native_app.sh" debug

echo ""
echo "Launching MuesliBeta..."
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
echo "  pkill -f MuesliBeta             # Kill beta app"
