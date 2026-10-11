# Validation record

Local validation on 11 October 2026 (Windows):

| Check | Result |
| --- | --- |
| Dart formatting | Passed; no remaining changes |
| Flutter analyzer | Passed; no issues |
| Flutter model/widget/subscription tests | 13 passed, including private approval, audience disclosure, scoped map subscriptions, cache clearing and startup retry |
| Realtime Database emulator security tests | 23 passed, including private profile/location isolation, constrained queries and private device recovery |
| Android native/Flutter debug APK | Built successfully with final source |
| GitHub workflow YAML | All three workflows parsed successfully, including the free-account sideload build |
| Real Firebase backend | Owner binding/control state verified; deployed rules match source; anonymous sign-in works; unapproved family/private-control reads denied |
| iOS native compile / signing | Not run; cloud Mac required for compilation; free-account AltStore signing route now documented |
| Physical background tracking and 24-hour pilots | Not run; requires phones and a configured family backend |

APK: `build/app/outputs/flutter-apk/famgpslink-1.1.0.apk`, 194,242,371 bytes (configured debug build, version code 3). The same APK is also available as `app-debug.apk`.

SHA-256: `0054FA4C64D5CF9252E629FF34FEE8CD4C8E9758343862303865D387FE2F09A7`.

Version 1.1.0 adds private connections selected during owner approval. Normal members receive only the `visibility: family` roster query; private connections read only their own and the owner's profiles. The rules apply the same audience checks to direct location/profile reads, deny private-to-family and family-to-private reads even with known paths, and retain private visibility after device recovery. Sharing remains opt-in. The owner sees both groups; separate private connections cannot see each other. The approval dialog lifecycle was also corrected after the new widget test exposed a controller being disposed during its closing animation.

Two existing live profiles received the legacy `family` visibility default through the trusted, transactional metadata migration. No device bindings or locations were modified, and no private profile was created automatically. The new locked rules were deployed to `famgpslink`; live rule contents, owner identity/control state, anonymous sign-in, and denial of unapproved family/private reads were verified. All family phones must upgrade to 1.1.0 because older versions request an unrestricted roster. Real private pairing and physical background tracking remain pilot checks.

Version 1.0.1 fixes a misleading startup screen: version 1.0.0 treated every initialization failure as an unconfigured build. The new screen preserves the error category/code, omits raw diagnostic payloads and offers a retry that reopens authentication/profile initialization. Tests cover failed first sign-in followed by successful retry, secure-storage failures and disabled sign-in. Owner sign-in now verifies the configured owner after authentication rather than relying on previously loaded metadata. The cause of the reported second-phone failure remains unknown until it retries or supplies its diagnostic code; no phone was attached for USB logs.

The APK is configured for Firebase project `famgpslink`. Realtime Database `famgpslink-default-rtdb` is active in `asia-southeast1` (Singapore), email/password and anonymous Authentication are enabled, both native apps are registered, and their ignored config files are downloaded. The user created the owner account privately; trusted CLI bootstrap linked it to the `owner` profile with sharing disabled. The tested locked database rules are deployed and their contents were compared against source. A temporary anonymous test account validated live sign-in/access isolation and was then removed; no test locations or pairing requests were created. Billing remains disabled. No privileged credentials or owner password are bundled in the app.

The iOS source uses the native Firebase SDK APIs corresponding to the pinned Flutter plugins. The supplied unsigned CI build must still compile it on macOS before a signed pilot is distributed. CI workflows have not been executed remotely.

An additional manual `ios-sideload.yml` workflow now builds a configured release app without Apple signing credentials and packages an unsigned IPA for AltStore. The seven-day refresh instructions are in `docs/IOS_SIDELOAD.md`. This route has not produced a real IPA or been tested on an iPhone; its workflow requires the source to be pushed and `FIREBASE_IOS_BASE64` configured in GitHub first.

The Android build reports upstream FlutterFire plugin warnings about Kotlin Gradle Plugin migration. Compilation succeeds with the pinned Flutter version. Check compatible plugin releases before a future Flutter upgrade.

Development-tool dependency audit reports 7 remaining findings (4 moderate, 3 high), rooted in transitive `@opentelemetry/core`, `braces` and `uuid` dependencies of Firebase tooling. Compatible patched versions of other affected dependencies were pinned. These Node packages are used only for local setup/tests and are not bundled into the mobile app. Major overrides were not forced across incompatible dependency contracts; review upstream fixes before refreshing the toolchain.

The ten-profile pilot limit is enforced by owner administration in the app; database rules enforce identity/access isolation but do not impose a server-side member count. The owner is a recoverable trusted email account; other installations signed into that same owner account are not separately revoked. Member recovery revokes the previous anonymous device identity.
