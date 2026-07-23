#!/usr/bin/env bash
set -euo pipefail

readonly DEFAULT_COMPONENTS="grch38,star,pathseq-host,t2t,kraken"
readonly GRCH38_URL="https://api.gdc.cancer.gov/data/254f697d-310d-4d7d-a27b-27fbf767a834"
readonly GRCH38_MD5="3ffbcfe2d05d43206f57f81ebb251dc9"
readonly GTF_URL="https://api.gdc.cancer.gov/data/be002a2c-3b27-43f3-9e0f-fd47db92a6b5"
readonly GTF_MD5="c03931958d4572148650d62eb6dec41a"
readonly KRAKEN_URL="https://genome-idx.s3.amazonaws.com/kraken/k2_pluspf_20240605.tar.gz"
readonly KRAKEN_BYTES="68463709535"
readonly PATHSEQ_HOST_URL="ftp://gsapubftp-anonymous@ftp.broadinstitute.org/bundle/pathseq/pathseq_host.tar.gz"
readonly PATHSEQ_HOST_BYTES="12819731715"
readonly T2T_URL="https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/009/914/755/GCF_009914755.1_T2T-CHM13v2.0/GCF_009914755.1_T2T-CHM13v2.0_genomic.fna.gz"
readonly T2T_MD5="9e6bf6b586bc8954208d1cc1d5f2fc99"

db_root="${PST2T_DB_ROOT:-}"
threads=16
components="${DEFAULT_COMPONENTS}"

usage() {
  cat <<'EOF'
Usage:
  prepare_references.sh --db-root DIR [--threads N] [--components LIST]

Options:
  --db-root DIR       External reference database root. May alternatively be
                      supplied through PST2T_DB_ROOT.
  --threads N         Threads used for BWA and STAR index generation (default: 16).
  --components LIST   Comma-separated components (default:
                      grch38,star,pathseq-host,t2t,kraken).
  -h, --help          Show this help.

Components:
  grch38, star, pathseq-host, t2t, kraken
EOF
}

while (($#)); do
  case "$1" in
    --db-root)
      db_root="${2:?--db-root requires a directory}"
      shift 2
      ;;
    --threads)
      threads="${2:?--threads requires a positive integer}"
      shift 2
      ;;
    --components)
      components="${2:?--components requires a comma-separated list}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "${db_root}" ]]; then
  echo "ERROR: supply --db-root DIR or set PST2T_DB_ROOT." >&2
  usage >&2
  exit 2
fi
if [[ ! "${threads}" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: --threads must be a positive integer." >&2
  exit 2
fi

for command_name in curl tar gzip awk df; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: ${command_name}" >&2
    exit 1
  }
done

mkdir -p "${db_root}"
db_root="$(cd "${db_root}" && pwd -P)"

want_component() {
  local requested="$1"
  local item
  IFS=',' read -r -a selected_components <<<"${components}"
  for item in "${selected_components[@]}"; do
    item="${item//[[:space:]]/}"
    [[ "${item}" == "${requested}" ]] && return 0
  done
  return 1
}

IFS=',' read -r -a selected_components <<<"${components}"
for item in "${selected_components[@]}"; do
  item="${item//[[:space:]]/}"
  case "${item}" in
    grch38|star|pathseq-host|t2t|kraken) ;;
    *)
      echo "ERROR: unsupported component: ${item}" >&2
      exit 2
      ;;
  esac
done

file_size() {
  if stat -c '%s' "$1" >/dev/null 2>&1; then
    stat -c '%s' "$1"
  else
    stat -f '%z' "$1"
  fi
}

md5_value() {
  if command -v md5sum >/dev/null 2>&1; then
    md5sum "$1" | awk '{print $1}'
  elif command -v md5 >/dev/null 2>&1; then
    md5 -q "$1"
  else
    echo "ERROR: md5sum or md5 is required for checksum verification." >&2
    exit 1
  fi
}

