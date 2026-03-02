#!/usr/bin/env bash

set -euo pipefail

OPENSHIFT_SCHEMA_DIR="${OPENSHIFT_SCHEMA_DIR:-v4.20-standalone-strict}"
DEFINITIONS=$(curl -sS "https://raw.githubusercontent.com/melmorabity/openshift-json-schemas/main/${OPENSHIFT_SCHEMA_DIR}/_definitions.json")

kinds=$(jq -r '.definitions | to_entries[] | select(.value["x-kubernetes-group-version-kind"] != null) | .value["x-kubernetes-group-version-kind"][]? | "\((if .group != "" then "\(.group)/" else "" end))\(.version):\(.kind)"' <<<"$DEFINITIONS")

# Output
echo "-- AUTOMATICALLY GENERATED"
echo "-- DO NOT EDIT"
echo "return {"
while read -r kind; do
  kind=$(echo "$kind" | tr '[:upper:]' '[:lower:]')
  echo "  \"$kind\","
done <<<"$kinds" | LC_ALL=C sort -u
echo "}"
