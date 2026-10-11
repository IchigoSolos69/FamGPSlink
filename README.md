# FamGPSlink

A private family location app for Android and iPhone. Flutter provides the shared UI; native Kotlin and Swift collectors publish the latest location even when the Flutter UI is suspended, subject to phone restrictions.

Implemented: owner-approved device profiles and recovery, family map and member list, opt-in sharing, permission guidance, native background collection, encrypted single-fix offline buffers, owner-only manual pin controls, Firebase rules/tests, and cloud build workflows. No location history, paid functions, SMS auth, or address lookup.

The local native configs now connect to **`famgpslink`**, with Realtime Database in Singapore. The tested locked rules are deployed, both native apps are registered, email/password and anonymous sign-in are enabled, and the owner account is linked to the stable owner profile. Install the local debug APK and use **Family owner sign-in** with your chosen password. A build without native Firebase configs displays a setup screen. Real battery and background performance must be checked using [the pilot checklist](docs/PILOT.md).

## Requirements and local builds

- Flutter **3.47.7** / Dart **3.13.5**, JDK **21**, Android SDK 36, NDK **28.2.13676358**. Android minimum: **8.0 / API 26**.
- iPhone minimum: **iOS 15**; Xcode on macOS for compilation. The supplied workflow uses a cloud macOS runner.
- Node **24.12+** and JDK 21 for Firebase emulator tests. A project-local Node runtime is also installed under `.tooling/node` for this workspace.

The local Flutter SDK is under `.tooling/flutter`; JDK is under `.tooling/java`. The Android SDK was moved to `D:\FamGPSlink-tooling\android-sdk` because C: lacked room for the NDK. Generated `build/` output is a junction to `D:\FamGPSlink-tooling\build`; the Gradle cache used for the validated build is `D:\FamGPSlink-tooling\gradle-cache` (set `GRADLE_USER_HOME` to reuse it). These tools are ignored and are not part of the app source. On a new Windows machine, install Flutter and run `tools/install-android.ps1` to install Android/JDK tools, or use your existing Android Studio SDK.

```powershell
.\.tooling\flutter\bin\flutter.bat pub get
.\.tooling\flutter\bin\flutter.bat analyze
.\.tooling\flutter\bin\flutter.bat test
.\.tooling\flutter\bin\flutter.bat build apk --debug
```

Debug APK: `build/app/outputs/flutter-apk/app-debug.apk`. With a connected phone, use `flutter run`, or `adb install -r` on the APK. Use the same test signing key for upgrades during the pilot; do not treat the debug-signed APK as a store release.

The latest local pilot is **1.1.0 (build 3)**, saved as `build/app/outputs/flutter-apk/famgpslink-1.1.0.apk`. Install over the existing app to keep the remembered profile. This release adds private connections. **Upgrade every family phone:** the new rules require a constrained roster query; older versions may report changed access until upgraded. Startup failures still show a retry button and a safe error code rather than incorrectly claiming the build has no family configuration.

## Connect your family

The following backend steps have already been completed for this workspace. They are retained as a setup/recovery reference. The bootstrap command refuses to overwrite the configured owner.

1. Use your Firebase project **`famgpslink`** on the **Spark** plan (selected in `.firebaserc`). Keep billing disabled. Enable **Anonymous** and **Email/Password** providers in Authentication. Do not enable automatic anonymous-account deletion for long-lived family profiles.
2. Create a **Realtime Database** in locked mode, preferably in the nearest region (Singapore is suitable for an India-based family). No Firestore or Cloud Functions are required.
3. Register Android application `com.famgpslink.famgpslink` and iOS bundle `com.famgpslink.famgpslink` in that project. Download the native config files:
   - `android/app/google-services.json`
   - `ios/Runner/GoogleService-Info.plist`
   Both are ignored by Git. The iOS build copies its config into the app only when present.
4. Create your owner **email/password user**, **`adimaitre56@gmail.com`**, in Firebase Authentication using the console. Use a password you can recover by email; no owner signup or first-device claim is allowed in the app.
5. Install Firebase setup/test tools with `npm ci`, then deploy the rules:

   ```powershell
   npx firebase login
   npx firebase deploy --only database --project famgpslink
   ```

