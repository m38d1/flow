#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"

mkdir -p build
swiftc -swift-version 5 Sources/Core.swift Tests/main.swift -o build/tests
./build/tests
