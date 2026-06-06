#!/bin/bash

set -eo pipefail

SCRIPT_DIR=$(dirname "$0")
source $SCRIPT_DIR/vars.source

mkdir -p $SCRIPT_DIR/build/
rm -f $SCRIPT_DIR/build/$PROJECT_NAME.love

$SCRIPT_DIR/convert_assets.sh

zip -9 -r $SCRIPT_DIR/build/$PROJECT_NAME.love ./project/
