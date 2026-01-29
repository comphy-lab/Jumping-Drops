#!/bin/bash
# runSimulation.sh - Run single jumping drops simulation from root directory
# Creates case folder in simulationCases/<CaseNo>/ and runs simulation there

set -e  # Exit on error

# ============================================================
# Configuration
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source project configuration
if [ -f "${SCRIPT_DIR}/.project_config" ]; then
    source "${SCRIPT_DIR}/.project_config"
else
    echo "ERROR: .project_config not found" >&2
    echo "       Run ./reset_install_requirements.sh or copy .project_config.example" >&2
    exit 1
fi

# Source parameter parsing library
if [ -f "${SCRIPT_DIR}/src-local/parse_params.sh" ]; then
    source "${SCRIPT_DIR}/src-local/parse_params.sh"
else
    echo "ERROR: src-local/parse_params.sh not found" >&2
    exit 1
fi

# ============================================================
# Usage Information
# ============================================================
usage() {
    cat <<EOF
Usage: $0 [OPTIONS] [params_file]

Run single jumping drops simulation from root directory.
Creates case folder in simulationCases/<CaseNo>/ based on parameter file.

Options:
    -c, --compile-only    Compile but don't run simulation
    --init-only           Run initialization phase only (creates dumpInit)
    --main-only           Run main simulation only (requires dumpInit)
    -d, --debug           Compile with debug flags (-g -DTRASH=1)
    -m, --mpi             Enable MPI parallel execution (main phase only)
    --cores N             Number of MPI cores (default: 4, requires --mpi)
    -v, --verbose         Verbose output
    -h, --help           Show this help message

Parameter file mode (default):
    $0 default.params

If no parameter file specified, uses default.params from current directory.

Environment variables:
    QCC_FLAGS     Additional qcc compiler flags

Examples:
    # Run full workflow (init + main, serial)
    $0

    # Run initialization only (creates dumpInit from STL)
    $0 --init-only

    # Run main simulation only (requires dumpInit)
    $0 --main-only --mpi --cores 8

    # Run with MPI parallel execution (4 cores)
    $0 --mpi

    # Run with MPI using 8 cores
    $0 --mpi --cores 8 default.params

    # Compile only (check for errors)
    $0 --compile-only

    # Debug mode with memory checking
    $0 --debug default.params

For more information, see README.md
EOF
}

# ============================================================
# Parse Command Line Options
# ============================================================
COMPILE_ONLY=0
INIT_ONLY=0
MAIN_ONLY=0
DEBUG_FLAGS=""
VERBOSE=0
MPI_ENABLED=0
MPI_CORES=4

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--compile-only)
            COMPILE_ONLY=1
            shift
            ;;
        --init-only)
            INIT_ONLY=1
            shift
            ;;
        --main-only)
            MAIN_ONLY=1
            shift
            ;;
        -d|--debug)
            DEBUG_FLAGS="-g -DTRASH=1"
            shift
            ;;
        -m|--mpi)
            MPI_ENABLED=1
            shift
            ;;
        --cores)
            MPI_CORES="$2"
            if ! [[ "$MPI_CORES" =~ ^[0-9]+$ ]] || [ "$MPI_CORES" -lt 1 ]; then
                echo "ERROR: --cores requires a positive integer, got: $MPI_CORES" >&2
                exit 1
            fi
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "ERROR: Unknown option: $1" >&2
            usage
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

# ============================================================
# Detect OS and Verify MPI
# ============================================================
OS_TYPE=$(uname -s)

# Verify MPI tools if MPI is enabled
if [ $MPI_ENABLED -eq 1 ]; then
    if ! command -v mpicc &> /dev/null; then
        echo "ERROR: mpicc not found. MPI compilation requires mpicc (OpenMPI or MPICH)." >&2
        echo "       Install MPI tools or run without --mpi flag for serial execution." >&2
        exit 1
    fi
    if ! command -v mpirun &> /dev/null; then
        echo "ERROR: mpirun not found. MPI execution requires mpirun (OpenMPI or MPICH)." >&2
        echo "       Install MPI tools or run without --mpi flag for serial execution." >&2
        exit 1
    fi