verify_md5() {
  local file="$1"
  local expected="$2"
  local observed
  observed="$(md5_value "${file}")"
  [[ "${observed}" == "${expected}" ]] || {
    echo "ERROR: checksum mismatch for ${file}" >&2
    echo "Expected: ${expected}" >&2
    echo "Observed: ${observed}" >&2
    exit 1
  }
}

verify_size() {
  local file="$1"
  local expected="$2"
  local observed
  observed="$(file_size "${file}")"
  [[ "${observed}" == "${expected}" ]] || {
    echo "ERROR: size mismatch for ${file}" >&2
    echo "Expected: ${expected} bytes" >&2
    echo "Observed: ${observed} bytes" >&2
    exit 1
  }
}

download() {
  local url="$1"
  local output="$2"
  if [[ -s "${output}" ]]; then
    echo "Using existing download: ${output}"
    return 0
  fi
  local partial="${output}.partial"
  echo "Downloading: ${url}"
  curl --fail --location --retry 5 --retry-delay 5 \
    --continue-at - --output "${partial}" "${url}"
  mv "${partial}" "${output}"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: activate the pathseq-t2t-nextflow environment; missing: $1" >&2
    exit 1
  }
}

available_kb="$(df -Pk "${db_root}" | awk 'NR == 2 {print $4}')"
echo "Database root: ${db_root}"
echo "Available space: $((available_kb / 1024 / 1024)) GiB"
echo "Components: ${components}"

grch38_dir="${db_root}/GRCh38"
grch38_fasta="${grch38_dir}/GRCh38.d1.vd1.fa"
star_dir="${grch38_dir}/STAR_GRCh38.d1.vd1.gencode.v36.sjdbOverhang100"
pathseq_host_dir="${db_root}/PathSeq_host"
t2t_dir="${db_root}/T2T-CHM13v2.0"
t2t_fasta="${t2t_dir}/GCF_009914755.1_T2T-CHM13v2.0_genomic.fna"
kraken_dir="${db_root}/Kraken2_PlusPF_20240605"

if want_component grch38 || want_component star; then
  require_command bwa
  mkdir -p "${grch38_dir}"
  grch38_archive="${grch38_dir}/GRCH38_fa.tar.gz"
  download "${GRCH38_URL}" "${grch38_archive}"
  verify_md5 "${grch38_archive}" "${GRCH38_MD5}"
  tar -tzf "${grch38_archive}" >/dev/null
  if [[ ! -s "${grch38_fasta}" ]]; then
    tar -xzf "${grch38_archive}" -C "${grch38_dir}"
  fi
  [[ -s "${grch38_fasta}" ]] || {
    echo "ERROR: GRCh38 FASTA was not extracted as expected." >&2
    exit 1
  }
  if [[ ! -s "${grch38_fasta}.bwt" ]]; then
    bwa index "${grch38_fasta}"
  fi
fi

if want_component star; then
  require_command STAR
  gtf_gz="${grch38_dir}/gencode.v36.annotation.gtf.gz"
  gtf="${grch38_dir}/gencode.v36.annotation.gtf"
  download "${GTF_URL}" "${gtf_gz}"
  verify_md5 "${gtf_gz}" "${GTF_MD5}"
  if [[ ! -s "${gtf}" ]]; then
    gzip -dc "${gtf_gz}" >"${gtf}.partial"
    mv "${gtf}.partial" "${gtf}"
  fi
  if [[ ! -s "${star_dir}/Genome" ]]; then
    if [[ -e "${star_dir}" ]]; then
      echo "ERROR: incomplete STAR index directory exists: ${star_dir}" >&2
      echo "Move it aside and rerun reference preparation." >&2
      exit 1
    fi
    star_build_dir="$(mktemp -d "${grch38_dir}/.star-index-build.XXXXXX")"
    STAR --runThreadN "${threads}" \
      --runMode genomeGenerate \
      --genomeDir "${star_build_dir}" \
      --genomeFastaFiles "${grch38_fasta}" \
      --sjdbGTFfile "${gtf}" \
      --sjdbOverhang 100
    [[ -s "${star_build_dir}/Genome" ]] || {
      echo "ERROR: STAR index generation did not produce Genome." >&2
      exit 1
    }
    mv "${star_build_dir}" "${star_dir}"
  fi
