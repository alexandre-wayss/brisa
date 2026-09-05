#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
output_dir="${project_dir}/build/Brisa.app"

if [[ -e "${output_dir}" ]]; then
  print -u2 "O destino já existe: ${output_dir}"
  print -u2 "Renomeie ou remova esse build antes de continuar."
  exit 1
fi

mkdir -p "${output_dir}/Contents/MacOS" "${output_dir}/Contents/Resources"

swiftc -parse-as-library "${project_dir}/Sources.swift" \
  -o "${output_dir}/Contents/MacOS/Brisa" \
  -module-cache-path "${project_dir}/build/ModuleCache" \
  -framework SwiftUI \
  -framework AVFoundation \
  -framework AppKit \
  -framework Carbon \
  -target arm64-apple-macosx13.0

cp "${project_dir}/Info.plist" "${output_dir}/Contents/Info.plist"
cp -R "${project_dir}/Resources/Audio" "${output_dir}/Contents/Resources/Audio"
cp "${project_dir}/Resources/CREDITOS-AUDIO.md" "${output_dir}/Contents/Resources/CREDITOS-AUDIO.md"
cp "${project_dir}/Assets/Brisa.icns" "${output_dir}/Contents/Resources/Brisa.icns"

xattr -cr "${output_dir}"
codesign --force --sign - --identifier local.brisa.ambient "${output_dir}"
codesign --verify --deep --strict "${output_dir}"
print "Build concluído: ${output_dir}"