fi

# ============================================================
# Determine Parameter File
# ============================================================
PARAM_FILE="${1:-default.params}"

if [ ! -f "$PARAM_FILE" ]; then
    echo "ERROR: Parameter file not found: $PARAM_FILE" >&2
    exit 1
fi

[ $VERBOSE -eq 1 ] && echo "Parameter file: $PARAM_FILE"

# ============================================================
# Parse Parameters to Get CaseNo
# ============================================================
parse_param_file "$PARAM_FILE"

CASE_NO=$(get_param "CaseNo")

if [ -z "$CASE_NO" ]; then
    echo "ERROR: CaseNo not found in parameter file" >&2
    exit 1
fi

# Validate CaseNo is 4 digits
if ! [[ "$CASE_NO" =~ ^[0-9]{4}$ ]] || [ "$CASE_NO" -lt 1000 ] || [ "$CASE_NO" -gt 9999 ]; then
    echo "ERROR: CaseNo must be 4-digit (1000-9999), got: $CASE_NO" >&2
    exit 1
fi

CASE_DIR="simulationCases/${CASE_NO}"

# Validate phase flags
if [ $INIT_ONLY -eq 1 ] && [ $MAIN_ONLY -eq 1 ]; then
    echo "ERROR: Cannot specify both --init-only and --main-only" >&2
    exit 1
fi

# Determine phase mode
PHASE_MODE="both"
if [ $INIT_ONLY -eq 1 ]; then
    PHASE_MODE="init"
elif [ $MAIN_ONLY -eq 1 ]; then
    PHASE_MODE="main"
fi

echo "========================================="
echo "Jumping Drops Simulation - Single Case"
echo "========================================="
echo "Case Number: $CASE_NO"
echo "Case Directory: $CASE_DIR"
echo "Parameter File: $PARAM_FILE"
echo "Phase Mode: $PHASE_MODE"
if [ $MPI_ENABLED -eq 1 ]; then
    echo "Execution Mode: MPI Parallel ($MPI_CORES cores)"
else
    echo "Execution Mode: Serial"
fi
echo ""

# ============================================================
# Create Case Directory
# ============================================================
if [ ! -d "$CASE_DIR" ]; then
    echo "Creating case directory: $CASE_DIR"
    mkdir -p "$CASE_DIR"
else
    echo "Case directory exists (will use restart if available)"
fi

# Copy parameter file to case directory for record keeping
cp "$PARAM_FILE" "$CASE_DIR/case.params"

# Change to case directory
cd "$CASE_DIR"
[ $VERBOSE -eq 1 ] && echo "Working directory: $(pwd)"

# ============================================================
# Compilation
# ============================================================
echo ""
echo "========================================="
echo "Compilation"
echo "========================================="

# Compile initialization phase (if needed)
if [ "$PHASE_MODE" = "init" ] || [ "$PHASE_MODE" = "both" ]; then
    SRC_INIT="../jumpingDrops_init.c"
    EXEC_INIT="jumpingDrops_init"

    if [ ! -f "$SRC_INIT" ]; then
        echo "ERROR: Source file $SRC_INIT not found" >&2
        exit 1
    fi

    echo "Compiling initialization phase ($SRC_INIT)..."
    [ $VERBOSE -eq 1 ] && echo "Compiler: qcc (serial only, STL geometry)"
    [ $VERBOSE -eq 1 ] && echo "Include paths: -I../../src-local"
    [ $VERBOSE -eq 1 ] && echo "Flags: -O2 -Wall -disable-dimensions $DEBUG_FLAGS $QCC_FLAGS"

    # Init phase is always serial (distance.h not MPI-compatible)
    qcc -I../../src-local \
        -O2 -Wall -disable-dimensions \
        $DEBUG_FLAGS $QCC_FLAGS \
        "$SRC_INIT" -o "$EXEC_INIT" -lm

    if [ $? -ne 0 ]; then
        echo "ERROR: Compilation of initialization phase failed" >&2
        exit 1
    fi

    echo "Compilation successful: $EXEC_INIT"
    echo ""
