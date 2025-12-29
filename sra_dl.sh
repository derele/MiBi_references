#!/usr/bin/env bash
# Usage: ./sra_dl_clean.sh <SRA_RUN_ID>
# Example: ./sra_dl_clean.sh DRR417191

set -euo pipefail

############################
# CONFIG
############################

SRA_ID="$1"
THREADS=8

# directories
BASE_DIR="${PWD}/${SRA_ID}"
SRA_DIR="${BASE_DIR}/sra"
FASTQ_DIR="${BASE_DIR}/fastq"
TMP_DIR="${BASE_DIR}/tmp"

############################
# CHECKS
############################

if [[ -z "${SRA_ID}" ]]; then
    echo "ERROR: No SRA accession provided"
    exit 1
fi

for cmd in prefetch fasterq-dump repair.sh pigz; do
    command -v "$cmd" >/dev/null || { echo "ERROR: $cmd not found"; exit 1; }
done

############################
# SETUP
############################

mkdir -p "${SRA_DIR}" "${FASTQ_DIR}" "${TMP_DIR}"
export TMPDIR="${TMP_DIR}"

############################
# DOWNLOAD
############################

echo "▶ Downloading ${SRA_ID} via prefetch..."
prefetch --max-size 100G --output-directory "${SRA_DIR}" "${SRA_ID}"

SRA_FILE="${SRA_DIR}/${SRA_ID}/${SRA_ID}.sra"
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

############################
# CLEANUP INTERMEDIATE FILES
############################

echo "▶ Removing intermediate files..."
rm -rf "${SRA_FILE}" \
   "${FASTQ_DIR}/${SRA_ID}_1.fastq" \
   "${FASTQ_DIR}/${SRA_ID}_2.fastq"

rm -rf "${TMP_DIR}"  # temp folder

############################
# COMPRESS FINAL FASTQ
############################

echo "▶ Compressing final FASTQ files..."
pigz -p "${THREADS}" \
     "${FASTQ_DIR}/${SRA_ID}_1.repaired.fastq" \
     "${FASTQ_DIR}/${SRA_ID}_2.repaired.fastq" \
     "${FASTQ_DIR}/${SRA_ID}_singletons.fastq"

echo "✔ Done: ${SRA_ID}"
echo "Final files are in ${FASTQ_DIR}"
