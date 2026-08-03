#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
t2tfilter="${repo_root}/overrides/t2tfilter.sh"
io_override="${repo_root}/overrides/io.sh"
setup_script="${repo_root}/scripts/setup_pathseq_t2t.sh"

if rg -n -F -- '-U >(' "${t2tfilter}"; then
  echo "ERROR: t2tfilter still contains an asynchronous -U process substitution." >&2
  exit 1
fi

if rg -n 'samtools flagstat.*[|][|][[:space:]]*true' "${t2tfilter}"; then
  echo "ERROR: t2tfilter still suppresses a flagstat failure." >&2
  exit 1
fi

rg -q 'samtools view -c' "${io_override}"
rg -q 'overrides/io.sh' "${setup_script}"
rg -q 'RUNTIME_DIR}/lib/io.sh' "${setup_script}"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT
touch "${tmpdir}/test.bam"

mkdir -p "${tmpdir}/bin"
cat > "${tmpdir}/bin/samtools" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  quickcheck)
    exit 0
    ;;
  view)
    [[ "${FAKE_FULL_READ_RESULT:-success}" == success ]]
    ;;
  *)
    exit 2
    ;;
esac
EOF
chmod +x "${tmpdir}/bin/samtools"

PATH="${tmpdir}/bin:${PATH}"
log() { :; }
die() {
  echo "$*" >&2
  exit 1
}
source "${io_override}"

export FAKE_FULL_READ_RESULT=success
bam_check_or_die "${tmpdir}/test.bam" "test success"

export FAKE_FULL_READ_RESULT=failure
if (bam_check_or_die "${tmpdir}/test.bam" "test corruption"); then
  echo "ERROR: full-read corruption was accepted." >&2
  exit 1
fi

echo "BAM integrity contract tests passed."
