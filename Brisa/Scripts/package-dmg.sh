#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
build_app="${project_dir}/build/Brisa.app"
release_dir="${project_dir}/release"
staging_dir="${release_dir}/dmg-staging"
dmg_path="${release_dir}/Brisa-macOS-arm64.dmg"

if [[ ! -d "${build_app}" ]]; then
  "${script_dir}/build.sh"
fi

if [[ -e "${dmg_path}" || -e "${staging_dir}" ]]; then
  print -u2 "A release já existe em ${release_dir}. Renomeie ou remova os artefatos antes de continuar."
  exit 1
fi

mkdir -p "${staging_dir}"
cp -R "${build_app}" "${staging_dir}/Brisa.app"
ln -s /Applications "${staging_dir}/Applications"
hdiutil create -volname "Brisa" -srcfolder "${staging_dir}" -ov -format UDZO "${dmg_path}"
print "DMG criado: ${dmg_path}"