fi

if want_component pathseq-host; then
  mkdir -p "${pathseq_host_dir}"
  pathseq_archive="${pathseq_host_dir}/pathseq_host.tar.gz"
  download "${PATHSEQ_HOST_URL}" "${pathseq_archive}"
  verify_size "${pathseq_archive}" "${PATHSEQ_HOST_BYTES}"
  tar -tzf "${pathseq_archive}" >/dev/null
  if [[ ! -s "${pathseq_host_dir}/pathseq_host.bfi" ||
        ! -s "${pathseq_host_dir}/pathseq_host.fa.img" ]]; then
    tar -xzf "${pathseq_archive}" -C "${pathseq_host_dir}"
  fi
  for required_file in pathseq_host.bfi pathseq_host.fa pathseq_host.fa.img; do
    [[ -s "${pathseq_host_dir}/${required_file}" ]] || {
      echo "ERROR: missing PathSeq host resource: ${required_file}" >&2
      exit 1
    }
  done
fi

if want_component t2t; then
  require_command bwa
  mkdir -p "${t2t_dir}"
  t2t_gz="${t2t_fasta}.gz"
  download "${T2T_URL}" "${t2t_gz}"
  verify_md5 "${t2t_gz}" "${T2T_MD5}"
  if [[ ! -s "${t2t_fasta}" ]]; then
    gzip -dc "${t2t_gz}" >"${t2t_fasta}.partial"
    mv "${t2t_fasta}.partial" "${t2t_fasta}"
  fi
  if [[ ! -s "${t2t_fasta}.bwt" ]]; then
    bwa index "${t2t_fasta}"
  fi
fi

if want_component kraken; then
  mkdir -p "${kraken_dir}"
  kraken_archive="${kraken_dir}/k2_pluspf_20240605.tar.gz"
  download "${KRAKEN_URL}" "${kraken_archive}"
  verify_size "${kraken_archive}" "${KRAKEN_BYTES}"
  tar -tzf "${kraken_archive}" >/dev/null
  if [[ ! -s "${kraken_dir}/hash.k2d" ||
        ! -s "${kraken_dir}/opts.k2d" ||
        ! -s "${kraken_dir}/taxo.k2d" ]]; then
    tar -xzf "${kraken_archive}" -C "${kraken_dir}"
  fi
  for required_file in hash.k2d opts.k2d taxo.k2d; do
    [[ -s "${kraken_dir}/${required_file}" ]] || {
      echo "ERROR: missing Kraken2 database file: ${required_file}" >&2
      exit 1
    }
  done
fi

picard_jar=""
if [[ -n "${CONDA_PREFIX:-}" && -d "${CONDA_PREFIX}/share" ]]; then
  picard_jar="$(find "${CONDA_PREFIX}/share" -type f -name picard.jar -print -quit)"
fi
if [[ -z "${picard_jar}" ]]; then
  echo "WARNING: picard.jar was not found below the active Conda environment." >&2
  echo "Activate pathseq-t2t-nextflow and rerun to populate tools.picard_jar." >&2
fi

parameter_template="${db_root}/pathseq-t2t-nextflow.references.yaml"
cat >"${parameter_template}" <<EOF
tools:
  picard_jar: ${picard_jar}

references:
  grch38_fasta: ${grch38_fasta}
  star_index: ${star_dir}
  hostdir: ${pathseq_host_dir}
  t2tref: ${t2t_fasta}
  kraken_index: ${kraken_dir}
  decoys_to_mask: None
EOF

echo
echo "Reference preparation complete."
echo "Parameter template: ${parameter_template}"
