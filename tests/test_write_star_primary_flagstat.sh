#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${repo_root}/scripts/write_star_primary_flagstat.sh"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

write_log() {
  local path="$1"
  local reads="$2"
  printf '                          Number of input reads | %s\n' "$reads" > "$path"
}

assert_primary_reads() {
  local expected="$1"
  local output="$2"
  local observed
  observed="$(awk -F '\t' 'NR == 1 { print $1 }' "$output")"
  [[ "$observed" == "$expected" ]] || {
    echo "ERROR: Expected $expected primary reads, observed $observed in $output" >&2
    exit 1
  }
}

write_log "${test_dir}/paired.log" 10
write_log "${test_dir}/single.log" 3

"$script" \
  --paired-log "${test_dir}/paired.log" \
  --output "${test_dir}/paired.tsv"
assert_primary_reads 20 "${test_dir}/paired.tsv"

"$script" \
  --single-log "${test_dir}/single.log" \
  --output "${test_dir}/single.tsv"
assert_primary_reads 3 "${test_dir}/single.tsv"

"$script" \
  --paired-log "${test_dir}/paired.log" \
  --single-log "${test_dir}/single.log" \
  --output "${test_dir}/mixed.tsv"
assert_primary_reads 23 "${test_dir}/mixed.tsv"

"$script" \
  --star-log "${test_dir}/paired.log" \
  --output "${test_dir}/legacy.tsv"
assert_primary_reads 20 "${test_dir}/legacy.tsv"

if "$script" --output "${test_dir}/missing.tsv" >/dev/null 2>&1; then
  echo "ERROR: Expected invocation without STAR logs to fail" >&2
  exit 1
fi

printf 'malformed\n' > "${test_dir}/malformed.log"
if "$script" \
  --single-log "${test_dir}/malformed.log" \
  --output "${test_dir}/malformed.tsv" >/dev/null 2>&1; then
  echo "ERROR: Expected malformed STAR log to fail" >&2
  exit 1
fi

echo "write_star_primary_flagstat tests passed."
