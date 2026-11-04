#!/bin/bash
# Makes this iMac (macOS) a self-hosted GitHub Actions runner for 0x5E3/IR-Capture, so the Mac builds run here for free
# instead of on GitHub's Mac machines (125th desktop chat). Double-click it in Finder; it opens in Terminal.
#
# It needs a registration token, which GitHub shows only to the repository's owner:
#   github.com/0x5E3/IR-Capture -> Settings -> Actions -> Runners -> New self-hosted runner -> macOS
#   copy the long token after "--token" on that page (it lasts an hour) and paste it when this asks.
#
# What it does: checks for Xcode's command line tools and CMake (installs CMake with Homebrew if it's missing), downloads
# GitHub's runner into ~/actions-runner-ircapture, registers it with the label ircapture-build, and installs it as a
# login item (a LaunchAgent), so it starts whenever you're logged in and picks up Mac build jobs by itself.
# To stop it:   cd ~/actions-runner-ircapture && ./svc.sh stop        To remove it: ./svc.sh uninstall && ./config.sh remove
# A build lands in "Bench Zips/builds" (or ~/BenchBuilds if macOS keeps the runner off the Desktop), and its AU is
# installed in your ~/Library/Audio/Plug-Ins/Components (the build's auval check does that).
set -e
cd "$HOME"
export PATH="$HOME/homebrew/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

echo "== Xcode's command line tools"
if ! xcode-select -p >/dev/null 2>&1; then
  echo "Not installed: a window will ask to install them. Run this script again when that's done."
  xcode-select --install || true
  read -n 1 -s -r -p "Press any key to close."; exit 1
fi
xcode-select -p

echo "== CMake"
if ! command -v cmake >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then brew install cmake; else
    echo "No CMake and no Homebrew found. Install CMake from cmake.org (the macOS universal .dmg), then run this again."
    read -n 1 -s -r -p "Press any key to close."; exit 1
  fi
fi
cmake --version | head -1

echo "== GitHub's runner"
D="$HOME/actions-runner-ircapture"
mkdir -p "$D" && cd "$D"
if [ ! -x ./config.sh ]; then
  V=$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p' | head -1)
  [ -n "$V" ] || { echo "Couldn't read the runner's latest version from github.com."; read -n 1 -s -r; exit 1; }
  echo "runner $V"
  curl -fL -o runner.tar.gz "https://github.com/actions/runner/releases/download/v$V/actions-runner-osx-x64-$V.tar.gz"
  tar xzf runner.tar.gz && rm runner.tar.gz
fi

if [ ! -f .runner ]; then
  echo
  read -r -p "Paste the registration token from GitHub (Settings > Actions > Runners > New self-hosted runner): " TOKEN
  ./config.sh --url https://github.com/0x5E3/IR-Capture --token "$TOKEN" --name "imac-macos-ircapture" \
    --labels "ircapture-build" --work "_work" --unattended --replace
fi

echo "== Starting it at every login"
./svc.sh install || true
./svc.sh start
./svc.sh status || true
echo
echo "Done. On github.com the runner shows as imac-macos (Idle) under Settings > Actions > Runners."
echo "Keep the iMac from sleeping while builds may run (System Settings > Energy / Battery: prevent sleeping)."
read -n 1 -s -r -p "Press any key to close."
