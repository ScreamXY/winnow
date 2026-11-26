# Winnow

[![CI](https://github.com/ScreamXY/winnow/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/ScreamXY/winnow/actions/workflows/ci.yml)

<img src="Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="120" alt="Winnow icon: a golden grain, with chaff blowing away">

**Your friends' posts. Without the algorithm.**

To _winnow_ means to let the wind blow the chaff away so that only the grain stays. Winnow is a
personal iPhone and iPad app that does this for Instagram: it shows instagram.com and removes the
algorithmic parts. Everything else stays.

Winnow is not made by, or connected to, Instagram or Meta.

## What it does

| Instagram shows                                  | Winnow                                                                                                                                                                      |
| ------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| The "For you" feed when you open it              | Opens the **Following** feed. The Home tab and the logo also go there.                                                                                                      |
| The Reels tab and the endless reels feed         | Hides the tab. If a link opens the reels feed, Winnow shows that one reel on its own page.                                                                                  |
| Reels from people you follow                     | **Kept.** They stay in your feed and play normally.                                                                                                                         |
| The Explore grid                                 | Hides the grid. **Search still works.**                                                                                                                                     |
| "Suggested for you" accounts and suggested posts | Hidden.                                                                                                                                                                     |
| Push notifications about suggested reels         | None. Winnow has no push notifications at all (see limits).                                                                                                                 |
| Sponsored posts                                  | Kept by default. You can hide them in Settings.                                                                                                                             |
| A feed that scrolls freely                       | **Flick mode**: one flick moves exactly one post, like the full-screen feed Instagram tested in 2022. Long posts still scroll, and a slow drag settles on the nearest post. |

Messages, stories, profiles, comments, likes, search, posting and your account settings work like on
instagram.com.

## Settings

Open **Settings → Apps → Winnow**. Changes apply when you go back to Winnow.

- Open the Following feed (on)
- Flick mode (on)
- Hide: Reels tab and reels feed (on), Explore grid (on), Suggestions (on), Sponsored posts (off)

## How it works

```
SwiftUI app
└─ WKWebView with instagram.com (Safari user agent, your login stays in the web view)
   ├─ RoutePolicy (Swift)      which pages may load: Following feed, no reels feed, other sites open in Safari
   ├─ winnow.js + winnow.css   what is hidden inside a page; runs in its own script world
   └─ FlickPaging (Swift)      where a scroll stops; uses post positions from winnow.js
```

- **Pages.** Instagram changes pages without a full load. The app watches the web view's address
  and sends `/` to `/?variant=following`, and `/reels/…` to a single `/reel/…` page.
  `RedirectGuard` stops any loop.
- **Inside a page.** The script marks blocks with `data-winnow-hidden="<reason>"` and CSS hides
  them. It never removes nodes, so Instagram's own code keeps working. It finds things by link
  target (`/reels/`, `/explore/people/`) where it can, because Instagram's class names change often.
- **Flick mode.** When you start a drag, the app asks the page for the post positions. When you
  lift your finger, `FlickPaging` picks the start of the next or previous post, and the scroll view
  stops there. This is native UIKit scrolling, not CSS scroll snapping.

## Install

Winnow is for personal use. It is not on the App Store and it is not planned: App Review would
very likely reject an app that wraps another company's website (guidelines 4.2 and 5.2.2).

- **From Xcode:** open `Winnow.xcodeproj`, choose your iPhone or iPad and press Run. With a paid
  developer account the install lasts up to one year.
- **TestFlight (internal):** create the app in App Store Connect and an Xcode Cloud workflow for the
  `Winnow` scheme, like the other ScreamXY apps. Internal testing needs no App Review. Builds
  expire after 90 days, and every push to `main` makes a new one.

Then log in to Instagram once in the app. You can remove the official Instagram app or move it to
the App Library.

## Limits

- **No push notifications.** That also means no alerts for new messages. Open Winnow to check.
- **Instagram on the web does less than the app.** Sources (see `docs/RESEARCH.md`) say there is no
  posting of reels, no live videos, no voice messages or calls and no Notes. Posting stories is
  unclear.
- **Instagram changes its website.** A filter can stop working after an update. Most rules use link
  targets, which change rarely. To fix a rule, connect your device to a Mac, open Safari → Develop →
  your device → Winnow, inspect the page, and change `Web/winnow.js` or `Web/winnow.css`.
- **Not yet checked on a real account:** the filters were tested against a hand-written test page,
  not against the live site. See "Check on a device" in `docs/RESEARCH.md`.

## Ideas we did not take

- **Instagram's own controls.** The Following feed resets to "For you" every time. "Snooze suggested
  posts" lasts 30 days. You cannot hide the Reels tab.
- **SocialLite and similar apps.** They work in the same way (a web view), but cost $6.99–$9.99 per
  month, and SocialLite blocks reels from people you follow too.
- **A Safari extension or user script** (for example with the free Userscripts app). It is a good
  idea and could reuse `winnow.js`. But extensions do not run in Home Screen web apps, so you would
  always use Instagram in a Safari tab, and flick mode would need CSS snapping.
- **A patched Instagram app** (SCInsta, BHInstagram). It keeps notifications and all features, but
  needs a decrypted copy of the app from a third party, breaks after Instagram updates and is
  against Instagram's terms.

## Development

```sh
sh scripts/check.sh               # lint, format, core tests, XcodeGen, simulator build
bash scripts/ci-test.sh iPhone    # UI tests against the test page
bash scripts/ci-test.sh iPad
swift scripts/make-icon.swift     # redraw the app icon
```

See `AGENTS.md` for the project rules.
