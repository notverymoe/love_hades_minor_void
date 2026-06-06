#!/usr/bin/env bash

#
# Processes all source assets into game assets.
#
# Usage: ./convert_assets.sh [force]
#
# Will skip assets with a matching checksum, unless "force" is specified
#

set -eo pipefail
shopt -s nullglob
SCRIPT_DIR=$(dirname "$(realpath "$0")")

################################################################################

process_texture() {
    local FORCE="$1"
    local SIZE_ALBEDO="$2"
    local SIZE_NORMAL="$3"
    local SIZE_ORMD="$4"
    local XCF="$5"
    
    OUTDIR=$(basename "$XCF" .xcf)

    # Validate checksum
    VALID=0
    if [ ! "$FORCE" == "force" ]; then
        if [ -f "$OUTDIR/.sha256" ]; then
            if sha256sum --check $OUTDIR/.sha256 --status; then
                echo "[Assets] Checksum matched. Skipping: $OUTDIR"
                VALID=1
            fi
        fi
    fi
    
    # Regenerate if checksum missing or doesn't match
    if [ "$VALID" == "0" ]; then
        $SCRIPT_DIR/xcf_to_dds.sh "$SIZE_ALBEDO" "$SIZE_NORMAL" "$SIZE_ORMD" "$XCF"

        # Write checksum
        sha256sum -b "$XCF" >> "$OUTDIR/.sha256"

        # Instruct git to ignore the folder
        echo \* >> "$OUTDIR/.gitignore"
    fi
}

################################################################################
echo "[Assets] Processing Materials..."

#==========================================================
echo "[Assets] Processing lowres (512px) Materials"

mkdir -p $SCRIPT_DIR/../project/assets/materials/lo
cd $SCRIPT_DIR/../project/assets/materials/lo
for XCF in "$SCRIPT_DIR"/../project/assets/src/materials/lo/*.xcf; do
    process_texture "$1" "512" "512" "512" "$XCF" 
done

echo "[Assets] Finished lowres (512px) Materials"
#==========================================================

#==========================================================
echo "[Assets] Processing medres (1024px) Materials"

mkdir -p $SCRIPT_DIR/../project/assets/materials/md
cd $SCRIPT_DIR/../project/assets/materials/md
for XCF in "$SCRIPT_DIR"/../project/assets/src/materials/md/*.xcf; do
    process_texture "$1" "1024" "512" "512" "$XCF" 
done

echo "[Assets] Finished medres (1024px) Materials"
#==========================================================

#==========================================================
echo "[Assets] Processing highres (2048px) Materials"

mkdir -p $SCRIPT_DIR/../project/assets/materials/hi
cd $SCRIPT_DIR/../project/assets/materials/hi
for XCF in "$SCRIPT_DIR"/../project/assets/src/materials/hi/*.xcf; do
    process_texture "$1" "2048" "1024" "512" "$XCF" 
done

echo "[Assets] Finished highres (2048px) Materials"
#==========================================================

################################################################################