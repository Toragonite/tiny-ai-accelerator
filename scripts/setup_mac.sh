#!/usr/bin/env bash
# macOS toolchain setup for tiny-ai-accelerator (Homebrew required: https://brew.sh)
set -e
brew install icarus-verilog verilator yosys
brew install --cask gtkwave || echo "gtkwave cask failed — try: brew install gtkwave, or use Surfer (https://surfer-project.org)"
echo
iverilog -V 2>&1 | head -1
verilator --version
yosys -V
echo "Done. Next: make sim"
