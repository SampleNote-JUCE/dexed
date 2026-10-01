#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

BUILD_DIR="${BUILD_DIR:-${PROJECT_DIR}/build-orangepi5}"
JOBS="${JOBS:-3}"
BUILD_STANDALONE="${BUILD_STANDALONE:-ON}"
BUILD_ID="${BUILD_ID:-orangepi5}"
readonly CPU_TUNE="-mcpu=cortex-a76.cortex-a55"

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

if [[ "$(uname -m)" != "aarch64" ]]; then
    die "this script requires an aarch64 userspace; detected $(uname -m)"
fi

command -v apt-get >/dev/null 2>&1 || die "apt-get is required"
command -v cmake >/dev/null 2>&1 || true
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || die "JOBS must be a positive integer"
[[ "$BUILD_STANDALONE" == "ON" || "$BUILD_STANDALONE" == "OFF" ]] || \
    die "BUILD_STANDALONE must be ON or OFF"

if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    case "${ID:-}" in
        debian|ubuntu|armbian) ;;
        *) die "this script supports Debian, Ubuntu, or Armbian; detected ${ID:-unknown}" ;;
    esac
else
    die "cannot identify the operating system"
fi

if [[ "$(id -u)" -eq 0 ]]; then
    APT=(apt-get)
else
    command -v sudo >/dev/null 2>&1 || die "sudo is required when not running as root"
    APT=(sudo apt-get)
fi

packages=(
    build-essential
    cmake
    ninja-build
    pkg-config
    git
    ccache
    libasound2-dev
    libx11-dev
    libxinerama-dev
    libxext-dev
    libfreetype6-dev
    libglu1-mesa-dev
    libjack-dev
    libsndfile1-dev
    xvfb
)

# JUCE's browser support is disabled by Dexed, but the CI build installs the
# WebKit development package. Use whichever package name this distribution has.
if apt-cache show libwebkit2gtk-4.1-dev >/dev/null 2>&1; then
    packages+=(libwebkit2gtk-4.1-dev)
elif apt-cache show libwebkit2gtk-4.0-dev >/dev/null 2>&1; then
    packages+=(libwebkit2gtk-4.0-dev)
fi

printf 'Installing build dependencies...\n'
"${APT[@]}" update
"${APT[@]}" install -y "${packages[@]}"

command -v cmake >/dev/null 2>&1 || die "cmake was not installed"
command -v c++ >/dev/null 2>&1 || die "a C++ compiler was not installed"
command -v ninja >/dev/null 2>&1 || die "ninja was not installed"

cd -- "$PROJECT_DIR"
printf 'Updating Git submodules...\n'
git submodule update --init --recursive

cmake_args=(
    -S .
    -B "$BUILD_DIR"
    -G Ninja
    -DCMAKE_BUILD_TYPE=Release
    "-DBUILD_ID=${BUILD_ID}"
    "-DDEXED_SKIP_STANDALONE=$([[ "$BUILD_STANDALONE" == "ON" ]] && printf OFF || printf ON)"
    -DDEXED_SKIP_CLAP=ON
    -DJUCE_COPY_PLUGIN_AFTER_BUILD=FALSE
    "-DCMAKE_C_FLAGS_RELEASE=-O3 -DNDEBUG ${CPU_TUNE}"
    "-DCMAKE_CXX_FLAGS_RELEASE=-O3 -DNDEBUG ${CPU_TUNE}"
)

printf 'Configuring Release build in %s...\n' "$BUILD_DIR"
cmake "${cmake_args[@]}"

printf 'Building with %s parallel jobs...\n' "$JOBS"
cmake --build "$BUILD_DIR" --parallel "$JOBS"

compile_commands="${BUILD_DIR}/compile_commands.json"
[[ -f "$compile_commands" ]] || die "CMake did not generate compile_commands.json"
for flag in "$CPU_TUNE" '-O3' '-flto'; do
    grep -F -- "$flag" "$compile_commands" >/dev/null || \
        die "expected compiler flag was not found in compile_commands.json: $flag"
done

artefacts="${BUILD_DIR}/Source/Dexed_artefacts/Release"
printf '\nBuild completed. Generated binaries:\n'
if [[ "$BUILD_STANDALONE" == "ON" ]]; then
    find "${artefacts}/Standalone" -maxdepth 1 -type f -executable -print 2>/dev/null || \
        printf '  standalone executable not found under %s\n' "${artefacts}/Standalone"
fi
if [[ -d "${artefacts}/VST3/Dexed.vst3" ]]; then
    printf '  %s\n' "${artefacts}/VST3/Dexed.vst3"
else
    printf '  VST3 plugin not found under %s/VST3\n' "$artefacts"
fi

printf '\nVerified compiler flags: %s, -O3, -flto\n' "$CPU_TUNE"
