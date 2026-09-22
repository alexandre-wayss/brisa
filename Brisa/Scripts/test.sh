#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
build_dir="${project_dir}/build/tests"
mkdir -p "${build_dir}"

# Every app source except the entry point, plus the tests and their runner.
source_files=("${project_dir}/Sources/"*.swift(N))
source_files=(${source_files:#*/Main.swift})
test_files=("${project_dir}/Tests/"*.swift)

swiftc -parse-as-library "${source_files[@]}" "${test_files[@]}" \
  -o "${build_dir}/BrisaTests" \
  -module-cache-path "${project_dir}/build/ModuleCache" \
  -framework SwiftUI \
  -framework AVFoundation \
  -framework AppKit \
  -framework Carbon \
  -framework UserNotifications \
  -target arm64-apple-macosx14.0 \
  -suppress-warnings

"${build_dir}/BrisaTests"
