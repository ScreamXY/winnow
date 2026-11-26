# Winnow

Winnow is a personal iPhone and iPad app. It shows instagram.com in a web view and removes the
algorithmic parts: it opens the Following feed, hides the Reels tab and the reels feed, hides the
Explore grid and hides suggestions. Reels from followed accounts stay. Flick mode moves one post per
flick in the home feed.

- Not for the App Store. Install from Xcode on the device, or through internal TestFlight. App Review
  would likely reject a wrapped third-party website (guidelines 4.2 and 5.2.2). Never use
  "Instagram", "Insta" or "gram" in the app name or icon, and never copy Instagram's logo, colors or
  markup.
- Native SwiftUI for iOS and iPadOS 26+. Keep pure logic (routes, flick paging, settings) in
  `Sources/WinnowCore`, Foundation-only, and test it with `swift test`.
- `Web/winnow.js` and `Web/winnow.css` do the hiding inside the page. The script runs in its own
  content world. Prefer link targets (`href`) and page structure over class names or visible text.
  Mark nodes with `data-winnow-hidden="<reason>"` and hide them with CSS; never remove nodes.
  Keep language-dependent labels in the lists at the top of the script.
- Instagram's Following page has no stories tray. `StoriesStrip` loads the home page in a second,
  small web view and `Web/stories.js` shows only the tray; the main page makes room above the first
  post (`setStoriesSpace`). The strip must never start a video or make sound, and only story pages
  and tapped links may go from the strip to the main web view.
- Never use `devicectl device copy to --remove-existing-content`: it deleted the whole app
  container on 26 November 2026 (login and settings). `scripts/device-probe.sh` copies a folder
  without it.
- `RoutePolicy` decides which pages may load. Keep it in sync with the route names in `winnow.js`.
  Any new redirect needs a unit test and must go through `RedirectGuard`.
- `Fixtures/fixture-feed.html` is a hand-written test page, not Instagram markup. It is in Debug
  builds only (`EXCLUDED_SOURCE_FILE_NAMES` in Release). When a hook in `winnow.js` changes, change
  the fixture and the UI tests with it.
- Never put Instagram credentials, cookies, screenshots of a real account or other personal data in
  the repo, logs, tests or issues. UI tests only use the fixture and never load instagram.com.
- Settings live in `Resources/Settings.bundle/Root.plist`. Keep its keys and defaults equal to
  `FilterSettings`.
- Generated Xcode project: edit `project.yml`, regenerate with `scripts/xcodegen.sh` (pinned
  XcodeGen 2.46.0), and commit the project plus the generated Info.plists, entitlements and shared
  schemes. CI runs `scripts/xcodegen.sh --check` and fails when they drift. Shared rule for all
  ScreamXY apps since 14 October 2026.
- App icon: `swift scripts/make-icon.swift` draws it. Change the script, not the PNG files.
- Read `README.md` for the design and `docs/RESEARCH.md` for sources and open questions.

ScreamXY-wide notes (all apps, portal, release TODO, trader and contact decisions) live in the
Obsidian vault at `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Privat/Development/ScreamXY/`
(`ScreamXY.md`, `TODO.md`). If the vault is not on this machine, say so.

## Shared release and CI rules

Winnow carries the shared rules without the App Store eligibility bullet, because it never goes to
the App Store. Its Xcode Cloud archive may use **TestFlight (Internal Testing Only)**.

Status (26 November 2026): App ID, App Store Connect record "Winnow: Following Feed" (Apple ID
`6839693814`) and the internal TestFlight group "Internal" exist. No Xcode Cloud workflow and no
uploaded build yet. Release scheme: `Winnow`. Setup steps and status: `docs/TESTFLIGHT.md`.

- Public support and security contact: `screamcode@gmail.com`. Keep in-app contact details, portal policies and App Store metadata consistent.
- `AGENTS.md` owns the rules. `CLAUDE.md` contains only: `See @AGENTS.md for monorepo documentation and guidelines.`
- Delivery (14 October 2026): feature branches are run from Xcode directly on the device with development signing. A push to `main` triggers the app's Xcode Cloud workflow, which archives the release scheme and delivers it to the internal TestFlight group; `ci_scripts/ci_post_xcodebuild.sh` writes the "What to Test" notes from the commit subjects. GitHub Actions stays the fast PR check and never signs or uploads. Xcode Cloud stamps its own build number (ignore `CURRENT_PROJECT_VERSION` there); after a manual upload, raise the next build number in the product's Xcode Cloud settings. A red Xcode Cloud run on `main` is a release problem: fix it on a branch, do not retry.
- Every Actions job needs a finite timeout and minimal permissions. Cancel superseded checks, but let an active production deployment finish.
- Exclude confirmed internal documentation from app builds. Documentation shipped in the product remains a build input. Scope jobs to their component and shared dependencies; unknown paths still run. Keep fixtures, migrations, dependency locks, localization and build configuration in CI scope.
- GitHub runners are for fast lint, type checks, deterministic unit tests and compilation only. Extensive browser E2E, simulator/device suites and screenshots run locally, including when agents code; do not add hosted opt-ins for them. Never run paid AI calls, live provider corpus runs, production database tests or signing/publishing as routine PR checks.
- Keep artifacts short-lived (7 days or less), and release bundles limited to tags/manual runs. Cheap lint, type checks, deterministic tests and compilation remain automatic.
- Release status lives in the Obsidian vault: `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Privat/Development/ScreamXY/` (`ScreamXY.md`, `TODO.md`). If unavailable, say so. Distinguish prepared files, published pages, CI results and hardware verification.

## Local validation required for relevant changes

`sh scripts/check.sh` (SwiftLint, swift-format, `swift test`, XcodeGen and a simulator build), then
`bash scripts/ci-test.sh iPhone` and `bash scripts/ci-test.sh iPad` for changes to the app, the page
script, the styles or the fixture. Discover installed simulators; the script records local evidence
under `build/ci/`. If `xcode-select` points at the Command Line Tools, prefix commands with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

Filters can only be fully checked against the real instagram.com on a device: connect the device,
open Safari → Develop → the device → Winnow, and inspect the page. Agents use the Debug-only probe
instead (`App/DebugProbe.swift`): with Winnow Dev open on the device, `scripts/device-probe.sh
<device> <script.js> [--snapshot]` runs the script in the page and prints the answer. Probe scripts
return page structure only (tags, roles, link patterns, sizes), never names, captions or messages.
Probe output and snapshots stay in `build/` (ignored by git) and are never committed. Report what
was checked on a device separately from simulator results.

Run the affected suites before committing and report what actually ran. Keep tests
and local scripts even when their hosted jobs are removed. Do not increase a CI
timeout to hide a hang; inspect the failure first.
