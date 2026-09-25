#!/bin/bash
# Exercise avatar style/privacy selection and actual PNG conversion without a
# relay account or generated model output. UI generation is verified separately.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/vibes-avatar-check.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
xcrun swiftc -parse-as-library \
  "$repo_root/client/Vibes/AvatarGenerator.swift" \
  "$repo_root/client/Tests/AvatarGeneratorChecks.swift" \
  -o "$check_dir/avatar-check"
"$check_dir/avatar-check"
