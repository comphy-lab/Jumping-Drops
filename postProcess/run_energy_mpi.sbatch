#!/bin/bash
#SBATCH --nodes=2
#SBATCH --ntasks=48
#SBATCH --ntasks-per-node=24
#SBATCH --cpus-per-task=1
#SBATCH --mem=260G
#SBATCH --time=2-00:00:00
#SBATCH --partition=genoa
#SBATCH --output=mpi-energy-%x-%j.out
#SBATCH --error=mpi-energy-%x-%j.err

set -euo pipefail

: "${CASE_ID:?submit with --export=ALL,CASE_ID=<case>}"
: "${ROOT:?submit with --export=ALL,ROOT=<repository-root>,CASE_ID=<case>}"
[[ "${CASE_ID}" =~ ^[0-9]+$ ]] || {
  echo "CASE_ID must contain digits only" >&2
  exit 2
}

CASE_DIR="${ROOT}/simulationCases/${CASE_ID}"
POST_DIR=${POST_DIR:-"${ROOT}/postprocess/${CASE_ID}-mpi-energy"}
ENERGY_WORKERS=${ENERGY_WORKERS:-1}
MPI_RANKS_PER_FRAME=${MPI_RANKS_PER_FRAME:-48}
MPI_NODES_PER_FRAME=${MPI_NODES_PER_FRAME:-2}
MPI_TASKS_PER_NODE=${MPI_TASKS_PER_NODE:-24}
MPI_MEMORY_PER_FRAME=${MPI_MEMORY_PER_FRAME:-250G}

test -d "${CASE_DIR}/intermediate"
test -f "${CASE_DIR}/case.params"
mkdir -p "${POST_DIR}" "${ROOT}/postprocess/_logs"
cd "${POST_DIR}"
ln -sfn "${CASE_DIR}/intermediate" intermediate
cp -f "${CASE_DIR}/case.params" .
cp -f "${ROOT}/postProcess/getEnergy.c" .
cp -f "${ROOT}/postProcess/run_energy_mpi.py" .
cp -f "${ROOT}/postProcess/energy_budget.py" .

module purge
module load 2024
module load OpenMPI/5.0.3-GCC-13.3.0
source "${ROOT}/.project_config"

CC99='mpicc -std=c99 -D_GNU_SOURCE=1' \
  qcc -O2 -Wall -D_MPI=1 -disable-dimensions getEnergy.c \
  -o getEnergy -lm

SNAPSHOTS=$(find -L intermediate -regextype posix-extended -maxdepth 1 \
  -type f -regex '.*/snapshot-[0-9]+(\.[0-9]+)?' | wc -l)
echo "MPI_ENERGY_START|$(date -Is)|case=${CASE_ID}|snapshots=${SNAPSHOTS}|workers=${ENERGY_WORKERS}|ranks_per_frame=${MPI_RANKS_PER_FRAME}"

export ENERGY_WORKERS MPI_RANKS_PER_FRAME MPI_NODES_PER_FRAME
export MPI_TASKS_PER_NODE MPI_MEMORY_PER_FRAME
python3 run_energy_mpi.py --cpus "${ENERGY_WORKERS}"

test -s getEnergy.dat
ROWS=$(grep -cve '^[[:space:]]*$' getEnergy.dat || true)
test "${ROWS}" -eq "${SNAPSHOTS}"

if python3 energy_budget.py getEnergy.dat energyBudget; then
  echo "MPI_ENERGY_BUDGET|$(date -Is)|case=${CASE_ID}|rows=${ROWS}"
else
  echo "MPI_ENERGY_BUDGET_SKIP|$(date -Is)|case=${CASE_ID}|getEnergy.dat written; plot unavailable"
fi

echo "MPI_ENERGY_DONE|$(date -Is)|case=${CASE_ID}|rows=${ROWS}"
