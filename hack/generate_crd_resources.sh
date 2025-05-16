#!/usr/bin/env bash

set -euo pipefail

INDEX=$(curl -sS https://raw.githubusercontent.com/datreeio/CRDs-catalog/refs/heads/main/index.yaml)

kinds=$(yq '.[].[] | "\(.apiVersion):\(.kind)"' <<<"$INDEX")

# Output
echo "-- AUTOMATICALLY GENERATED"
echo "-- DO NOT EDIT"
echo "return {"
while read -r kind; do
  echo "  \"$kind\","
done <<<"$kinds" | sort
echo "}"
