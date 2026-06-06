#!/bin/bash

set -eo pipefail

SCRIPT_DIR=$(dirname "$0")
source $SCRIPT_DIR/vars.source

if [ ! "$1" == "skip" ]; then
    $SCRIPT_DIR/convert_assets.sh $1
fi 

echo "[Game] Starting..."
$LOVE_BIN ./project/
