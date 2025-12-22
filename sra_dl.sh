#!/usr/bin/env bash
# Usage: ./sra_dl.sh <SRA_RUN_ID>
#
# Example:
#   ./sra_dl.sh SRR12345678

set -euo pipefail

############################
# CONFIG
############################

SRA_ID="$1"
THREADS=8

# optional: where SRA files go
SRA_DIR="${SRA_ID}/sra"
FASTQ_DIR="${SRA_ID}/fastq"

############################
# CHECKS
############################

if [[ -z "${SRA_ID}" ]]; then
  echo "ERROR: No SRA accession provided"
  exit 1
fi

command -v prefetch >/dev/null || { echo "prefetch not found"; exit 1; }
command -v fasterq-dump >/dev/null || { echo "fasterq-dump not found"; exit 1; }
command -v repair.sh >/dev/null || { echo "repair.sh (BBTools) not found"; exit 1; }

############################
# SETUP
############################

mkdir -p "${SRA_DIR}" "${FASTQ_DIR}"

export TMPDIR="${PWD}/${SRA_ID}/tmp"
mkdir -p "${TMPDIR}"

############################
# DOWNLOAD
############################

echo "▶ Downloading ${SRA_ID} via prefetch..."
prefetch \
  --max-size 100G \
  --output-directory "${SRA_DIR}" \
  "${SRA_ID}"

SRA_FILE="${SRA_DIR}/${SRA_ID}.sra"

if [[ ! -s "${SRA_FILE}" ]]; then
  echo "ERROR: ${SRA_FILE} not found or empty"
  exit 1
fi

############################
# CONVERT TO FASTQ
############################

echo "▶ Converting ${SRA_ID} to FASTQ..."

fasterq-dump \
  --threads "${THREADS}" \
  --skip-technical \
  --split-files \
  --outdir "${FASTQ_DIR}" \
  "${SRA_FILE}"

############################
# REPAIR PAIRS
############################

echo "▶ Repairing paired-end reads..."

repair.sh \
  in1="${FASTQ_DIR}/${SRA_ID}_1.fastq" \
  in2="${FASTQ_DIR}/${SRA_ID}_2.fastq" \
  out1="${FASTQ_DIR}/${SRA_ID}_1.repaired.fastq" \
  out2="${FASTQ_DIR}/${SRA_ID}_2.repaired.fastq" \
  outs="${FASTQ_DIR}/${SRA_ID}_singletons.fastq" \
  overwrite=t


echo "▶ Compressing FASTQ files..."

pigz -p "${THREADS}" \
  "${FASTQ_DIR}/${SRA_ID}_1.repaired.fastq" \
  "${FASTQ_DIR}/${SRA_ID}_2.repaired.fastq" \
  "${FASTQ_DIR}/${SRA_ID}_singletons.fastq"

echo "✔ Done: ${SRA_ID}"

rm -rf "${TMPDIR}"
