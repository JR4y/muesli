#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib/supabase_config.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

configured_file="$tmpdir/Supabase.xcconfig"
cat > "$configured_file" <<'EOF'
MUESLI_SUPABASE_URL=https://example.supabase.co
MUESLI_SUPABASE_ANON_KEY=sb_publishable_example
EOF

missing_key_file="$tmpdir/Supabase-missing-key.xcconfig"
cat > "$missing_key_file" <<'EOF'
MUESLI_SUPABASE_URL=https://example.supabase.co
EOF

empty_values_file="$tmpdir/Supabase-empty-values.xcconfig"
cat > "$empty_values_file" <<'EOF'
MUESLI_SUPABASE_URL=
MUESLI_SUPABASE_ANON_KEY=
EOF

url=""
anon=""
muesli_load_supabase_config "$configured_file" url anon
[[ "$url" == "https://example.supabase.co" ]]
[[ "$anon" == "sb_publishable_example" ]]
[[ "$(muesli_has_supabase_sync_config "$configured_file" && echo yes || echo no)" == "yes" ]]
[[ "$(muesli_has_supabase_sync_config "$missing_key_file" && echo yes || echo no)" == "no" ]]
[[ "$(muesli_has_supabase_sync_config "$empty_values_file" && echo yes || echo no)" == "no" ]]

echo "supabase config helper tests passed"
