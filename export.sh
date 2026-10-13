#!/usr/bin/env bash
# Export the web build to build/web (needs Godot 4.7 web export templates).
cd "$(dirname "$0")" && mkdir -p build/web && godot --headless --export-release Web build/web/index.html