6. Bootstrap the owner using your trusted Firebase CLI sign-in (your Google account must have administration rights to this project):

   ```powershell
   npm run owner:bootstrap -- --cli famgpslink https://famgpslink-default-rtdb.asia-southeast1.firebasedatabase.app adimaitre56@gmail.com "Adi"
   ```

   The URL above is this family's Singapore database. The script finds the existing owner email user and seeds the locked configuration, stable owner profile, device binding and sharing-off state. It refuses to replace an existing configured family. The password is never passed to the script. The `--cli` option uses the pinned CLI session in memory and does not export credentials. Alternatively, omit `--cli` to use Admin SDK application-default credentials. If using a service-account file, keep it outside this repository and never bundle it in the app; set `GOOGLE_APPLICATION_CREDENTIALS` to its absolute path.
7. Rebuild/install the configured app. Use **Family owner sign-in** on your phone. Family members choose their name once and give you their eight-character pairing code. Verify it with them in **Settings → Family administration**, approve their profile, then let them enable sharing themselves.

No privileged credential is needed after setup. Realtime Database rules enforce all family access checks on the server. Do not switch rules into test/public mode to fix setup failures.

## Everyday behavior and recovery

- **Private connection:** when approving a new pairing request in **Settings → Family administration**, enable **Private connection (only you)** before confirming the code. The person is absent from other family members' profiles, map, member count and location access. Only the owner sees their shared pin; they see only the owner and their own pin. Their settings explain this audience, and sharing starts only when they opt in. The owner still sees normal family members. Private connections cannot see each other.
- **Private recovery:** choose **Recover [name]** for a replacement phone; the existing visibility is retained and the previous device is revoked. Visibility is fixed when the profile is approved. To change it, remove the profile and pair again, rather than silently broadening its audience.
- **Sharing:** allow foreground location first, then Background/Always access. Android shows the required ongoing notification. Approximate permissions work; the member list displays their estimated accuracy in metres. Sharing off removes the public pin.
- **Battery:** moving collection targets about 60 seconds / 50 metres; Android drops to balanced-power 5-minute requests after three minutes without motion. iOS lowers accuracy and uses automatic pausing and significant-change monitoring. Stationary updates are opportunistic: neither OS promises a five-minute heartbeat. Power restrictions or force-stop may require reopening the app.
- **Map:** family listeners attach only while the family map is visible and the app is foregrounded. Per-member private-control listeners are never used to populate the shared map. Accuracy and stale age use the measurement time, not the network upload time.
- **Manual pin:** only the configured owner can open **My shared location**. Saving a pin atomically enables the private override and publishes the chosen point without an accuracy field or manual label. GPS collection and pending uploads are stopped. The private revision prevents queued GPS fixes from winning a later transaction. Override survives restart until you restore GPS.
- **Restore GPS:** a separate native one-shot request obtains a fresh fix before clearing the override. Missing permission, signal, network or a competing settings change leaves the manual pin active.
- **Profile recovery:** reinstalling/changing a member phone creates a new authentication session and pairing request. Approve that request with **Recover [name]**. The stable member ID/name remain; old authentication binding and coordinates are removed atomically. Sharing is off until the recovered phone opts in. Remove a member to revoke their access and delete their last pin.
- **Owner recovery:** use owner email sign-in / password reset. This pilot treats the owner identity as one trusted account; it does not enforce an immutable hardware identity or revoke another installation already signed into the same owner account. Do not share owner credentials.
- **Offline:** native buffers retain one encrypted latest fix using Android Keystore or iOS Keychain. At most one upload transaction is in flight; retries back off to five minutes. Transaction checks reject obsolete revisions, paused/overridden sharing and older measurements. Auth/device changes clear the buffer.

## Data and validation

The database has `config`, `pairingRequests`, and `family/{bindings,members,states}`. Profiles include an immutable `visibility` of `family` or `ownerOnly`. Normal members read the roster using `orderByChild('visibility').equalTo('family')`; only the owner can read the complete roster. Private connections subscribe directly to their own profile and the owner's profile. Rules apply the same audience checks to individual profile and location reads, including guessed paths. A state contains private `control` and audience-readable `location`. Only the active bound device can read its whole state; permitted peers can read only its `location`. Control has `sharingEnabled`, `overrideActive`, a monotonically increasing `revision`, and the chosen manual pin while an override is active (so pausing/resuming sharing retains it). Location has `latitude`, `longitude`, optional `accuracy`, `measuredAt` and `publishedAt`. No route history or underlying real owner location is stored during an override.

For an existing backend, upgrade profile metadata before deploying these rules. `tools/migrate-visibility.mjs` defaults to a dry run; it adds `visibility: family` to legacy profiles while preserving existing audiences, bindings and locations. Run with `--apply` using trusted Firebase CLI sign-in:

