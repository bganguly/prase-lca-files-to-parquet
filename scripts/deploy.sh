#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT_DIR/data/manifest.json"
REPO="bganguly/parse-lca-files-to-parquet"
WORKFLOW="ingest_new_quarter.yml"

LAST_FY=$(python3 -c "import json; m=json.load(open('$MANIFEST')); print(m['last_fy'])")
LAST_Q=$(python3 -c "import json; m=json.load(open('$MANIFEST')); print(m['last_quarter'])")

printf '\n━━━ parse-lca-files-to-parquet · H1B LCA pipeline ━━━\n\n'
printf 'Last ingested (manifest): FY%s Q%s\n\n' "$LAST_FY" "$LAST_Q"

# ── credential discovery ──────────────────────────────────────────────────────
# Search order: env vars → ~/.aws/credentials → .env files in sibling repos
_find_cred() {
  local key="$1"
  local val=""

  # 1. already in environment
  val="${!key:-}"
  [[ -n "$val" ]] && { printf '%s' "$val"; return; }

  # 2. aws configure
  if command -v aws >/dev/null 2>&1; then
    local aws_key
    case "$key" in
      AWS_ACCESS_KEY_ID)     aws_key="aws_access_key_id" ;;
      AWS_SECRET_ACCESS_KEY) aws_key="aws_secret_access_key" ;;
      AWS_REGION|AWS_DEFAULT_REGION) aws_key="region" ;;
      *) aws_key="" ;;
    esac
    if [[ -n "$aws_key" ]]; then
      val=$(aws configure get "$aws_key" 2>/dev/null || true)
      [[ -n "$val" ]] && { printf '%s' "$val"; return; }
    fi
  fi

  # 3. .env files: current repo, then sibling repos one level up
  local search_dirs=("$ROOT_DIR" "$(dirname "$ROOT_DIR")")
  for dir in "${search_dirs[@]}"; do
    while IFS= read -r -d '' envfile; do
      local found
      found=$(grep -m1 "^${key}=" "$envfile" 2>/dev/null | cut -d= -f2- || true)
      [[ -n "$found" ]] && { printf '%s' "$found"; return; }
    done < <(find "$dir" -maxdepth 3 -name ".env" -print0 2>/dev/null)
  done

  true
}

_mask() { local v="$1"; [[ -z "$v" ]] && echo "(not set)" || echo "${v:0:8}...${v: -4}"; }

_prompt_cred() {
  local label="$1" current="$2"
  local ans val
  if [[ -n "$current" ]]; then
    printf '  %-24s  %s  - use this? [Y/n]: ' "$label" "$(_mask "$current")" >&2
    read -r ans; ans="${ans:-Y}"
    if [[ "$ans" =~ ^[Yy] ]]; then
      printf '%s' "$current"
    else
      printf '  New value: ' >&2; read -rs val; printf '\n' >&2
      printf '%s' "$val"
    fi
  else
    printf '  %-24s  (not found) - enter value: ' "$label" >&2
    read -rs val; printf '\n' >&2
    printf '%s' "$val"
  fi
}

# ── gather credentials ────────────────────────────────────────────────────────
printf '%s\n' '=== AWS / GitHub Secrets setup ==='
printf '%s\n\n' 'Scanning for existing credentials (env, aws configure, .env files)...'

FOUND_KEY_ID=$(_find_cred AWS_ACCESS_KEY_ID)
FOUND_SECRET=$(_find_cred AWS_SECRET_ACCESS_KEY)
FOUND_REGION=$(_find_cred AWS_REGION)
[[ -z "$FOUND_REGION" ]] && FOUND_REGION=$(_find_cred AWS_DEFAULT_REGION)
[[ -z "$FOUND_REGION" ]] && FOUND_REGION="us-east-1"

AWS_ACCESS_KEY_ID=$(_prompt_cred     "AWS_ACCESS_KEY_ID"     "$FOUND_KEY_ID")
AWS_SECRET_ACCESS_KEY=$(_prompt_cred "AWS_SECRET_ACCESS_KEY" "$FOUND_SECRET")
AWS_REGION=$(_prompt_cred            "AWS_REGION"            "$FOUND_REGION")

# S3_BUCKET: look in .env files or use hardcoded known value
FOUND_BUCKET=$(_find_cred S3_BUCKET)
[[ -z "$FOUND_BUCKET" ]] && FOUND_BUCKET="h1b-nlq-parquet-577479071532-20260511"
S3_BUCKET=$(_prompt_cred "S3_BUCKET" "$FOUND_BUCKET")

printf '\n'

[[ -z "$AWS_ACCESS_KEY_ID" || -z "$AWS_SECRET_ACCESS_KEY" || -z "$S3_BUCKET" ]] && {
  printf 'Missing required credentials — aborting.\n'; exit 1
}

# ── push secrets to GitHub ────────────────────────────────────────────────────
printf '=== Pushing secrets to GitHub repo: %s ===\n' "$REPO"
printf '%s' "$AWS_ACCESS_KEY_ID"     | gh secret set AWS_ACCESS_KEY_ID     --repo "$REPO"
printf '%s' "$AWS_SECRET_ACCESS_KEY" | gh secret set AWS_SECRET_ACCESS_KEY --repo "$REPO"
printf '%s' "$AWS_REGION"            | gh secret set AWS_REGION            --repo "$REPO"
printf '%s' "$S3_BUCKET"             | gh secret set S3_BUCKET             --repo "$REPO"
printf 'Secrets set.\n\n'

# ── trigger workflow ──────────────────────────────────────────────────────────
printf '%s\n' '=== Triggering GitHub Actions workflow ==='
printf '%s\n\n' 'All heavy processing runs on the GitHub runner - this machine is not involved.'

gh workflow run "$WORKFLOW" --repo "$REPO"

sleep 4
RUN_ID=$(gh run list --repo "$REPO" --workflow "$WORKFLOW" --limit 1 --json databaseId -q '.[0].databaseId')
RUN_URL="https://github.com/$REPO/actions/runs/$RUN_ID"
printf 'Workflow triggered: %s\n' "$RUN_URL"

read -rp $'\nWatch the run? [y/N]: ' _watch
if [[ "${_watch,,}" == "y" ]]; then
  gh run watch "$RUN_ID" --repo "$REPO"
fi
