# Publishing UniversePen

The **iPad app** can go to the App Store. The **Mac app (UniversePen Host)** cannot: the Mac App Store requires the App Sandbox, and a sandboxed app may not post pen and keyboard events to other apps (and "Second screen" uses a private API). It is distributed as a **notarized download** instead – the same split as other pen-display apps.

Both need the paid **Apple Developer Program** (99 €/year) in your own name. Everything below that does not need the account is already prepared in this repo.

## Already prepared

| What | Where |
|---|---|
| Store texts in 7 languages (name, subtitle, promo text, description, keywords, URLs) | `appstore/metadata/<locale>/` (fastlane "deliver" layout) |
| Privacy policy (EN + DE) | [`docs/PRIVACY.md`](PRIVACY.md) – use its GitHub URL as privacy policy URL |
| Privacy manifests (no tracking, no collected data, UserDefaults CA92.1, boot time 35F9.1) | `Client/Resources/PrivacyInfo.xcprivacy`, `Host/Resources/PrivacyInfo.xcprivacy` |
| Export compliance flag (`ITSAppUsesNonExemptEncryption = NO`: only TLS from Apple's Network framework) | `project.yml` → iPad Info.plist |
| Switchable bundle ID for the store build | `Config/PadApp.xcconfig` (+ your gitignored `PadApp.local.xcconfig`) |
| App icon without alpha channel (required by App Store Connect) | `Client/Assets.xcassets/AppIcon.appiconset/icon-1024.png` (re-run `convert('RGB')` if you regenerate it) |
| Permission texts in all 7 languages | `Client/Localization/*.lproj/InfoPlist.strings` |
| Notarized Mac build script | [`Tools/notarize-host.sh`](../Tools/notarize-host.sh) + `Host/UniversePenHost.entitlements` |
| Demo mode for App Review (works without a Mac) | iPad → "Try without a Mac (demo)" |

## Steps once you have the account

1. **Bundle ID.** In the developer portal register an App ID, e.g. `io.github.bedsheetsosu.universepen`. Create `Config/PadApp.local.xcconfig`:
   ```
   PAD_BUNDLE_ID = io.github.bedsheetsosu.universepen
   DEVELOPMENT_TEAM = <your team ID>
   ```
   Note: a new bundle ID is a new app on the iPad – settings and pairing start fresh (export your profiles first).
2. **App Store Connect → New App:** platform iOS, name "UniversePen" (if the name is taken, try "UniversePen – Pen Display"), primary language English, the bundle ID from step 1, SKU e.g. `universepen-ipad`.
3. **Upload:** Xcode → Product → Archive (scheme Tafel, device "Any iOS Device") → Distribute App → App Store Connect.
4. **Store page:** copy the texts from `appstore/metadata/` (or `fastlane deliver` with that folder). Category: Graphics & Design. Price: free.
5. **App Privacy:** "Data Not Collected".
6. **Export compliance:** answer "uses encryption → only exempt/standard encryption provided by the OS" (matches the Info.plist flag). Double-check the current wording in App Store Connect.
7. **Screenshots:** the iPad 13-inch size (2064 × 2752 or 2752 × 2064) is required; App Store Connect scales them for smaller iPads.
8. **Review notes** – paste this:

   > UniversePen turns the iPad into a pen display / pen tablet for a Mac. It needs the free companion app "UniversePen Host" on a Mac (macOS 15+), downloadable from https://github.com/bedsheetsosu/universepen/releases, paired with a code shown on the Mac.
   > **To review without a Mac:** on the first screen tap "Try without a Mac (demo)". The demo shows drawing with pressure and tilt, the pointer, clicks and the tablet mode with an aiming exercise entirely on the iPad.
   > The app makes no internet connections and collects no data; it only connects to the user's own Mac on the local network or USB cable.

9. **Mac app:** `TEAM_ID=<team> Tools/notarize-host.sh` → upload the zip to the GitHub release. Users then open it without "Open Anyway".

## Known review risks

- **Guideline 4.2 / 2.5.x (companion app):** the iPad app needs a Mac app from outside the App Store. Common for this kind of app; the demo mode and the review note above address it.
- **Trademarks:** the store texts name "Apple Pencil" and "Mac" only descriptively; keywords contain no other companies' brands or game names.
- The **name** "UniversePen" may already be taken in the store – that only shows when you create the app.
