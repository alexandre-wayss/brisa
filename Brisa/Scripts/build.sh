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

# Shortcuts and Focus filters only talk to apps signed by a developer team. Use BRISA_SIGN_IDENTITY,
# else the first Developer ID or Apple Development certificate in the keychain, else an ad-hoc signature.
sign_identity="${BRISA_SIGN_IDENTITY:-}"
if [[ -z "${sign_identity}" ]]; then
  identities="$(security find-identity -v -p codesigning 2>/dev/null)"
  sign_identity="$(print -r -- "${identities}" | grep -m1 '"Developer ID Application' | sed -E 's/.*"(.*)"/\1/' || true)"
  [[ -z "${sign_identity}" ]] && sign_identity="$(print -r -- "${identities}" | grep -m1 '"Apple Development' | sed -E 's/.*"(.*)"/\1/' || true)"
fi

source_files=("${project_dir}/Sources/"*.swift)
deployment_target="14.0"
target_triple="arm64-apple-macosx${deployment_target}"
intents_dir="${project_dir}/build/AppIntents"
mkdir -p "${intents_dir}"

# The Shortcuts app finds Brisa's actions through Metadata.appintents, which Xcode normally generates.
# The compiler records the App Intents types it sees, then Apple's processor turns that into the metadata.
print -l '["AnyResolverProviding","AppEntity","AppEnum","AppIntent","AppIntentsPackage","AppShortcutProviding","AppShortcutsProvider","DynamicOptionsProvider","EntityQuery","IntentValueQuery","Resolver","TransientEntity","_IntentValueRepresentable"]' > "${intents_dir}/protocols.json"

swiftc -O -parse-as-library -wmo "${source_files[@]}" \
  -o "${output_dir}/Contents/MacOS/Brisa" \
  -module-name Brisa \
  -module-cache-path "${project_dir}/build/ModuleCache" \
  -emit-const-values-path "${intents_dir}/Brisa.swiftconstvalues" \
  -Xfrontend -const-gather-protocols-file -Xfrontend "${intents_dir}/protocols.json" \
  -framework SwiftUI \
  -framework AVFoundation \
  -framework AppKit \
  -framework AppIntents \
  -framework Carbon \
  -framework UserNotifications \
  -target "${target_triple}"

# Without a team signature macOS refuses to connect, so leave the actions out rather than show broken ones.
if [[ -n "${sign_identity}" ]]; then
  print -l "${source_files[@]}" > "${intents_dir}/sources.txt"
  print -l "${intents_dir}/Brisa.swiftconstvalues" > "${intents_dir}/constvalues.txt"
  : > "${intents_dir}/empty.txt"
  xcrun appintentsmetadataprocessor \
    --toolchain-dir "$(dirname "$(dirname "$(dirname "$(xcrun --find swiftc)")")")" \
    --module-name Brisa \
    --sdk-root "$(xcrun --sdk macosx --show-sdk-path)" \
    --xcode-version "$(xcodebuild -version | awk '/Build version/ { print $3 }')" \
    --platform-family macOS \
    --deployment-target "${deployment_target}" \
    --bundle-identifier local.brisa.ambient \
    --output "${output_dir}/Contents/Resources" \
    --target-triple "${target_triple/macosx/macos}" \
    --binary-file "${output_dir}/Contents/MacOS/Brisa" \
    --source-file-list "${intents_dir}/sources.txt" \
    --metadata-file-list "${intents_dir}/empty.txt" \
    --static-metadata-file-list "${intents_dir}/empty.txt" \
    --swift-const-vals-list "${intents_dir}/constvalues.txt" \
    --compile-time-extraction \
    --deployment-aware-processing \
    --no-app-shortcuts-localization \
    --force
fi

cp "${project_dir}/Info.plist" "${output_dir}/Contents/Info.plist"
cp -R "${project_dir}/Resources/Audio" "${output_dir}/Contents/Resources/Audio"
cp "${project_dir}/Resources/CREDITOS-AUDIO.md" "${output_dir}/Contents/Resources/CREDITOS-AUDIO.md"
cp "${project_dir}/Assets/Brisa.icns" "${output_dir}/Contents/Resources/Brisa.icns"

# Strip extended attributes (Finder info, provenance) that codesign rejects.
clean_app="$(mktemp -d)/Brisa.app"
ditto --norsrc --noextattr --noacl "${output_dir}" "${clean_app}"
rm -rf "${output_dir}"
ditto --norsrc --noextattr --noacl "${clean_app}" "${output_dir}"
rm -rf "${clean_app:h}"
xattr -cr "${output_dir}"
if [[ -n "${sign_identity}" ]]; then
  print "Assinando com: ${sign_identity}"
  codesign --force --sign "${sign_identity}" --options runtime --identifier local.brisa.ambient "${output_dir}"
else
  print "Nenhum certificado encontrado: assinatura ad-hoc, sem Atalhos nem filtros de Foco neste build."
  codesign --force --sign - --identifier local.brisa.ambient "${output_dir}"
fi
codesign --verify --deep --strict "${output_dir}"
print "Build concluído: ${output_dir}"
