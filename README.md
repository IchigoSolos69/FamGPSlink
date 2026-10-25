# FamGPSlink

An invitation-only location-sharing app for a small family, built for **Android and iPhone**. Members share their latest location, control their own sharing, and keep a remembered profile on each installation. The owner approves devices, manages private connections, and can replace their own shared GPS location with a manual pin.

Flutter provides the interface. Native Kotlin and Swift components collect and upload locations when the Flutter interface is suspended, subject to phone restrictions. Firebase Authentication and Realtime Database provide identity and access control; MapLibre and OpenFreeMap provide maps.

**Source version:** `1.1.1+4`. **Status:** family pilot. Android builds, iOS compilation/IPA packaging, and automated tests have passed. Physical background reliability and the full 24-hour battery pilots remain unverified. See [Validation](docs/VALIDATION.md) and [Pilot checklist](docs/PILOT.md).

## Contents

- [Features and scope](#features-and-scope)
- [Using the app](#using-the-app)
- [Tracking and offline behavior](#tracking-and-offline-behavior)
- [Architecture and repository](#architecture-and-repository)
- [Development setup](#development-setup)
- [Firebase setup](#firebase-setup)
- [Database model and security](#database-model-and-security)
- [Android installation](#android-installation)
- [iPhone installation and renewal](#iphone-installation-and-renewal)
- [GitHub Actions and signing](#github-actions-and-signing)
- [Testing and pilot acceptance](#testing-and-pilot-acceptance)
- [Troubleshooting](#troubleshooting)
- [Operations, costs, and limits](#operations-costs-and-limits)

## Features and scope

| Feature | Behavior |
| --- | --- |
| Family map and member list | Latest shared pin, name, measurement age, and GPS accuracy when available. Locations older than 15 minutes are marked stale. |
| Invitation-only access | Anonymous member accounts cannot read family data before owner approval. Pairing uses an eight-character code. |
| Remembered profiles | Authentication persists; a random installation ID is kept in secure storage. Reopening does not repeat profile creation. |
| Opt-in sharing | Each approved member enables sharing themselves. Pausing removes their shared pin. |
| Background tracking | Android foreground service and iOS Core Location collectors upload independently of the Flutter screen. |
| Private connections | A private member sees only the owner and themselves. Only the owner can see that private member's profile and pin. |
| Owner manual location | The owner selects a map pin for their own shared location; GPS collection stops while the override is active. |
| Profile recovery | A replacement installation can be linked to an existing profile while revoking the previous installation. |
| Offline handling | One encrypted pending fix per phone, backoff retries, and protection against older samples overwriting newer locations. |
| Permission guidance | Location, precision, background access, GPS and power status, plus a Resume tracking action. |

Version one supports **one family and up to ten profiles, including the owner**. The profile limit is enforced in owner administration, not by a server-side count constraint. QR pairing is not implemented.

Location history, route replay, geofences, alerts, chat, emergency features, address search, SMS authentication, and paid server functions are outside this version. Tracking is best effort, with no uninterrupted-service or fixed-precision guarantee.

## Using the app

### Owner and regular members

1. Install a Firebase-configured build using the platform instructions below.
2. On the owner phone, choose **Family owner sign-in** and use the preconfigured Firebase email/password account. The first person opening the app cannot claim ownership.
3. On another phone, choose a profile name and give the displayed pairing code to the owner.
4. The owner opens **Settings → Family administration**, verifies the code with that person, and approves the device.
5. On the approved phone, allow foreground location, then background/Always access. Enable precise location if desired and available.
6. Enable **Share my location**. Check for a fresh pin on another permitted phone, then test with the sharing phone locked.

Regular members see the owner and other regular family profiles. Reopening restores the existing profile. A reinstall or replacement may require recovery rather than creating a duplicate profile.

### Private connections

When approving a **new** profile, select **Private connection (only you)** before confirming the pairing code.

| Viewer | Profiles and shared locations available |
| --- | --- |
| Owner | All approved family and private profiles |
| Regular family member | Owner and regular family profiles |
| Private connection | Owner and their own profile only |
| Pending/unapproved installation | No family profiles or locations |

Private members' settings explain their audience; sharing remains opt-in. Private connections cannot see each other. Visibility is fixed at approval: recovery preserves it, while changing the audience requires removing the profile and pairing again. Database rules enforce these restrictions even for guessed record paths.

### Owner manual pin

Open **Settings → My shared location**, tap the map, and choose **Share this pin**.

- Saving atomically publishes the coordinates, enables sharing, and activates the private override.
- Permitted members see a normal pin without a manual-location label or invented GPS accuracy. Its initial timestamps are the actual save time.
- The override persists through restart until GPS is restored. Pausing removes the visible pin but retains the selection; resuming republishes it with its original selection time and a new publication time.
- Automatic collection and pending uploads stop. Rules reject automatic writes over the active manual pin; no underlying real GPS location is stored during the override.
- **Restore GPS sharing** obtains a fresh native fix before atomically clearing the override. Permission, signal, network, or competing-settings failures retain the override and show an error.

### Recovery and removal

On a replacement member phone, create a pairing request and let the owner choose **Recover [name]**. The stable profile ID, name, and visibility remain; the previous authentication binding and pin are removed. Sharing starts off on the replacement phone until that person opts in.

Remove a member through **Family administration** to delete their profile/state and revoke access. Recover the owner through email sign-in/password reset. The owner is one trusted Firebase account: another installation signed into that account is not individually revoked. Keep owner credentials private.

## Tracking and offline behavior

| Condition | Android | iPhone |
| --- | --- | --- |
| Moving | High accuracy; targets about 60 seconds with a 50-metre distance filter. | Best accuracy and a 50-metre filter; uploads target about 60 seconds when fixes arrive. |
| Stationary | After about three minutes without motion: balanced power, about five minutes, no minimum distance. | Reduced accuracy; uploads target about five minutes when fixes arrive. Automatic pausing can create longer gaps. |
| Background | Foreground service with required notification; boot receiver attempts restart when sharing was requested and permissions allow. | Core Location background delivery and significant-change monitoring within iOS limits. |
| Restrictions | Battery restrictions, force-stop, denied permissions, or disabled GPS can stop/delay updates. | Force-quit, permission changes, power saving, and OS suspension can stop/delay updates. |

These are targets, not heartbeat guarantees. Stationary pins may age even when the phone is online. The app preserves actual measurement times instead of making old points look freshly measured. Accuracy depends on the phone, permission precision, signal, and surroundings. See [Android battery guidance](https://developer.android.com/develop/sensors-and-location/location/battery) and [Apple background-location guidance](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background).

Family roster/location listeners attach only while the map is visible and the app is foregrounded. Own-control listeners and native tracking have separate lifecycles.

While offline, Android Keystore-backed encryption or iOS Keychain protects a single newest pending fix. One transaction uploads at a time; retries back off from five seconds to five minutes. Identity changes clear pending data, and control revisions invalidate fixes from earlier sharing/override states. Uploads check identity, revision, sharing state, and measurement time.

## Architecture and repository

```text
Flutter screens and FamilyController
  ├─ Firebase Auth: anonymous members / email-password owner
  ├─ Realtime Database: approvals, profiles, controls, latest pins
  ├─ MapLibre: OpenFreeMap map style and attribution
  └─ MethodChannel: com.famgpslink/location
       ├─ Android: Kotlin foreground service + Fused Location Provider
       └─ iOS: Swift Core Location + one-shot fresh-fix requests
```

| Path | Purpose |
| --- | --- |
| `lib/main.dart` | Firebase startup, app lifecycle, retryable startup errors |
| `lib/screens.dart` | Onboarding, map, settings, administration, manual-pin UI |
| `lib/family_controller.dart` | Sessions, scoped subscriptions, approval/recovery, sharing transactions |
| `lib/models.dart` | Data models, secure random codes, location age/stale calculations |
| `lib/location_bridge.dart` | Flutter/native method channel |
| `android/app/src/main/kotlin/com/famgpslink/famgpslink/` | MainActivity, LocationService, encrypted FixStore, BootReceiver |
| `ios/Runner/AppDelegate.swift` | Native tracker, fresh GPS requests, pending-fix Keychain storage |
| `tools/write-rules.mjs` / `database.rules.json` | Maintained rule definitions / generated deployment file |
| `tools/bootstrap-owner.mjs` | Trusted one-time owner bootstrap |
| `tools/migrate-visibility.mjs` | Dry-run/apply legacy visibility migration |
| `tools/install-android.ps1` | Windows JDK/Android SDK setup helper |
| `tools/install-ndk.ps1` | Workspace-specific NDK helper; inspect its hardcoded D: paths first |
| `tools/ios-release.sh` | Signed macOS IPA export using CI signing material |
| `tools/create-icons.mjs` | App icon generation |
| `test/` / `tests/` | Flutter tests / database emulator security tests |
| `.github/workflows/` | Checks, configured pilot builds, unsigned iPhone builds |
| `docs/` | iPhone guide, validation record, physical-device pilot |

Dependencies include `firebase_core`, `firebase_auth`, `firebase_database`, `flutter_secure_storage`, and `maplibre_gl`. Native code shares the default Firebase app/auth session with FlutterFire. The map style is `https://tiles.openfreemap.org/styles/bright`; retain provider/OpenStreetMap attribution. Tiles are served separately from Firebase; offline map downloads are not implemented.

## Development setup

| Requirement | Version used by the project |
| --- | --- |
| Flutter / Dart | Flutter **3.47.7**, Dart **3.13.5**; see pubspec and CI |
| Android | JDK **21**, SDK **36**, NDK **28.2.13676358**; minimum **Android 8.0 / API 26** |
| iPhone | Minimum **iOS 15**; Xcode on macOS. CI uses `macos-26`. |
| Backend tooling/tests | Node **24.12+**, npm, JDK 21; pinned `package-lock.json` |

Install the toolchain, then:

```powershell
git clone https://github.com/IchigoSolos69/FamGPSlink.git
Set-Location FamGPSlink
flutter doctor -v
flutter pub get
npm ci
flutter analyze
flutter test
npm test
```

`npm test` starts the local database emulator for **demo-famgpslink**, not the live family database. Put JDK on PATH or configure JAVA_HOME. Emulator configuration uses port 9000 for Database and 9099 for Authentication; the test script starts only Database.

Configure Firebase before building a usable family app. A build without native configuration cannot join the family.

```powershell
flutter build apk --debug
# With a connected Android phone:
flutter run
```

Windows cannot compile native iPhone apps. On a configured Mac, `flutter build ios --release --no-codesign` compiles an unsigned device app; the sideload workflow also packages an IPA.

### Existing Windows workspace

These paths describe the original PC, not portable prerequisites:

| Resource | Local path |
| --- | --- |
| Checkout | `C:\Users\Adi\Documents\GitHub\FamGPSlink` |
| Flutter | `.tooling/flutter` |
| JDK / optional local Node | `.tooling/java` / `.tooling/node` |
| Android SDK | `D:\FamGPSlink-tooling\android-sdk` |
| Generated build junction | `D:\FamGPSlink-tooling\build` |
| Gradle cache | `D:\FamGPSlink-tooling\gradle-cache` |
| Verified iPhone build files | `.tooling/ios-1.1.1-build1006/` |
| SideStore setup files | `.tooling/SideStore-setup/` |

Tools/configuration/build output are ignored and absent from a fresh clone. On this PC, use `.\.tooling\flutter\bin\flutter.bat` if Flutter is not on PATH; set GRADLE_USER_HOME to the cache above to reuse it. The Android setup helper assumes Flutter already exists in `.tooling/flutter`; install the NDK through your SDK manager as needed. Do not copy the D: drive assumptions blindly.

## Firebase setup

The setup record identifies project **famgpslink**, database **famgpslink-default-rtdb** in **Singapore (`asia-southeast1`)**, and Android/iOS identifier **`com.famgpslink.famgpslink`**. `.firebaserc` selects this project. Earlier validation confirmed owner bootstrap, enabled sign-in providers, and deployed locked rules; this README is not a live health check.

### New setup or recovery reference

1. Use Firebase **Spark** and keep billing disabled. Enable **Anonymous** and **Email/Password** Authentication. Do not enable automatic deletion of anonymous accounts used for persistent profiles.
2. Create a **Realtime Database** in locked mode. Firestore and Cloud Functions are not used.
3. Register both native applications and download their configurations:
   - `android/app/google-services.json`
   - `ios/Runner/GoogleService-Info.plist`
4. Create the recoverable owner email/password user in the Firebase console. This family's configured email is `adimaitre56@gmail.com`; use the appropriate account for a separate deployment. Choose the password privately.
5. Authenticate the pinned CLI and deploy rules:

   ```powershell
   npm ci
   npx firebase login
   npx firebase deploy --only database --project famgpslink
   ```

   Complete browser authorization locally. Replace any authorization-code placeholder with the actual code; do not type angle-bracket placeholders literally into PowerShell or post codes in chat.
6. Bootstrap **once**, using a CLI account with project administration access:

   ```powershell
   npm run owner:bootstrap -- --cli famgpslink https://famgpslink-default-rtdb.asia-southeast1.firebasedatabase.app adimaitre56@gmail.com "Adi"
   ```

   This finds the existing owner user and creates trusted configuration, the stable owner profile, its binding, and sharing-off state. It refuses to overwrite an existing family. Reopening/signing into an existing family does not require another bootstrap.
7. Build/install the configured app, sign in as owner, and approve members by pairing code.

Without `--cli`, bootstrap supports Admin SDK application-default credentials. If using GOOGLE_APPLICATION_CREDENTIALS, point it to an administrator credential outside the repository. Neither that credential nor a CLI token belongs in the mobile app or client-config CI secrets. CLI bootstrap uses its local session in memory and never needs the owner password.

Native client configs identify the backend but do not grant administrator access; database rules remain the security boundary. Never deploy public/test rules as a setup workaround. The sideload workflow explicitly checks this family's project/bundle/database identifiers: a fork targeting another backend must update those checks, configs, and `.firebaserc`.

### Existing backend visibility migration

Before deploying private-connection rules over legacy profiles, migrate missing visibility fields. Check the dry run before applying:

```powershell
node tools/migrate-visibility.mjs --cli famgpslink https://famgpslink-default-rtdb.asia-southeast1.firebasedatabase.app
node tools/migrate-visibility.mjs --cli --apply famgpslink https://famgpslink-default-rtdb.asia-southeast1.firebasedatabase.app
```

The migration adds `visibility: family` to legacy profiles, validates the owner, and preserves existing visibility, bindings, and locations. Upgrade all family phones: older unrestricted roster reads are rejected by private-connection rules.

## Database model and security

```text
config/
  ownerUid, ownerMemberId
pairingRequests/{authUid}/
  name, installationId, code, createdAt
family/
  bindings/{authUid}: memberId
  members/{memberId}/
    name, authUid, installationId, active, visibility
  states/{memberId}/
    control/
      sharingEnabled, overrideActive, revision
      manual/                     # Present during the owner's override
        latitude, longitude, setAt
    location/                     # Absent while sharing is off
      latitude, longitude, accuracy?, measuredAt, publishedAt
```

Times are epoch milliseconds. `measuredAt` is the fix time or manual selection time; `publishedAt` is the server publication time. Manual pins omit accuracy. Stable member IDs are separate from authentication UIDs and random installation IDs; no immutable hardware identifier is collected.

Rules enforce:

- Pending users can manage their own pairing request and inspect their own binding, but cannot read family profiles/locations. Trusted owner configuration exposes identifiers, not credentials.
- Members publish only through their active identity/binding and cannot approve devices or escalate privileges.
- Regular roster queries require `orderByChild('visibility').equalTo('family')`. The owner reads the complete roster; private clients directly read themselves and the owner.
- Permitted peers read only a member's location, not private control state. Bound devices access their own state; the trusted owner administers the family.
- Coordinates, fields, timestamps, revisions, sharing/override state, and location ordering are validated. Automatic uploads cannot overwrite an override or replay an older fix.
- Recovery/removal revokes the former binding. Removal deletes the latest member state; the app maintains no route history.

Edit **tools/write-rules.mjs**, regenerate **database.rules.json**, and validate before deploying:

```powershell
npm run rules:generate
npm test
npx firebase deploy --only database --project famgpslink
```

## Android installation

Build a configured APK locally or use **Family pilot builds → android** in GitHub Actions. Local output: `build/app/outputs/flutter-apk/app-debug.apk`.

The recorded **1.1.1 / build 4** APK was also saved as `build/app/outputs/flutter-apk/famgpslink-1.1.1.apk`. Its sharing and stationary-update fixes are documented in [Validation](docs/VALIDATION.md).

1. Transfer the APK and allow installation from that file source when Android asks.
2. Install over the existing app using the same signing key to retain its profile. For USB installation: `adb install -r build/app/outputs/flutter-apk/app-debug.apk`.
3. Complete sign-in/approval, grant location/background permissions, and enable sharing.
4. Review battery restrictions if tracking stops; test both stationary and moving behavior.

The pilot uses a **debug signing key**. Even `build apk --release` currently uses debug signing; production Android signing is not configured. Preserve the pilot key across updates and configure a dedicated release key before store distribution. Avoid uninstalling to resolve a key mismatch without planning profile recovery. After a CI build raises the version code, subsequent upgrades need a sufficiently high code too.

## iPhone installation and renewal

Free sideloading and paid TestFlight are separate routes. Opening an unsigned IPA download alone cannot install it; a signing tool must sign it for the device.

### Obtain the configured IPA

1. Add FIREBASE_IOS_BASE64 to the GitHub **family-pilot** environment as described below.
2. Run **Actions → iPhone sideload build** on a branch containing **1.1.1 or newer** and the intended fixes. The recorded fixed build used `codex/fix-iphone-approval`; verify source rather than assuming a newer run means newer code.
3. Download **famgpslink-iphone-sideload**, extract the ZIP, and inspect **BUILD_INFO.json** for version, build, source commit, and workflow run. Verify the IPA against **SHA256SUMS.txt** when distributing it.
4. Transfer **famgpslink-unsigned.ipa** to iPhone Files. The outer artifact ZIP is not installable.

The recorded verified build is **1.1.1 / iPhone build 1006**, source `2ea49d1015e3e0545e2c9cf7949680d321d6dae1`, in [run 38158016893](https://github.com/IchigoSolos69/FamGPSlink/actions/runs/38158016893). IPA SHA-256: `d75c3c65c276b4df4b760b65cbc633b09c9504eb78fa03dd2858fd02c241a6df`. Artifacts have **14-day retention**; this run is a provenance reference, not a permanent download. Rebuild if its artifact expired. Release mode uses AOT compilation and needs no JIT.

### SideStore: renew on the iPhone

This is the route selected for the family's iPhone 11. Follow the [official prerequisites](https://docs.sidestore.io/docs/installation/prerequisites) and [installation guide](https://docs.sidestore.io/docs/installation/install) for compatibility and downloads:

1. USB-connect the unlocked phone to the PC and accept **Trust This Computer**.
2. Use official [iloader](https://github.com/nab138/iloader/releases) to sign/install SideStore and complete pairing. Enter Apple credentials locally.
3. Trust the developer under **General → VPN & Device Management**; enable **Developer Mode** if requested.
4. Install [LocalDevVPN](https://apps.apple.com/app/localdevvpn/id6755608044), connect Wi-Fi/VPN, and sign into SideStore with the same Apple Account used in iloader.
5. In **My Apps**, refresh SideStore using its expiry counter before importing FamGPSlink with **+**.

Install FamGPSlink directly, not inside LiveContainer, so its native background-location lifecycle can operate.

### Manual and automatic refresh

Free Apple signing expires after **seven days** and normally permits **three active sideloaded apps, including SideStore**. SideStore supports on-device background renewal; expiry still applies. See the [SideStore FAQ](https://docs.sidestore.io/docs/faq).

For manual renewal, connect Wi-Fi/LocalDevVPN, open **My Apps**, and tap the expiry counters for **FamGPSlink and SideStore**. SideStore may briefly close; confirm both counters return to about seven days.

Enable SideStore's automatic-refresh option where offered and **Settings → General → Background App Refresh → SideStore**. Keep Wi-Fi/VPN available and avoid force-closing SideStore. Scheduling is best effort: check expiry periodically and manually renew at two days remaining. [Background App Refresh guidance](https://support.apple.com/en-euro/118408). [Low Power Mode disables Background App Refresh](https://support.apple.com/en-euro/101604).

Routine renewal needs no PC; expired SideStore or invalid pairing can require iloader repair. Pairing may need replacement after an iOS update/reset. Renewal re-signs the installed app: it does not install new FamGPSlink code or refresh a GPS pin by itself.

### AltStore and paid alternatives

[The detailed AltStore guide](docs/IOS_SIDELOAD.md) covers Windows/AltServer. AltStore Classic has the same free-signing expiry and requires AltServer connectivity for renewal. Use the same signing Apple Account and update over the existing app to retain stored identity where possible; a changed identity can still require owner-approved recovery.

A Mac with Xcode/free Personal Team is another development route with periodic renewal. TestFlight requires membership and the signed CI workflow below. [Apple Developer Program](https://developer.apple.com/programs/) membership currently costs US$99 per year or local pricing; [TestFlight builds expire after 90 days](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/). Paid membership is not required for the SideStore pilot.

## GitHub Actions and signing

| Workflow | Trigger and output |
| --- | --- |
| `checks.yml` — Checks | Push, PR, or manual. Formatting, Flutter analysis/tests, rule consistency, emulator tests, unconfigured Android APK, unsigned iOS debug compilation. |
| `ios-sideload.yml` — iPhone sideload build | Manual. Configured release IPA without Apple signing, BUILD_INFO.json, SHA256SUMS.txt. Requires FIREBASE_IOS_BASE64. |
| `family-pilot.yml` — Family pilot builds | Manual Android/iOS/both selection. Configured Android debug APK or signed iOS IPA. TestFlight upload checkbox is off by default. |

The **Checks** APK is deliberately unconfigured and cannot join the family. Install configured pilot artifacts. Artifacts are not permanent GitHub Releases.

Create **Settings → Environments → family-pilot** and add secrets for the selected job:

| Secret | Required for | Value |
| --- | --- | --- |
| `FIREBASE_ANDROID_BASE64` | Configured Android | Base64 of google-services.json |
| `ANDROID_DEBUG_KEYSTORE_BASE64` | Configured Android | Base64 of the original pilot debug keystore, preserving upgrade compatibility |
| `FIREBASE_IOS_BASE64` | Configured iOS, either workflow | Base64 of GoogleService-Info.plist |
| `IOS_CERTIFICATE_BASE64` | Signed iOS | Distribution certificate and private key exported as .p12, base64 encoded |
| `IOS_CERTIFICATE_PASSWORD` | Signed iOS | P12 export password |
| `IOS_PROFILE_BASE64` | Signed iOS | Base64 App Store distribution profile for the bundle ID, including Keychain capability |
| `APPLE_TEAM_ID` | Signed iOS | Apple Developer team ID |
| `APPSTORE_KEY_BASE64` | TestFlight upload | Base64 App Store Connect API private key (.p8) |
| `APPSTORE_KEY_ID` | TestFlight upload | API key ID |
| `APPSTORE_ISSUER_ID` | TestFlight upload | API issuer UUID |

Copy a client config's base64 locally and paste directly into its GitHub secret:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path 'ios/Runner/GoogleService-Info.plist').Path)) | Set-Clipboard
# For Android, use android/app/google-services.json instead.
```

The pilot debug keystore normally uses alias `androiddebugkey` and standard debug passwords `android`; it is not a store-distribution key. Never commit keys, certificates, passwords, pairing records, service accounts, or API private keys. Base64 is not encryption.

For TestFlight, create the bundle/app record in App Store Connect first. The macOS job imports signing material into a temporary keychain and exports an IPA; upload requires the checkbox and all three API secrets. External testers may require beta review. Renew signing materials and upload new builds before expiry. Review cloud Mac allowance and spending controls before builds.

## Testing and pilot acceptance

```powershell
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
npm ci
npm run rules:generate
git diff --exit-code -- database.rules.json
npm test
```

Recorded version 1.1.1 validation passed **20 Flutter tests** and **25 database emulator tests**, configured Android compilation, and unsigned release iOS packaging. Coverage includes outsiders/pending users, pairing isolation, impersonation, escalation, private audiences, constrained queries, revoked bindings, location validation, override races, stale replay, cold-cache transactions, repeated sharing enable, and recovery/removal.

These are prior results, not a claim tests were rerun for a documentation update. See [Validation and artifact checksums](docs/VALIDATION.md).

Before wider access, complete [docs/PILOT.md](docs/PILOT.md) on physical Android and iPhone devices: locked screens, stationary/moving use, offline reconnect, power saving, permission changes, reboot/force-stop, recovery, private audiences, override persistence, and restore failures. Run a 24-hour baseline/sharing comparison on each platform; record battery drain, accuracy, update delays, and Firebase traffic. Investigate incremental battery drain above five percentage points/day before expanding access; this is a tuning target, not a guarantee.

## Troubleshooting

| Symptom | Check and next action |
| --- | --- |
| “This build is not connected to your family yet” / startup failure | Confirm native Firebase config and backend match; avoid the unconfigured Checks APK. Check internet/auth providers, use Retry connection, and preserve the safe error code. Not every startup failure means missing configuration. |
| “Access has changed. Your device may need approval again.” | Check installed version first. Version 1.0.1 reads an unrestricted roster rejected by privacy rules. Update to 1.1.1 or later over the existing app. For actual revocation/reinstallation, use recovery. |
| “Sharing could not be updated. Try again.” despite permissions | Version 1.1.0 aborted transactions on an initially empty native cache. Update to 1.1.1 or later. Repeated permission/approval changes cannot update old code; preserve any new safe error code. |
| Newer iPhone build still has the bug | Verify BUILD_INFO.json source/version. Runs 38153997532 and 38157053654 compiled older code; recorded fixed run: 38158016893. Build number alone does not prove a fix is present. |
| Stationary Android pin is an hour old | Version 1.1.1 removes the stationary 50-metre filter. Check sharing, permissions, GPS, battery restrictions, and Resume tracking. Actual cadence still depends on Android scheduling. |
| iPhone stops sharing after several days | Check SideStore signing expiry as well as Always location access. Renew, open FamGPSlink, and confirm a fresh pin on another phone. |
| Old location after reconnect | Check measurement time; a new upload timestamp does not mean a fresh GPS fix. Only one newest pending sample is kept. |
| Owner pin does not follow the phone | Check My shared location: the manual override persists until Restore GPS sharing succeeds. |
| iPhone developer-trust block | Review General → VPN & Device Management and Developer Mode; follow the installer instructions on the phone. |
| SideStore VPN route / DeviceEndpointNotInitialized error | Check Wi-Fi, LocalDevVPN, SideStore Local Network permission, compatible SideStore version, and pairing configuration. Restart apps/phone before pairing repair. See [connection troubleshooting](https://docs.sidestore.io/docs/troubleshooting/common-issues). |
| Anisette HTTP 502 | Selected metadata server failure; check provider settings/status. This is separate from Firebase and family approval. |
| SideStore login 80045 / -80045 | Apple/anisette failures are [reported upstream](https://github.com/SideStore/SideStore/issues/1652). A reported workaround disables On-Device Anisette, restarts, selects Jkcoxson Mac (`https://mac-ani.jkcoxson.com/`), and restarts/retries. Not guaranteed; check current guidance and keep credentials local. |
| SideStore/app expired | Repair/re-sign through the installer if it cannot open. Preserve FamGPSlink where possible; deleting it may require profile recovery. |
| Map tiles fail | Check network/provider availability and use the member list. Tile failure is separate from Firebase approval. |

Signing, VPN, and anisette problems belong to the sideloading toolchain. Changing Firebase rules or reapproving a member does not repair Apple signing. Avoid deleting the app or resetting all pairing/authentication state as a first step.

## Operations, costs, and limits

- **Backend:** Spark currently includes **100 simultaneous Realtime Database connections**, **1 GB stored**, and **10 GB downloaded/month**. Keep billing disabled; monitor daily during the pilot, then regularly with quota headroom. See [Firebase pricing](https://firebase.google.com/pricing).
- **Maps:** [OpenFreeMap](https://openfreemap.org/) supplies maps without a paid API key. Retain attribution; availability and tile traffic are separate from Firebase quotas.
- **Failures:** quota/network errors must leave unavailable/offline or truthfully stale data. No application code upgrades billing automatically.
- **Identity:** protect the recoverable owner account. Installation identity is remembered, not a permanent hardware fingerprint. Reinstalling does not bypass approval.
- **Retention:** only the latest shared location and one local pending fix are used; no app-managed route history. Firebase project administrators remain trusted and have administrative access.
- **Distribution:** free iPhone signing needs seven-day renewal; automation is best effort. TestFlight builds last 90 days. Membership and cloud Mac compute are separate from free Firebase/maps usage.
- **Maintenance:** regenerate/test rules, preserve signing keys for upgrades, verify manifests/checksums and version codes, and review upstream compatibility before SDK upgrades.
- **Known validation limits:** the recorded audit had seven transitive development-tool findings (four moderate, three high), not mobile-app dependencies. See Validation and rerun the audit when updating tooling. Full physical-device pilots remain outstanding.

No license file is committed. This is a private family pilot; production signing and broader distribution still require release work.
