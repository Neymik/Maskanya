#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
[ -f .env ] && source .env
yc serverless function delete --name "${FUNCTION_NAME:-image-thumbnailer-v2}" --folder-id "${FOLDER_ID}"