fi

# Compile main phase (if needed)
if [ "$PHASE_MODE" = "main" ] || [ "$PHASE_MODE" = "both" ]; then
    SRC_MAIN="../jumpingDrops_main.c"
    EXEC_MAIN="jumpingDrops_main"

    if [ ! -f "$SRC_MAIN" ]; then
        echo "ERROR: Source file $SRC_MAIN not found" >&2
        exit 1
    fi

    echo "Compiling main simulation phase ($SRC_MAIN)..."

    if [ $MPI_ENABLED -eq 1 ]; then
        # MPI parallel compilation
        if [ "$OS_TYPE" = "Darwin" ]; then
            # macOS
            [ $VERBOSE -eq 1 ] && echo "Compiler: CC99='mpicc -std=c99' qcc"
            [ $VERBOSE -eq 1 ] && echo "Include paths: -I../../src-local"
            [ $VERBOSE -eq 1 ] && echo "Flags: -Wall -O2 -D_MPI=1 -disable-dimensions $DEBUG_FLAGS $QCC_FLAGS"

            CC99='mpicc -std=c99' qcc -I../../src-local \
                -Wall -O2 -D_MPI=1 -disable-dimensions \
                $DEBUG_FLAGS $QCC_FLAGS \
                "$SRC_MAIN" -o "$EXEC_MAIN" -lm
        else
            # Linux
            [ $VERBOSE -eq 1 ] && echo "Compiler: CC99='mpicc -std=c99 -D_GNU_SOURCE=1' qcc"
            [ $VERBOSE -eq 1 ] && echo "Include paths: -I../../src-local"
            [ $VERBOSE -eq 1 ] && echo "Flags: -Wall -O2 -D_MPI=1 -disable-dimensions $DEBUG_FLAGS $QCC_FLAGS"

            CC99='mpicc -std=c99 -D_GNU_SOURCE=1' qcc -I../../src-local \
                -Wall -O2 -D_MPI=1 -disable-dimensions \
                $DEBUG_FLAGS $QCC_FLAGS \
                "$SRC_MAIN" -o "$EXEC_MAIN" -lm
        fi
    else
        # Serial compilation
        [ $VERBOSE -eq 1 ] && echo "Compiler: qcc (serial)"
        [ $VERBOSE -eq 1 ] && echo "Include paths: -I../../src-local"
        [ $VERBOSE -eq 1 ] && echo "Flags: -O2 -Wall -disable-dimensions $DEBUG_FLAGS $QCC_FLAGS"

        qcc -I../../src-local \
            -O2 -Wall -disable-dimensions \
            $DEBUG_FLAGS $QCC_FLAGS \
            "$SRC_MAIN" -o "$EXEC_MAIN" -lm
    fi

    if [ $? -ne 0 ]; then
        echo "ERROR: Compilation of main phase failed" >&2
        exit 1
    fi

    echo "Compilation successful: $EXEC_MAIN"
    echo ""
fi

# Exit if compile-only mode
if [ $COMPILE_ONLY -eq 1 ]; then
    echo ""
    echo "Compile-only mode: Stopping here"
    cd ../..
    exit 0
fi

# ============================================================
# Execution
# ============================================================
echo ""
echo "========================================="
echo "Execution"
echo "========================================="

# Parse parameters from case.params
source "${SCRIPT_DIR}/src-local/parse_params.sh"
parse_param_file "case.params"

Oh=$(get_param "Oh")
Bo=$(get_param "Bo")
MAXlevel=$(get_param "MAXlevel")
tmax=$(get_param "tmax")

