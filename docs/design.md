# Design

Milestone 1 is a debug screen: system form, monospaced log lines, no custom brand. The notes below apply from milestone 2.

## Direction

Follow the official WHOOP app, not NOOP's Liquid Metal / Charge UI and not the Neka-style figure in the private fork.

WHOOP's own Home screen description ([The WHOOP Home screen](https://www.whoop.com/us/en/thelocker/the-all-new-whoop-home-screen/), fetched 2026-11-02; the page is dated June 21, 2023 and also describes a 2025 redesign):

- Dark, score-first. Sleep, Recovery, and Strain dials at the top. Tap a dial for the breakdown.
- Recovery is a percent. Green 67–99%, yellow 34–66%, red 1–33%. Overnight, from HRV, resting heart rate, respiratory rate, and sleep.
- Strain is cardiovascular load on a **0–21** scale. The scale is non-linear.
- Sleep Performance rolls sufficiency, consistency, efficiency, and stress into one score.
- The rest of Home (My Day, plans, dashboard tiles, Health tab, streak, AI) is not Aloft's second milestone. Three dials first.

NOOP's scorer output is a different shape. `StrainScorer` documents a historical 0–21 axis that the Charge/Effort/Rest redesign rescaled to 0–100, keeping the internal key `strain`. Recovery there is also 0–100 and is explicitly not WHOOP's model ([`RecoveryScorer.swift`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Packages/StrandAnalytics/Sources/StrandAnalytics/RecoveryScorer.swift), [`StrainScorer.swift`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Packages/StrandAnalytics/Sources/StrandAnalytics/StrainScorer.swift)). Showing WHOOP-like dials on top of those functions is a product choice still open. Label estimates as estimates.

Public UI teardowns exist ([925studios](https://www.925studios.co/blog/whoop-design-breakdown), [Screenspo](https://www.screenspo.com/apps/whoop)). They were not used for the numbers above. The color bands and the 0–21 scale come from WHOOP's article. Do not invent hex values in code until someone samples the real app and writes them down.

## iPhone Duo and a normal iPhone

Primary simulator: iPhone Duo in Xcode 27.1. The app also runs on a normal iPhone. Apple's prepare guide ([developer.apple.com/iphone-duo/prepare](https://developer.apple.com/iphone-duo/prepare/), fetched 2026-11-02):

- Built with the iOS 27 SDK or later, the app resizes when the device folds and unfolds. Size is the window's size, which does not always match the screen.
- Size from the view or window (`GeometryReader`, `onGeometryChange`). Do not read `UIScreen.main.bounds` once at launch.
- Do not branch layout on `UIDevice` orientation, interface orientation, `userInterfaceIdiom`, or a list of known point sizes.
- "Regular width" is not a synonym for iPad. iPhone Duo can present iPhone-app size classes in combinations older iPhones did not.
- Test on the iPhone Duo simulator in Xcode 27.1 (Device Hub) and on a conventional iPhone simulator. Fold and unfold. Bluetooth still needs a real device.

Aloft rule on top of that: one column when the width is narrow, two panes when it is wide. Drive that off the width you have. Do not look for a hinge angle, a posture enum, or a Duo-only code path. A normal iPhone in landscape should get the wide layout if it is actually wide, and the narrow layout if it is not.

## Taste

Clean, simple, restrained, close to a stock Apple app that happens to use WHOOP's score colors.

- System text styles and plenty of the background color. One accent family: green / yellow / red for recovery, and a single strain color once it is chosen.
- No illustration of a body, no live wallpaper, no glassmorphism layering, no second design system.
- Empty, syncing, and error states are part of the screen, written in plain language.
- Every number on Today should be traceable to a stored row. If it is missing, show that it is missing.
