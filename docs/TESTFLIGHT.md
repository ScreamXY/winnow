# TestFlight setup

Winnow ships only to the internal TestFlight group, never to the App Store. A push to `main` starts
the Xcode Cloud workflow, which archives the `Winnow` scheme and sends the build to TestFlight.

## Status

- Prepared in the repo: bundle ID `com.screamxy.winnow`, team `QC8483T34B`, automatic signing,
  opaque app icons, privacy manifest (UserDefaults, reason `CA92.1`),
  `ITSAppUsesNonExemptEncryption = NO`, and `ci_scripts/ci_post_xcodebuild.sh` for the
  "What to Test" notes.
- Not done yet (needs your Apple ID): the App Store Connect record, the internal group and the
  Xcode Cloud workflow. Steps below.

## One-time setup (about 10 minutes)

The name "Winnow" is already used on the App Store, and App Store Connect names must be unique.
Use **Winnow Feed** for the record. The name on the Home Screen stays "Winnow".

1. **Create the workflow in Xcode.** Open `Winnow.xcodeproj` and choose
   **Integrate → Create Workflow…** (or the **Cloud** tab in the Report navigator).
   Select the **Winnow** product.
2. **App Store Connect record.** Xcode offers to create it. Use:
   - Name: `Winnow Feed`
   - Bundle ID: `com.screamxy.winnow`
   - SKU: `winnow-ios`
   - Primary language: English
3. **Repository access.** If Xcode asks, grant the Xcode Cloud GitHub app access to
   `ScreamXY/winnow`.
4. **Edit the workflow** before you save it:
   - Name: `Main to TestFlight`. General: turn on **Restrict Editing**.
   - Start condition: **Branch Changes** on `main`. Under **Files and Folders**, choose
     "Don't start a build if all changed files match" and add `README.md`, `AGENTS.md`,
     `CLAUDE.md`, `SECURITY.md` and the `docs` folder (the same list as
     `.github/xcode-cloud-paths.json`).
   - Environment: latest Xcode release.
   - Action: **Archive – iOS**, scheme `Winnow`, Distribution Preparation
     **TestFlight (Internal Testing Only)**. Winnow never goes to the App Store, so this is right
     here, unlike the other ScreamXY apps.
   - Post-action: **TestFlight Internal Testing** with a new group **Internal** that contains you.
5. **Start the first build** when Xcode asks. It takes about 10 to 20 minutes.
6. **Install.** Open the TestFlight app on your iPhone and iPad and install **Winnow Feed**.

## When a build fails

- A red Xcode Cloud run on `main` is a release problem: fix it on a branch, do not retry.
- App Store Connect sends an email with an `ITMS-…` code when it rejects a build. Fix the cause and
  push again; Xcode Cloud gives the next build number.
- If a processed build has no group, add it to **Internal** by hand in App Store Connect →
  TestFlight, then check the post-action settings of the workflow.
