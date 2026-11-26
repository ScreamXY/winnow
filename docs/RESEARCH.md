# Research

Collected on 26 November 2026 from public pages, without logging in anywhere. Confidence:
**high** = official or primary source, **medium** = secondary or older source, **low** = weak or
disputed source.

## Similar apps and projects

| Project                                                                | What it is                                                                                        | Notes                                                                                                                                                                                                                                                                                      |
| ---------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| [SocialLite](https://apps.apple.com/us/app/socialliteapp/id6757661674) | iOS app for Instagram, YouTube, Facebook, X, Snapchat and Reddit                                  | Core features need Pro: $6.99–$9.99 per month or $19.99–$47.90 per year. Shows the web version of each network ([site](https://sociallite.app/for-apple/)). Reviews: no message notifications, the real app is still needed for stories and posts, the Instagram view is "glitchy". (high) |
| [JustAgram](https://github.com/AlexMatter1512/justagram)               | Open-source Capacitor app with mobile instagram.com                                               | CSS filters for Reels, Explore, stories and suggested reels, plus a messages-only mode. Good reference for selectors. (high)                                                                                                                                                               |
| [No Reels](https://github.com/tonybenoy/no_reels)                      | Expo web view                                                                                     | Archived in 2023. (high)                                                                                                                                                                                                                                                                   |
| [Userscripts](https://github.com/quoid/userscripts)                    | Free, open-source Safari extension                                                                | Runs `.user.js` files in Safari on iOS. (high)                                                                                                                                                                                                                                             |
| [Hyperweb](https://apps.apple.com/gb/app/hyperweb/id1581824571)        | Safari extension                                                                                  | Last update March 2023. (high)                                                                                                                                                                                                                                                             |
| [SocialFocus](https://apps.apple.com/pk/app/id1661093205)              | Paid Safari extension                                                                             | Safari only. (high)                                                                                                                                                                                                                                                                        |
| [Less Is More](https://apps.apple.com/app/id6751927411)                | App                                                                                               | Forces Following, hides "For you", Explore and suggestions. (high)                                                                                                                                                                                                                         |
| [SCInsta](https://github.com/SoCuul/SCInsta)                           | Tweak for the real Instagram app (fork of [BHInstagram](https://github.com/BandarHL/BHInstagram)) | Hides the Reels tab, Explore grid, suggestions and ads. Needs a jailbreak, TrollStore or a decrypted IPA. Breaks with Instagram updates; Instagram's [terms](https://help.instagram.com/581066165581870) forbid modifying the app. (high)                                                  |

## Instagram on the web

- `https://www.instagram.com/?variant=following` and `?variant=favorites` exist
  ([How-To Geek, 2024](https://www.howtogeek.com/instagram-for-web-still-has-a-chronological-feedif-you-know-how-to-find-it/)).
  (high that they existed; medium that they still work; no source for phone-width pages)
- No report found that Instagram blocks its own login inside WKWebView. SocialLite and JustAgram
  rely on it. Google sign-in is blocked in web views
  ([Google](https://developers.googleblog.com/en/upcoming-security-changes-to-googles-oauth-20-authorization-endpoint-in-embedded-webviews/)).
  (medium)
- The default WKWebView user agent has no `Version/… Safari/…` part
  ([WebKit 233073](https://bugs.webkit.org/show_bug.cgi?id=233073)). Winnow adds it. No source shows
  that this changes Instagram's behavior. (high / unknown)
- Problems other wrappers had: the two-factor screen reset
  ([JustAgram #13](https://github.com/AlexMatter1512/justagram/issues/13)), pop-ups and reCAPTCHA
  frames leaving the web view ([FocusFeed PR](https://github.com/jacobsmolik1/FocusFeed/pull/1)).
  Winnow lets all frames and login redirects load inside. (medium)
- Routes: the phone layout links to `/`, `/explore/` (search sits above the Explore grid),
  `/reels/` and `/direct/inbox/`. The reels feed also uses `/reels/<id>/`
  ([Reels Off](https://addons.mozilla.org/en-US/firefox/addon/reels-off/)). Single items are
  `/reel/<code>/` and `/p/<code>/` ([Meta oEmbed](https://developers.facebook.com/docs/instagram-platform/oembed)).
  (medium / high)
- The web version cannot post reels, go live, send voice messages or make calls; Notes are app-only;
  posting stories is disputed ([mobilemasr, 2026](https://mobilemasr.com/en/blogs/instagram-web-on-iphone)).
  (low)

## Apple rules

- Guidelines 4.2 (more than a repackaged website), 4.2.2 (no web clippings), 5.2.2 (third-party
  services need permission) and 5.2.1 (trademarks)
  ([App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)). (high)
- Internal TestFlight testers need no review; builds expire after 90 days
  ([Apple](https://developer.apple.com/help/app-store-connect/test-a-beta-version/overview-of-testflight/)).
  (high)
- A development install with a paid account lasts up to one year (7 days with a free account)
  ([TN3125](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles)).
  (high)
- Safari extensions do not run in Home Screen web apps
  ([Apple forum, 2022](https://developer.apple.com/forums/thread/715634)). Nothing newer found.
  (medium)

## Instagram's own controls

- The Following feed is chronological and cannot be the default; the app reopens on Home
  ([TechCrunch, 2022](https://techcrunch.com/2022/03/23/instagram-launches-chronological-and-favorites-feeds-for-all-users-but-they-cant-be-the-default)).
  (high for 2022, medium today)
- "Snooze suggested posts" lasts 30 days
  ([Instagram](https://about.instagram.com/blog/tips-and-tricks/control-your-instagram-feed)). (high)
- "Your Algorithm" sets Reels topics; it reached all English users in January 2026
  ([TechCrunch](https://techcrunch.com/2025/12/10/instagrams-new-your-algorithm-tool-gives-you-more-control-over-the-reels-you-see)).
  (high)
- Notifications → Live and Reels can turn off "Recently uploaded reels" and "Most watched reels"
  ([iDB](https://www.idownloadblog.com/2022/09/19/how-to-turn-off-new-reels-notifications-instagram/)).
  (medium)
- The iPad app launched on 3 September 2025 and opened to Reels
  ([TechCrunch](https://techcrunch.com/2025/09/03/instagram-is-finally-launching-an-ipad-app/)).
  (high)

## Flick mode background

- Instagram tested a full-screen home feed from May 2022 and stopped it in July 2022
  ([TechCrunch](https://techcrunch.com/2022/07/28/instagram-to-walk-back-full-screen-home-feed-and-temporarily-reduce-recommended-posts/)).
  (high)
- CSS `scroll-snap-stop: always` works in iOS Safari 15+, and WebKit lets you scroll freely inside a
  snap area taller than the screen ([WebKit 223021](https://bugs.webkit.org/show_bug.cgi?id=223021)),
  but open bugs remain for momentum and jumps ([253195](https://bugs.webkit.org/show_bug.cgi?id=253195),
  [253196](https://bugs.webkit.org/show_bug.cgi?id=253196)). Winnow uses native scroll targets
  instead. (high / medium)

## Check on a device

These questions can only be answered with a real account:

1. Does `/?variant=following` show the Following feed at phone width, and does the Home tab go there?
2. Does the home feed scroll the whole page (needed for flick mode), or an inner element?
3. Are feed posts still `<article>` elements? Do the Reels tab and "See all" suggestions still use
   `href="/reels/"` and `href="/explore/people/"`?
4. Does a `/reel/<code>/` page let you swipe on into more algorithmic reels?
5. Which labels does Instagram use for "Suggested for you" and "Sponsored" in your language?
6. Do login, two-factor codes and the "Save login info" step work?
