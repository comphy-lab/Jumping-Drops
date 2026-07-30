#!/bin/bash
#SBATCH --job-name=jumping-drop
#SBATCH --account=nctth181
#SBATCH --nodes=1
#SBATCH --ntasks=192
#SBATCH --cpus-per-task=1
#SBATCH --time=100:00:00
#SBATCH --partition=genoa
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=vatsal.sanjay@comphy-lab.org
#SBATCH --output=slurm-%x-%j.out
#SBATCH --error=slurm-%x-%j.err

# Submit one staged three-dimensional case:
#   sbatch --job-name=jd1020 --export=ALL,CASE_NO=1020 runCaseSnellius.sbatch

set -euo pipefail

if [ -z "${CASE_NO:-}" ]; then
  echo "ERROR: CASE_NO must be exported by sbatch" >&2
  exit 1
fi

case_params="${SLURM_SUBMIT_DIR}/sweep_cases/case_${CASE_NO}.params"
if [ ! -f "$case_params" ]; then
  echo "ERROR: Missing staged parameter file: $case_params" >&2
  exit 1
fi

cd "$SLURM_SUBMIT_DIR"
module purge
module load 2024
module load OpenMPI/5.0.3-GCC-13.3.0
source .project_config

export MPI_LAUNCHER=srun
export MPI_LAUNCHER_NFLAG=-n

echo "=== case ${CASE_NO} | $(date -u +%FT%TZ) | $(hostname) | ${SLURM_NTASKS} ranks ==="
bash runSimulation.sh \
  --main-only \
  --mpi \
  --cores "${SLURM_NTASKS}" \
  "$case_params"
echo "=== case ${CASE_NO} complete | $(date -u +%FT%TZ) ==="
