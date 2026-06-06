#!/usr/bin/env bash

# Converts GIMP XCF layers into engine textures.
#
# usage: xcf_to_dds.sh <GIMP XCF FILE>
#
# Requires these tools on the PATH:
# - imagemagick (https://github.com/imagemagick/imagemagick)
# - compressonatorcli (https://github.com/GPUOpen-Tools/compressonator)
#
# This will destroy and re-create a folder in the current directory with the
# same name as the selected XCF file. It will then extract the following layers
# from the XCF file:
# - ALBEDO (RGB)
# - NORMAL (RGB, Assumes GL Y-up)
# - AMBIENT (GREY)
# - ROUGHNESS (GREY)
# - METALNESS (GREY)
#
# It will then create the following texture maps in that folder:
# - tex_albedo.dds   
#     - Contains: ALBEDO
#     - BC7-encoded with mipmaps
# - tex_normal.dds   (BC5-encoded Red/Green NORMAL channels with mipmaps)
#     - Contains: NORMAL (RG)
#     - BC5-encoded with mipmaps
# - tex_material.dds
#     - Contains: AMBIENT (R), ROUGHNESS (G), METALNESS(G)
#     - BC7-encoded with mipmaps
# 

set -eo pipefail

SIZE_ALBEDO="$1"
SIZE_NORMAL="$2"
SIZE_ORMD="$3"
XCF="$4"

# Create output directory
OUTDIR=$(basename "$XCF" .xcf)
rm -rf "$OUTDIR"
mkdir -p "$OUTDIR"

################################################################################
echo "[XCF_TO_DDS] Setting up: $OUTDIR"

# Create temp dir and setup to cleanup on exit
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Cache Layer Information, force uppercase names
LAYERS=$(magick "$XCF" -format "%s:%l\n" info: | tr '[:lower:]' '[:upper:]')

# Find layer index for magick
find_layer() {  
    # Force uppercase name argument
    local name=$(tr '[:lower:]' '[:upper:]' <<< $1)

    # Extract layer id from cached input
    awk -F: -v layer="$name" '$2==layer { print $1; exit }' <<< $LAYERS
}

# Extract layer from xcf as png
extract_layer() {
    local SIZE="$1"
    local NAME="$2"
    local OUTPUT="$3"

    # Find layer name
    local IDX=$(find_layer "$NAME")
    if [[ -z "$IDX" ]]; then
        echo "Layer not found: $NAME" >&2
        exit 1
    fi

    # Extract to output
    magick "$XCF[$IDX]" -filter Lanczos -resize "$SIZE"x"$SIZE" "$OUTPUT"
}

################################################################################
echo "[XCF_TO_DDS] Processing: $OUTDIR"

################################################################################
echo "[XCF_TO_DDS] Extracting XCF Layers..."

extract_layer "$SIZE_ALBEDO" "Albedo"       "$TMP/albedo.png"
extract_layer "$SIZE_NORMAL" "Normal"       "$TMP/normal_un.mpc"
extract_layer "$SIZE_ORMD"   "Ambient"      "$TMP/ambient.mpc"
extract_layer "$SIZE_ORMD"   "Roughness"    "$TMP/roughness.mpc"
extract_layer "$SIZE_ORMD"   "Metalness"    "$TMP/metalness.mpc"
extract_layer "$SIZE_ORMD"   "Displacement" "$TMP/displacement.mpc"

################################################################################
echo "[XCF_TO_DDS] Building Material ORMD Texture..."

magick \
    "$TMP/ambient.mpc" "$TMP/roughness.mpc" "$TMP/metalness.mpc" "$TMP/displacement.mpc" \
    -combine "$TMP/orm.png"

################################################################################
echo "[XCF_TO_DDS] Building Normal Texture..."

magick \
    "$TMP/normal_un.mpc" \
    -channel R -fx "nx = u.r * 2 - 1; ny = u.g * 2 - 1; nz = u.b * 2 - 1; len = sqrt(nx*nx + ny*ny + nz*nz); len > 0 ? (nx/len * 0.5 + 0.5) : 0.5" \
    -channel G -fx "nx = u.r * 2 - 1; ny = u.g * 2 - 1; nz = u.b * 2 - 1; len = sqrt(nx*nx + ny*ny + nz*nz); len > 0 ? (ny/len * 0.5 + 0.5) : 0.5" \
    -channel B -evaluate set 0% +channel \
    "$TMP/normal_xy.png"

################################################################################
echo "[XCF_TO_DDS] Compressing DDS Textures..."

compressonatorcli -silent \
    -mipsize 1 \
    -fd BC7 -Quality 0.6 -CompressionSpeed 0 -UseChannelWeighting 1 \
    "$TMP/albedo.png" "$OUTDIR/tex_albedo.dds" > /dev/null 2>&1

compressonatorcli -silent \
    -mipsize 1 \
    -fd BC5 -Quality 0.6 -CompressionSpeed 0 -UseChannelWeighting 0 -FilterGamma 1.0 \
    "$TMP/normal_xy.png" "$OUTDIR/tex_normal.dds" > /dev/null 2>&1

compressonatorcli -silent \
    -mipsize 1 \
    -fd BC7 -Quality 0.6 -CompressionSpeed 0 -UseChannelWeighting 0 -FilterGamma 1.0 \
    "$TMP/orm.png" "$OUTDIR/tex_material.dds" > /dev/null 2>&1

################################################################################
echo "[XCF_TO_DDS] Done:"
echo "[XCF_TO_DDS] - $OUTDIR/tex_albedo.dds"
echo "[XCF_TO_DDS] - $OUTDIR/tex_normal.dds"
echo "[XCF_TO_DDS] - $OUTDIR/tex_material.dds"
