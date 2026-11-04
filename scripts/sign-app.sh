#!/bin/bash
set -euo pipefail

app_path="${1:?Usage: sign-app.sh /path/to/App.app}"
signing_identity="${PRESS_IF_CODESIGN_IDENTITY:-}"

if [[ -z "$signing_identity" ]]; then
    identity_listing="$(security find-identity -v -p codesigning)"
    identity_pattern='([[:xdigit:]]{40}) "Apple Development:'
    development_identities=()
    while IFS= read -r line; do
        if [[ "$line" =~ $identity_pattern ]]; then
            development_identities+=("${BASH_REMATCH[1]}")
        fi
    done <<< "$identity_listing"
    if [[ ${#development_identities[@]} -ne 1 ]]; then
        printf '%s\n' 'Choose a stable signing certificate with PRESS_IF_CODESIGN_IDENTITY. Run security find-identity -v -p codesigning to list certificates.' >&2
        printf '%s\n' 'For an intentional ad hoc build, set PRESS_IF_CODESIGN_IDENTITY=-. Its macOS privacy permissions may become invalid after the next rebuild.' >&2
        exit 1
    fi
    signing_identity="${development_identities[0]}"
fi

if [[ "$signing_identity" == '-' ]]; then
    printf '%s\n' 'Ad hoc signing selected: rebuilding can invalidate Accessibility and Screen Recording permissions.' >&2
fi

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist")"
codesign --force --sign "$signing_identity" --timestamp=none --identifier "$bundle_id" "$app_path"
codesign --verify --deep --strict "$app_path"
