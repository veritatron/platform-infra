#!/bin/sh
# Verifies that k3s_install_script_commit and k3s_install_script_sha256 in a
# tfvars file belong to its k3s_version: the commit must be the one the release
# tag points to, and the checksum must match install.sh at that commit.
set -eu

tfvars="${1:?usage: verify-k3s-pin.sh <tfvars-file>}"
repo_url="https://github.com/k3s-io/k3s"
raw_url="https://raw.githubusercontent.com/k3s-io/k3s"

fail() {
  echo "verify-k3s: $*" >&2
  exit 1
}

value() {
  sed -n "s/^$1[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$tfvars"
}

version=$(value k3s_version)
commit=$(value k3s_install_script_commit)
sha256=$(value k3s_install_script_sha256)

[ -n "$version" ] || fail "k3s_version not found in $tfvars"
[ -n "$commit" ] || fail "k3s_install_script_commit not found in $tfvars"
[ -n "$sha256" ] || fail "k3s_install_script_sha256 not found in $tfvars"

refs=$(git ls-remote "$repo_url" "refs/tags/$version" "refs/tags/$version^{}")
tag_commit=$(printf '%s\n' "$refs" | awk '$2 ~ /\^\{\}$/ { print $1 }')
[ -n "$tag_commit" ] || tag_commit=$(printf '%s\n' "$refs" | awk 'NR == 1 { print $1 }')
[ -n "$tag_commit" ] || fail "tag $version does not exist in $repo_url"
[ "$tag_commit" = "$commit" ] ||
  fail "k3s_install_script_commit is $commit, but tag $version points to $tag_commit"

script=$(mktemp)
trap 'rm -f "$script"' EXIT
curl -sfL --retry 3 --retry-all-errors -o "$script" "$raw_url/$commit/install.sh" ||
  fail "could not download install.sh at $commit"
actual=$(sha256sum "$script" | cut -d ' ' -f 1)
[ "$actual" = "$sha256" ] ||
  fail "k3s_install_script_sha256 is $sha256, but install.sh at $commit has $actual"

echo "verify-k3s: $version, commit $commit and install.sh checksum match"
