#!/bin/zsh
# PROTOTYPE runner: builds and launches the Tinycast terminal-instance mock. Pass --demo for a scripted smoke run.
set -e
cd "${0:A:h}"
mkdir -p .build
swiftc -swift-version 5 -O -o .build/TerminalInstanceMock TerminalInstanceMock.swift 2>&1 | grep -v "^$" || true
exec .build/TerminalInstanceMock "$@"