if [ -z "$Oh" ] || [ -z "$Bo" ] || [ -z "$MAXlevel" ]; then
    echo "ERROR: Missing required parameters (Oh, Bo, MAXlevel) in case.params" >&2
    exit 1
fi

echo "Parameters: Oh=$Oh, Bo=$Bo, MAXlevel=$MAXlevel"

# Run initialization phase (if needed)
if [ "$PHASE_MODE" = "init" ] || [ "$PHASE_MODE" = "both" ]; then
    echo ""
    echo "========================================="
    echo "Phase 1: Initialization (STL → dumpInit)"
    echo "========================================="

    if [ -f "dumpInit" ]; then
        echo "Warning: dumpInit already exists - will be overwritten"
    fi

    echo "Command: ./jumpingDrops_init $Oh $Bo $MAXlevel"
    ./jumpingDrops_init $Oh $Bo $MAXlevel

    INIT_EXIT_CODE=$?

    if [ $INIT_EXIT_CODE -ne 0 ]; then
        echo "ERROR: Initialization phase failed with exit code $INIT_EXIT_CODE" >&2
        cd ../..
        exit $INIT_EXIT_CODE
    fi

    if [ ! -f "dumpInit" ]; then
        echo "ERROR: dumpInit not created by initialization phase" >&2
        cd ../..
        exit 1
    fi

    # Copy dumpInit to dump for main phase
    cp dumpInit dump
    echo "Initialization phase completed successfully"
    echo ""
fi

# Run main simulation phase (if needed)
if [ "$PHASE_MODE" = "main" ] || [ "$PHASE_MODE" = "both" ]; then
    echo ""
    echo "========================================="
    echo "Phase 2: Main Simulation"
    echo "========================================="

    # Check for dump file
    if [ ! -f "dump" ]; then
        echo "ERROR: dump file not found - run initialization phase first" >&2
        cd ../..
        exit 1
    fi

    if [ -f "restart" ]; then
        echo "Restart file found - simulation will resume from checkpoint"
    fi

    # Get tmax
    if [ -z "$tmax" ]; then
        echo "ERROR: tmax not found in case.params" >&2
        exit 1
    fi

    echo "Running main simulation: tmax=$tmax"
    echo "Starting simulation..."
    echo "========================================="

    # Run simulation
    if [ $MPI_ENABLED -eq 1 ]; then
        [ $VERBOSE -eq 1 ] && echo "Command: mpirun -np $MPI_CORES ./jumpingDrops_main $tmax $Oh $Bo $MAXlevel"
        mpirun -np $MPI_CORES ./jumpingDrops_main $tmax $Oh $Bo $MAXlevel
    else
        [ $VERBOSE -eq 1 ] && echo "Command: ./jumpingDrops_main $tmax $Oh $Bo $MAXlevel"
        ./jumpingDrops_main $tmax $Oh $Bo $MAXlevel
    fi

    EXIT_CODE=$?

    echo "========================================="
    if [ $EXIT_CODE -eq 0 ]; then
        echo "Main simulation completed successfully"
    else
        echo "Main simulation failed with exit code $EXIT_CODE"
    fi
    echo "========================================="
fi

# Final summary
echo ""
echo "========================================="
echo "Summary"
echo "========================================="
if [ "$PHASE_MODE" = "both" ]; then
    echo "Completed both initialization and main simulation"
    echo "Output location: $CASE_DIR"
elif [ "$PHASE_MODE" = "init" ]; then
    echo "Initialization phase completed"
    echo "dumpInit created in: $CASE_DIR"
elif [ "$PHASE_MODE" = "main" ]; then
    echo "Main simulation completed"
    echo "Output location: $CASE_DIR"
fi
echo "========================================="

# Return to root directory
cd ../..

# Set final exit code
FINAL_EXIT_CODE=0
if [ "$PHASE_MODE" = "main" ] || [ "$PHASE_MODE" = "both" ]; then
    FINAL_EXIT_CODE=${EXIT_CODE:-0}
fi

exit $FINAL_EXIT_CODE
