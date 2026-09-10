#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT_DIR/data/manifest.json"
REPO="bganguly/parse-lca-files-to-parquet"
WORKFLOW="ingest_new_quarter.yml"

LAST_FY=$(python3 -c "import json; m=json.load(open('$MANIFEST')); print(m['last_fy'])")
LAST_Q=$(python3 -c "import json; m=json.load(open('$MANIFEST')); print(m['last_quarter'])")

printf '\n━━━ parse-lca-files-to-parquet · H1B LCA pipeline ━━━\n\n'
printf 'Last ingested locally: FY%s Q%s\n' "$LAST_FY" "$LAST_Q"
printf 'Triggering GitHub Actions to check for and ingest new DOL quarters.\n'
printf 'All heavy processing runs on the GitHub runner — this machine is not involved.\n\n'

gh workflow run "$WORKFLOW" --repo "$REPO"

sleep 4
RUN_ID=$(gh run list --repo "$REPO" --workflow "$WORKFLOW" --limit 1 --json databaseId -q '.[0].databaseId')
RUN_URL="https://github.com/$REPO/actions/runs/$RUN_ID"
printf 'Workflow triggered: %s\n' "$RUN_URL"

read -rp $'\nWatch the run? [y/N]: ' _watch
if [[ "${_watch,,}" == "y" ]]; then
    gh run watch "$RUN_ID" --repo "$REPO"
fi
