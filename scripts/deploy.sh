#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"

REGION="${REGION:-us-east-1}"
VERSION_TAG="${VERSION_TAG:-}"

printf '\n━━━ parse-lca-files-to-parquet · H1B LCA pipeline ━━━\n\n'
printf 'Fetches official LCA datasets, converts to Parquet, and uploads to S3.\n\n'

read -rp "AWS region [$REGION]: " _r && REGION="${_r:-$REGION}"

exec "$SCRIPTS_DIR/infra-up.sh" "" "$REGION" "$VERSION_TAG"
