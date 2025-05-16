#!/usr/bin/env bash

set -euo pipefail

DEFINITIONS=$(curl -sS https://raw.githubusercontent.com/yannh/kubernetes-json-schema/refs/heads/master/master-standalone-strict/_definitions.json)

kinds=$(jq -r '.definitions | to_entries[] | select(.value["x-kubernetes-group-version-kind"] != null) | .value["x-kubernetes-group-version-kind"][]? | "\((if .group != "" then "\(.group)/" else "" end))\(.version):\(.kind)"' <<<"$DEFINITIONS")

# Output
echo "-- AUTOMATICALLY GENERATED"
echo "-- DO NOT EDIT"
echo "return {"
while read -r kind; do
  echo "  \"$kind\","
done <<<"$kinds" | LC_ALL=C sort -u
echo "}"
