#!/bin/bash
#SBATCH --nodes=2
#SBATCH --ntasks=48
#SBATCH --ntasks-per-node=24
#SBATCH --cpus-per-task=1
#SBATCH --mem=260G
#SBATCH --time=24:00:00
#SBATCH --partition=genoa
#SBATCH --output=mpi-render-%x-%j.out
#SBATCH --error=mpi-render-%x-%j.err

set -euo pipefail

: "${CASE_ID:?submit with --export=ALL,CASE_ID=<case>}"
: "${ROOT:?submit with --export=ALL,ROOT=<repository-root>,CASE_ID=<case>}"
[[ "${CASE_ID}" =~ ^[0-9]+$ ]] || {
  echo "CASE_ID must contain digits only" >&2
  exit 2
}

CASE_DIR="${ROOT}/simulationCases/${CASE_ID}"
POST_DIR=${POST_DIR:-"${ROOT}/postprocess/${CASE_ID}-mpi-render"}
FRAME_WORKERS=${FRAME_WORKERS:-1}
MPI_RANKS_PER_FRAME=${MPI_RANKS_PER_FRAME:-48}
MPI_NODES_PER_FRAME=${MPI_NODES_PER_FRAME:-2}
MPI_TASKS_PER_NODE=${MPI_TASKS_PER_NODE:-24}
MPI_MEMORY_PER_FRAME=${MPI_MEMORY_PER_FRAME:-250G}
FRAME_FOLDER=${FRAME_FOLDER:-Video_view3_v3}

test -d "${CASE_DIR}/intermediate"
mkdir -p "${POST_DIR}" "${ROOT}/postprocess/_logs"
cd "${POST_DIR}"
ln -sfn "${CASE_DIR}/intermediate" intermediate
cp -f "${ROOT}/postProcess/getView3D_v3.c" .
cp -f "${ROOT}/postProcess/render_frames_mpi.py" .

module purge
module load 2024
module load OpenMPI/5.0.3-GCC-13.3.0
module load FFmpeg/7.0.2-GCCcore-13.3.0
source "${ROOT}/.project_config"

CC99='mpicc -std=c99 -D_GNU_SOURCE=1' \
  qcc -O2 -Wall -D_MPI=1 -disable-dimensions getView3D_v3.c \
  -o getView3D_v3 -L"${BASILISK}/gl" -lglutils -lfb_tiny -lm

SNAPSHOTS=$(find -L intermediate -regextype posix-extended -maxdepth 1 \
  -type f -regex '.*/snapshot-[0-9]+(\.[0-9]+)?' | wc -l)
echo "MPI_RENDER_START|$(date -Is)|case=${CASE_ID}|snapshots=${SNAPSHOTS}|workers=${FRAME_WORKERS}|ranks_per_frame=${MPI_RANKS_PER_FRAME}"

export FRAME_WORKERS MPI_RANKS_PER_FRAME MPI_NODES_PER_FRAME
export MPI_TASKS_PER_NODE MPI_MEMORY_PER_FRAME FRAME_FOLDER
python3 render_frames_mpi.py --cpus "${FRAME_WORKERS}" --skip-video

if [[ "${VALIDATION_ONLY:-0}" == 1 ]]; then
  REFERENCE_FOLDER=${REFERENCE_FOLDER:-Video_view3_v2}
  test "${FRAME_FOLDER}" != "${REFERENCE_FOLDER}"
  shopt -s nullglob
  VALIDATION_FRAMES=("${FRAME_FOLDER}"/*.png)
  test "${#VALIDATION_FRAMES[@]}" -gt 0
  for FRAME in "${VALIDATION_FRAMES[@]}"; do
    REFERENCE="${REFERENCE_FOLDER}/$(basename "${FRAME}")"
    test -s "${REFERENCE}"
    SSIM_LOG=$(ffmpeg -i "${REFERENCE}" -i "${FRAME}" \
      -lavfi ssim -f null - 2>&1)
    SSIM=$(sed -n 's/.* All:\([0-9.]*\) .*/\1/p' <<< "${SSIM_LOG}" | tail -1)
    test -n "${SSIM}"
    awk -v score="${SSIM}" 'BEGIN { exit !(score >= 0.99) }'
    echo "MPI_RENDER_MATCH|frame=$(basename "${FRAME}")|ssim=${SSIM}"
  done
  echo "MPI_RENDER_VALIDATION_DONE|$(date -Is)|case=${CASE_ID}|snapshots=${SNAPSHOT_TIMES:-all}"
  exit 0
fi

if [[ -n "${SNAPSHOT_TIMES:-}" ]]; then
  echo "MPI_RENDER_SUBSET_DONE|$(date -Is)|case=${CASE_ID}|snapshots=${SNAPSHOT_TIMES}"
  exit 0
fi

FRAMES=$(python3 render_frames_mpi.py --validate-manifest)
test "${FRAMES}" -eq "${SNAPSHOTS}"

VIDEO_TMP="video_${CASE_ID}.tmp.mp4"
ffmpeg -y -threads 8 -r 50 -f concat -safe 0 \
  -i "${FRAME_FOLDER}/frames.ffconcat" -c:v libx264 -pix_fmt yuv420p \
  -movflags +faststart "${VIDEO_TMP}" > "ffmpeg_${CASE_ID}.log" 2>&1
mv -f "${VIDEO_TMP}" "video_${CASE_ID}.mp4"

VIDEO_BYTES=$(stat -c%s "video_${CASE_ID}.mp4")
test "${VIDEO_BYTES}" -gt 0
echo "MPI_RENDER_DONE|$(date -Is)|case=${CASE_ID}|frames=${FRAMES}|video_bytes=${VIDEO_BYTES}"
