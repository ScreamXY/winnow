# TestFlight setup

Winnow ships only to the internal TestFlight group, never to the App Store. A push to `main` starts
the Xcode Cloud workflow, which archives the `Winnow` scheme and sends the build to TestFlight.

## Status (26 November 2026)

Done:

- Repo: bundle ID `com.screamxy.winnow`, team `QC8483T34B`, automatic signing, opaque app icons,
  privacy manifest (UserDefaults, reason `CA92.1`), `ITSAppUsesNonExemptEncryption = NO`, and
  `ci_scripts/ci_post_xcodebuild.sh` for the "What to Test" notes.
- Developer portal: App ID "Winnow" with bundle ID `com.screamxy.winnow` is registered.
- App Store Connect: app record **Winnow: Following Feed** (Apple ID `6839693814`, SKU
  `winnow-ios`, English (U.S.), Full Access). "Winnow" and "Winnow Feed" were already taken. The
  Home Screen name stays "Winnow".
- TestFlight: internal group **Internal** with automatic distribution and one tester (the account
  holder).
- A local Release archive (`xcodebuild … archive -allowProvisioningUpdates`) works.

Not done:

- No build is uploaded yet. The upload from this Mac failed because Xcode had no valid App Store
  Connect login for the team ("App Store Connect access for QC8483T34B is required").
- No Xcode Cloud workflow yet. App Store Connect on the web cannot create a new Xcode Cloud
  product; only Xcode can.

## Create the Xcode Cloud workflow (in Xcode, about 5 minutes)

1. In Xcode, open **Settings → Accounts** and check that your Apple Account is signed in.
2. Open `Winnow.xcodeproj` and choose **Integrate → Create Workflow…**. Select the **Winnow**
   product. Xcode finds the existing record "Winnow: Following Feed".
3. If Xcode asks, grant the Xcode Cloud GitHub app access to `ScreamXY/winnow`.
4. Edit the workflow before you save it:
   - Name: `Main to TestFlight`. General: turn on **Restrict Editing**.
   - Start condition: **Branch Changes** on `main`. Under **Files and Folders**, choose
     "Don't start a build if all changed files match" and add `README.md`, `AGENTS.md`,
     `CLAUDE.md`, `SECURITY.md` and the `docs` folder (the same list as
     `.github/xcode-cloud-paths.json`).
   - Environment: latest Xcode release.
   - Action: **Archive – iOS**, scheme `Winnow`, Distribution Preparation
     **TestFlight (Internal Testing Only)**. Winnow never goes to the App Store, so this is right
     here, unlike the other ScreamXY apps.
   - Post-action: **TestFlight Internal Testing** with the group **Internal**. The group's
     automatic distribution does not cover Xcode Cloud builds, so this post-action is needed.
5. Start the first build. It takes about 10 to 20 minutes.
6. Open the TestFlight app on your iPhone and iPad and install **Winnow: Following Feed**.

## Upload a build by hand (optional)

With a signed-in Xcode account, this uploads the current commit:

```sh
xcodebuild -project Winnow.xcodeproj -scheme Winnow -configuration Release \
    -destination 'generic/platform=iOS' -archivePath build/release/Winnow.xcarchive \
    -allowProvisioningUpdates archive
xcodebuild -exportArchive -archivePath build/release/Winnow.xcarchive \
    -exportOptionsPlist <plist with method app-store-connect, destination upload,
    teamID QC8483T34B, testFlightInternalTestingOnly true> \
    -exportPath build/release/export -allowProvisioningUpdates
```

After a manual upload, raise the next build number in the product's Xcode Cloud settings.

## When a build fails

- A red Xcode Cloud run on `main` is a release problem: fix it on a branch, do not retry.
- App Store Connect sends an email with an `ITMS-…` code when it rejects a build. Fix the cause and
  push again; Xcode Cloud gives the next build number.
- If a processed build has no group, add it to **Internal** by hand in App Store Connect →
  TestFlight, then check the post-action settings of the workflow.
