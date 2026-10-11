# iPhone installation without paid Apple membership

Use **AltStore Classic**, its Windows companion **AltServer**, and a free Apple Account. AltStore signs the app for your phone. Free installs expire after seven days and must be refreshed; they are limited to three active sideloaded apps per device. This is a pilot route, with no paid Apple membership required. See [AltStore's free distribution documentation](https://faq.altstore.io/developers/distribute-with-altstore-classic) and [expiration limits](https://faq.altstore.io/altstore-classic/your-altstore).

**Current status:** version **1.1.1** fixes a sharing-save failure after approval: transactions now retry when the native cache is initially empty, and repeated enable attempts preserve the existing pin. Version 1.1.0 build 1003 from [run 38153997532](https://github.com/IchigoSolos69/FamGPSlink/actions/runs/38153997532) contains the earlier approval/map fix but does not contain this sharing fix. The configured 1.1.1 [run 38156375135](https://github.com/IchigoSolos69/FamGPSlink/actions/runs/38156375135) was intentionally cancelled by the user during compilation; no IPA was produced and it was not restarted. When ready, build the latest `codex/fix-iphone-approval` source using the workflow below. Windows cannot compile the native iPhone app; GitHub's Mac runner builds it. Physical background tracking still needs validation. Check your GitHub Actions allowance and spending limit before running a Mac job; free Apple signing does not make cloud compute unlimited.

## 1. Generate the FamGPSlink IPA once

1. Commit and push the app source, including `.github/workflows/ios-sideload.yml`, to your GitHub repository. Keep the ignored Firebase configuration and signing/credential files out of commits.
2. In GitHub, open **Settings → Environments**, create/select **family-pilot**, then **Add environment secret** named **FIREBASE_IOS_BASE64**.
3. In PowerShell, run this exact command from the project folder to copy the configuration's base64 value, then paste it into that GitHub secret's value:

   ```powershell
   Set-Location C:\Users\Adi\Documents\GitHub\FamGPSlink
   [Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path 'ios/Runner/GoogleService-Info.plist').Path)) | Set-Clipboard
   ```

   This is the native client configuration, not an owner password or service-account credential. No Apple signing secrets are needed for this workflow.
4. Open GitHub **Actions → iPhone sideload build → Run workflow**, choose the branch containing the source, and run it. Use this workflow rather than the paid-signing **Family pilot builds** workflow.
5. After a successful run, open its summary and download **famgpslink-iphone-sideload** under **Artifacts**. Extract the downloaded ZIP. Check **BUILD_INFO.json** for version **1.1.1** or later and the intended source commit. Run 38153997532 predates this manifest and the sharing fix. The install file is **famgpslink-unsigned.ipa**; the outer artifact ZIP is not the app. A failed run produces no usable download: inspect the failed build step before proceeding.
6. Transfer the IPA to the iPhone's Files app, for example through your own iCloud Drive. Keep it within your family.

## 2. Install AltStore Classic on each iPhone

Follow the [official Windows instructions](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows) for current download links:

1. Install the Apple-direct versions of iTunes and iCloud specified there, then AltServer for Windows.
2. Start AltServer as administrator. Connect the unlocked iPhone by USB and accept **Trust This Computer**. Enable the phone's **Wi-Fi sync** in iTunes.
3. From AltServer's tray icon, choose **Install AltStore → your iPhone**. Enter your Apple Account details locally when prompted.
4. On the iPhone, trust the developer under **Settings → General → VPN & Device Management**. For iOS 16+, enable **Settings → Privacy & Security → Developer Mode**, following the restart prompts.
5. Open AltStore, sign in if prompted, then open **My Apps → +** and select **famgpslink-unsigned.ipa** from Files. Keep AltServer running and the phone connected during installation.

Each family member uses their own Apple Account for signing. That account is separate from FamGPSlink's Firebase identity. Keep using the same signing account for updates so the app can retain its stored identity.

## 3. Join the family and share location

- **Your phone:** open FamGPSlink → **Family owner sign-in**, then sign in as `adimaitre56@gmail.com` using your chosen Firebase password.
- **Other phones:** choose a profile name once and give you the pairing code. On your owner phone, open **Settings → Family administration** and approve the device. For an existing profile on a replacement phone, use its **Recover** action.
- **Private connection:** for a new profile that should share only with you, enable **Private connection (only you)** in the approval dialog. That phone sees only you and its own pin; other family phones cannot see its profile or location. Recovery retains this choice.
- On each phone, open FamGPSlink **Settings → Allow location**, allow **While Using the App**, then use **Background access**. If Always is not offered, use **Phone settings** and select **Location → Always**, with **Precise Location** enabled.
- Enable **Share my location**. Confirm a new location appears on another family phone, then test with the iPhone locked. Complete [the physical-device pilot](PILOT.md) before relying on background updates.

## 4. Refresh before expiry

At least once every seven days, run AltServer on Windows, connect the iPhone by USB or the same Wi-Fi network, then use **AltStore → My Apps → Refresh All**. Background refresh is opportunistic; check the remaining days yourself. [AltServer connectivity instructions](https://faq.altstore.io/altstore-classic/altserver).

Expired apps cannot be opened. If AltStore itself expires, reinstall it through AltServer without deleting it first, then refresh FamGPSlink. Avoid deleting FamGPSlink to resolve signing problems: a fresh installation may require owner-approved profile recovery. Changes to the Apple signing account can also affect secure stored identity.

If you have a Mac, Apple's alternative is Xcode with a free **Personal Team**; it also requires periodic rebuilding/reinstallation under the same seven-day limit. [Apple's Personal Team documentation](https://developer.apple.com/help/account/basics/about-your-developer-account).

## Access error immediately after approval

Version 1.0.1 requests the complete member roster after approval. The privacy rules introduced with 1.1.0 reject that unrestricted read for regular members, and the old app incorrectly reports it as lost device approval. Repeating approval does not fix an old binary.

The reported run `38151212570` compiled commit `750919b52bcd53111c5259ed88885ff3c68f614a`, which is version 1.0.1. The corrected [run 38153997532](https://github.com/IchigoSolos69/FamGPSlink/actions/runs/38153997532) succeeded using `main` commit `823525b5018ad26cb0106a5fbd6073184f7a1c53` (version 1.1.0, build 1003). Download its **famgpslink-iphone-sideload** artifact, extract the ZIP and install **famgpslink-unsigned.ipa** through AltStore using the same signing Apple Account, over the existing FamGPSlink installation. Keep the app installed while updating so its remembered approval can be restored. Open FamGPSlink and use **Retry connection** if the earlier error remains on screen. The live approved device bindings were verified; reapproval should not be necessary for this update.
