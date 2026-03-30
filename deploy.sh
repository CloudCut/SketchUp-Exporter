#!/bin/bash
# Deploy the extension directly to SketchUp 2025 and 2026 plugin directories.
# Usage: ./deploy.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

TARGETS=(
  "$HOME/Library/Application Support/SketchUp 2025/SketchUp/Plugins"
  "$HOME/Library/Application Support/SketchUp 2026/SketchUp/Plugins"
)

for PLUGIN_DIR in "${TARGETS[@]}"; do
  if [ ! -d "$PLUGIN_DIR" ]; then
    echo "Skipping (not found): $PLUGIN_DIR"
    continue
  fi

  echo "Deploying to: $PLUGIN_DIR"

  # Copy loader file
  cp "$SCRIPT_DIR/cloudcut_exporter.rb" "$PLUGIN_DIR/"

  # Copy extension directory
  mkdir -p "$PLUGIN_DIR/cloudcut_exporter/html"
  mkdir -p "$PLUGIN_DIR/cloudcut_exporter/icons"

  for f in main.rb utils.rb geometry_extractor.rb path_converter.rb \
           svg_builder.rb json_builder.rb dialog.rb updater.rb; do
    cp "$SCRIPT_DIR/cloudcut_exporter/$f" "$PLUGIN_DIR/cloudcut_exporter/"
  done

  cp "$SCRIPT_DIR/cloudcut_exporter/html/export_dialog.html" "$PLUGIN_DIR/cloudcut_exporter/html/"
  cp "$SCRIPT_DIR/cloudcut_exporter/html/style.css"           "$PLUGIN_DIR/cloudcut_exporter/html/"
  cp "$SCRIPT_DIR/cloudcut_exporter/html/dialog.js"           "$PLUGIN_DIR/cloudcut_exporter/html/"

  cp "$SCRIPT_DIR/cloudcut_exporter/icons/icon_16.png" "$PLUGIN_DIR/cloudcut_exporter/icons/"
  cp "$SCRIPT_DIR/cloudcut_exporter/icons/icon_24.png" "$PLUGIN_DIR/cloudcut_exporter/icons/"

  echo "  Done."
done

echo ""
echo "Restart SketchUp to load the updated extension."
