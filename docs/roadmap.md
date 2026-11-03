# Roadmap

Order is the point. A later milestone does not start because an earlier one is "mostly" done.

## 0 — Docs

This repository: README, agent rules, NOOP map, protocol notes, design, decisions, license. No app code.

## 1 — Strap, store, debug screen

One Swift package plus an iOS app shell.

- Pair and bond on a real iPhone. Sync history. Save it in on-device SQLite.
- Fold the WAL into the main file before acking the strap. File protection must stay readable after first unlock. Test by relaunching with `-wal` and `-shm` removed and still seeing the rows.
- Debug screen only: connection state, last sync, last error, row counts, recent log lines, copy and share. Nothing uploaded.
- Package tests for framing and for the durability case. Simulator screenshots of the debug screen on iPhone Duo and on a normal iPhone. BLE proof is the physical phone, stated in the PR.

Out of this milestone: scores, any network in the strap path.

Status (2026-11-02): package, store, durability tests, and the debug view (the Log tab) exist. Not yet proven: pair, bond, and sync on a physical iPhone with Ryan's strap.

## 1b — Profile, Crew, and the designed screens

Added by decision 5 and 7. Email or Apple sign-in through Neon Auth, onboarding (name, basics, band, Health, Crew, nights), and Home with Sky, Crew, Log, and You tabs. The Go API holds profile, Crew, weather words, and Lifts.

Status (2026-11-02): built and screenshot-checked on the iPhone Duo simulator (closed, plus offscreen renders at the open sizes) and an iPhone 17 Pro in portrait and landscape. Backend tests run against the Neon `dev` branch. Not yet proven: a full sign-in with a real inbox, Apple sign-in (needs the real bundle and team id), and folding the Duo simulator live.

Status (2026-11-03): the API runs on Cloud Run against Neon `main` (decision 9, `infra/`). Unauthenticated calls get 401 and `/health` returns ok. Neon Auth `main` trusts the Cloud Run origin and is named Aloft. Still open: the Apple provider and custom SMTP on `main`, a TestFlight build with the new Release settings, a real sign-in that saves a profile, and turning off "Allow Localhost" once no tester has the old build.

## 2 — Today

A single screen in the spirit of the official WHOOP app: recovery, strain, and sleep, computed on device from the stored strap data. Adaptive layout (one column when narrow, two panes when wide). Same screenshot pair as milestone 1, plus a device check that the numbers came from a real sync rather than a fixture alone.

Open until then: whether the strain dial shows WHOOP's 0–21 or NOOP's rescaled 0–100. See [design.md](design.md).

## 3+

Only after Today is in daily use. Candidates, not commitments:

- Trends for the three scores.
- HealthKit write, opt-in, on device.
- Sleep detail, then whatever Ryan asks for next.

- Sync health chunks to the backend (decision 5 says this needs its own entry first).

Still out: watch app, widgets, Android, coach, firmware tools.