```powershell
node tools/migrate-visibility.mjs --cli --apply famgpslink https://famgpslink-default-rtdb.asia-southeast1.firebasedatabase.app
```

Rules are maintained in `tools/write-rules.mjs`; generated `database.rules.json` is the deployable source. After a rule edit, regenerate and run real emulator tests:

```powershell
npm run rules:generate
$env:JAVA_HOME = (Get-ChildItem .tooling/java -Directory | Select-Object -First 1).FullName
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
npm test
```

Tests cover outsider/pending access, pairing isolation, impersonation and escalation, private profile/location isolation and constrained queries, coordinate/timestamp validation, private override reads, upload races, stale replay, audience-preserving recovery and member removal. Flutter tests cover approval controls, audience disclosure, scoped subscriptions, cache clearing, timestamps and shared-pin rendering. Physical-device and 24-hour battery acceptance remain separate requirements in `docs/PILOT.md`.

See [the validation record](docs/VALIDATION.md) for completed checks and outstanding delivery requirements.

## Cloud builds and TestFlight

For iPhone installation **without paid Apple membership**, use the [Windows/AltStore installation guide](docs/IOS_SIDELOAD.md) and the manual **iPhone sideload build** workflow. It packages a configured unsigned release IPA for AltStore to sign on each device. Free installs require refreshing every seven days. The first cloud iOS build and physical tracking pilot remain unverified; no iPhone download exists yet. The TestFlight route below is optional and requires paid membership.

Push this source to your own GitHub repository to use `.github/workflows/checks.yml`. Checks run Flutter analysis/tests, rules tests, an unconfigured Android APK build and an unsigned native iOS compile.

For connected builds, create a GitHub environment named **family-pilot** and add these secrets as single-line base64 values where indicated:

| Secret | Value |
| --- | --- |
| `FIREBASE_ANDROID_BASE64` | Base64 of `google-services.json` |
| `ANDROID_DEBUG_KEYSTORE_BASE64` | Base64 of the same Android debug keystore used for the first pilot APK (`~/.android/debug.keystore`; standard alias/password `androiddebugkey` / `android`) so subsequent APKs can upgrade without reinstalling |
| `FIREBASE_IOS_BASE64` | Base64 of `GoogleService-Info.plist` |
| `IOS_CERTIFICATE_BASE64` | Base64 of exported Apple Distribution certificate **and private key** (`.p12`) |
| `IOS_CERTIFICATE_PASSWORD` | P12 export password |
| `IOS_PROFILE_BASE64` | Base64 of App Store distribution provisioning profile for `com.famgpslink.famgpslink`, including Keychain capability |
| `APPLE_TEAM_ID` | Apple Developer team ID |
| `APPSTORE_KEY_BASE64` | Base64 of App Store Connect API private key (`.p8`), required only for upload |
| `APPSTORE_KEY_ID` | API key ID, required only for upload |
| `APPSTORE_ISSUER_ID` | API issuer UUID, required only for upload |

Run **Family pilot builds** manually, selecting Android/iOS/both. Android produces a configured debug APK. iOS imports signing materials into a temporary keychain and produces a signed IPA. TestFlight upload is a separate checkbox, off by default. The Apple App Store Connect app record must exist for the bundle ID before uploading. Add external family testers; beta review may be required. Renew builds before TestFlight's 90-day expiry and renew certificates/profiles before they expire.

Apple Developer membership and cloud macOS build usage are separate from the free backend. Monitor your CI allowance and keep signing secrets in the environment, not in commits.

## Free-tier operations

Firebase Spark currently includes 100 simultaneous Realtime Database connections, 1 GB stored and 10 GB downloaded/month. This pilot UI supports ten profiles, stores only the latest point, and limits map subscriptions to reduce downloads. Inspect the Firebase Usage tab daily during the pilot and weekly afterwards, with a margin below quota limits. Quota/service failures surface as unavailable/offline or stale locations; no code upgrades your billing plan. OpenFreeMap supplies free map tiles; keep its attribution visible and expect the member list to remain useful if map service is unavailable.

References: [Firebase pricing](https://firebase.google.com/pricing), [OpenFreeMap](https://openfreemap.org/), [Apple background location](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background), [Android battery guidance](https://developer.android.com/develop/sensors-and-location/location/battery), [TestFlight](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/).
