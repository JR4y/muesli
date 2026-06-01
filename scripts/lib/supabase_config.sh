#!/usr/bin/env bash

muesli_load_supabase_config() {
  local config_file="$1"
  local out_url_var="$2"
  local out_anon_var="$3"
  local parsed_url=""
  local parsed_anon=""

  printf -v "$out_url_var" '%s' ""
  printf -v "$out_anon_var" '%s' ""

  [[ -f "$config_file" ]] || return 0

  while IFS='=' read -r key value; do
    case "$key" in
      MUESLI_SUPABASE_URL) parsed_url="$value" ;;
      MUESLI_SUPABASE_ANON_KEY) parsed_anon="$value" ;;
    esac
  done < <(grep -E '^[A-Z_]+=' "$config_file" || true)

  printf -v "$out_url_var" '%s' "$parsed_url"
  printf -v "$out_anon_var" '%s' "$parsed_anon"
}

muesli_has_supabase_sync_config() {
  local config_file="$1"
  local url=""
  local anon=""

  muesli_load_supabase_config "$config_file" url anon
  [[ -n "$url" && -n "$anon" ]]
}
