#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/preview
out="${1:-$PWD/Preview/Ритм.png}"
swiftc -swift-version 5 -parse-as-library -DRITM_PREVIEW App/RitmApp.swift App/Core/*.swift App/UI/*.swift Preview/Render.swift -o .build/preview/render
.build/preview/render "$out"
