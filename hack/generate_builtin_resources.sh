#!/usr/bin/env bash

set -euo pipefail

DEFINITIONS_URL_BASE="https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master"
DEFINITIONS_URL_SUFFIX="/_definitions.json"
GH_TREE_URL="https://api.github.com/repos/yannh/kubernetes-json-schema/git/trees/master"

# Get the GitHub tree
gh_tree_content=$(curl -s "$GH_TREE_URL")
if [[ -z "$gh_tree_content" ]]; then
  echo "Can't GET GH tree" >&2
  exit 1
fi

# Extract unique versions (vX.Y.Z) and keep only the last 10
versions=($(echo "$gh_tree_content" | jq -r '.tree[].path' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 10))

declare -A kinds

for version in "${versions[@]}"; do
  url="${DEFINITIONS_URL_BASE}/${version}${DEFINITIONS_URL_SUFFIX}"
  content=$(curl -s "$url")
  if [[ -z "$content" ]]; then
    echo "Can't GET $url" >&2
    exit 1
  fi

  # Extract all kinds from x-kubernetes-group-version-kind
  mapfile -t found_kinds < <(echo "$content" | jq -r '
    .definitions // {} |
    to_entries[] |
    select(.value["x-kubernetes-group-version-kind"] != null) |
    .value["x-kubernetes-group-version-kind"][]?.kind
  ')

  for kind in "${found_kinds[@]}"; do
    kinds["$kind"]=1
  done

  sleep 1
done

# Output
echo "-- AUTOMATICALLY GENERATED"
echo "-- DO NOT EDIT"
echo "return {"
for kind in "${!kinds[@]}"; do
  echo "  \"$kind\","
done | sort
echo "}"
