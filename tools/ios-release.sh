#!/usr/bin/env bash
set -euo pipefail

for name in FIREBASE_IOS_BASE64 IOS_CERTIFICATE_BASE64 IOS_CERTIFICATE_PASSWORD IOS_PROFILE_BASE64 APPLE_TEAM_ID BUILD_NUMBER RUNNER_TEMP; do
  test -n "${!name:-}" || { echo "Missing release secret: $name"; exit 1; }
done
export KEYCHAIN_PATH="$RUNNER_TEMP/famgpslink.keychain-db"
export KEYCHAIN_PASSWORD
KEYCHAIN_PASSWORD="$(openssl rand -hex 24)"
export PROFILE_PATH="$RUNNER_TEMP/family.mobileprovision"
export PROFILE_PLIST="$RUNNER_TEMP/profile.plist"
printf '%s' "$FIREBASE_IOS_BASE64" | base64 --decode > ios/Runner/GoogleService-Info.plist
printf '%s' "$IOS_CERTIFICATE_BASE64" | base64 --decode > "$RUNNER_TEMP/certificate.p12"
printf '%s' "$IOS_PROFILE_BASE64" | base64 --decode > "$PROFILE_PATH"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$RUNNER_TEMP/certificate.p12" -P "$IOS_CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN_PATH" >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null
security list-keychains -d user -s "$KEYCHAIN_PATH" login.keychain-db
security cms -D -i "$PROFILE_PATH" > "$PROFILE_PLIST"
export PROFILE_UUID
PROFILE_UUID="$(/usr/libexec/PlistBuddy -c 'Print :UUID' "$PROFILE_PLIST")"
mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"
cp "$PROFILE_PATH" "$HOME/Library/MobileDevice/Provisioning Profiles/$PROFILE_UUID.mobileprovision"
trap 'security delete-keychain "$KEYCHAIN_PATH" || true; rm -f "$RUNNER_TEMP/certificate.p12" "$PROFILE_PATH" "$PROFILE_PLIST" "$HOME/Library/MobileDevice/Provisioning Profiles/$PROFILE_UUID.mobileprovision"' EXIT

ruby -rxcodeproj -e '
  project = Xcodeproj::Project.open("ios/Runner.xcodeproj")
  project.targets.find { |target| target.name == "Runner" }.build_configurations.each do |configuration|
    configuration.build_settings["DEVELOPMENT_TEAM"] = ENV.fetch("APPLE_TEAM_ID")
    configuration.build_settings["CODE_SIGN_STYLE"] = "Manual"
    configuration.build_settings["CODE_SIGN_IDENTITY"] = "Apple Distribution"
    configuration.build_settings["PROVISIONING_PROFILE_SPECIFIER"] = ENV.fetch("PROFILE_UUID")
  end
  project.save
'
python3 - <<'PY'
import os, plistlib
with open(os.environ['RUNNER_TEMP'] + '/ExportOptions.plist', 'wb') as output:
    plistlib.dump({
        'method': 'app-store-connect', 'teamID': os.environ['APPLE_TEAM_ID'],
        'signingStyle': 'manual', 'signingCertificate': 'Apple Distribution',
        'provisioningProfiles': {'com.famgpslink.famgpslink': os.environ['PROFILE_UUID']},
        'destination': 'export', 'manageAppVersionAndBuildNumber': False,
    }, output)
PY
flutter build ipa --release --build-number="$BUILD_NUMBER" --export-options-plist="$RUNNER_TEMP/ExportOptions.plist"
