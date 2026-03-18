#!/bin/bash
# Build a clean .rbz package for the CNC Exporter extension.
# Usage: ./build_rbz.sh [output_dir]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="${1:-$SCRIPT_DIR/build}"

# Extract version from the loader file
VERSION=$(grep -m1 'EXTENSION.version' "$SCRIPT_DIR/ed_cnc_exporter.rb" | sed 's/.*"\(.*\)".*/\1/')
if [ -z "$VERSION" ]; then
  echo "Error: Could not read version from ed_cnc_exporter.rb" >&2
  exit 1
fi

RBZ_NAME="ed_cnc_exporter_v${VERSION}.rbz"

mkdir -p "$OUTPUT_DIR"

# Build from a temp directory to get a clean zip
TMPDIR=$(mktemp -d)
trap "rm -rf '$TMPDIR'" EXIT

# Copy only the files that belong in the extension
cp "$SCRIPT_DIR/ed_cnc_exporter.rb" "$TMPDIR/"

mkdir -p "$TMPDIR/ed_cnc_exporter/html"
mkdir -p "$TMPDIR/ed_cnc_exporter/icons"

for f in main.rb utils.rb geometry_extractor.rb path_converter.rb \
         svg_builder.rb json_builder.rb dialog.rb updater.rb; do
  cp "$SCRIPT_DIR/ed_cnc_exporter/$f" "$TMPDIR/ed_cnc_exporter/"
done

cp "$SCRIPT_DIR/ed_cnc_exporter/html/export_dialog.html" "$TMPDIR/ed_cnc_exporter/html/"
cp "$SCRIPT_DIR/ed_cnc_exporter/html/style.css"           "$TMPDIR/ed_cnc_exporter/html/"
cp "$SCRIPT_DIR/ed_cnc_exporter/html/dialog.js"            "$TMPDIR/ed_cnc_exporter/html/"

cp "$SCRIPT_DIR/ed_cnc_exporter/icons/icon_16.png" "$TMPDIR/ed_cnc_exporter/icons/"
cp "$SCRIPT_DIR/ed_cnc_exporter/icons/icon_24.png" "$TMPDIR/ed_cnc_exporter/icons/"

# Create the .rbz (zip) from inside the temp dir so paths are relative
cd "$TMPDIR"
zip -r "$OUTPUT_DIR/$RBZ_NAME" \
  ed_cnc_exporter.rb \
  ed_cnc_exporter/ \
  -x '*.DS_Store' -x '__MACOSX/*'

echo ""
echo "Built: $OUTPUT_DIR/$RBZ_NAME"
