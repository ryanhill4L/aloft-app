# Aloft

Aloft is Ryan Hill's personal iPhone app. It talks to his WHOOP strap over Bluetooth and keeps the data on the phone, so the strap is usable without a WHOOP subscription.

This repository is a from-scratch restart. It replaces his private fork of [NOOP](https://github.com/ryanbr/noop) ([ryanhill4L/noop](https://github.com/ryanhill4L/noop)). That fork became a large monorepo: many targets, a friends backend, widgets, a watch app, Android, and a Neka-inspired UI. Aloft keeps the strap path and leaves the rest behind. NOOP is the reference, not the codebase to extend.

**Status: early.** The strap package, the on-device store, the app's screens, and a small Go backend exist. A real sync with a strap has not been proven on a phone yet.

Aloft is not affiliated with WHOOP. It is not a medical device. Scores, when they exist, will be on-device estimates.

## What Aloft is

- An iPhone app that pairs with a WHOOP strap you own, syncs history, and stores it in on-device SQLite.
- One small Swift package for the strap layer (pairing, protocol, store), then a thin app around it.
- A dark, WHOOP-app-style interface once sync is proven: recovery, strain, and sleep first.
- Adaptive layout for a normal iPhone and for iPhone Duo. See [docs/design.md](docs/design.md).

## What Aloft is not

- A cloud health service or an analytics product. Health data stays on the phone. The backend only holds your profile, your Crew, the day's weather word, and Lifts (see [docs/decisions.md](docs/decisions.md)).
- A port of the NOOP app, its Liquid Metal / Charge UI, Android, watchOS, widgets, or the friends backend.
- A place for health exports, photos, secrets, or Apple team and bundle identifiers.

## Layout

| Path | What |
|---|---|
| `proto/` | API contract, Connect-RPC |
| `backend/` | Go API, Neon Postgres, Neon Auth JWT verification |
| `ios/Aloft/` | SwiftUI app |
| `ios/Packages/AloftStrap/` | Strap framing, history, durable SQLite store |

## Goals

- Pair, sync, and durably save strap data on a real iPhone.
- Show that state on a bare debug screen before any other UI.
- Then build a Today screen in the spirit of the official WHOOP app, one screen at a time.
- Stay small enough that a new coding session can learn the project from these docs.

## Non-goals

- Feature parity with NOOP or with the official WHOOP app.
- Coaching, workouts, journal, alarms, firmware updates. (A Crew of up to 12 sharing weather words is in scope; see decision 5.)
- HealthKit, trends, and widgets until the strap path is proven (see [docs/roadmap.md](docs/roadmap.md)).
- Commercial distribution. Use is personal and noncommercial. See [LICENSE](LICENSE).

## Milestones

| | Milestone | Done when |
|---|---|---|
| 0 | These docs | This pull request |
| 1 | Strap package, durable store, debug screen | Pairs and syncs on a real iPhone; data survives relaunch with the WAL sidecars removed |
| 2 | Today | Recovery, strain, and sleep, WHOOP-app style, adaptive layout |
| 3+ | Later | Trends, HealthKit write, and anything else only after 1 and 2 |

Detail and non-goals live in [docs/roadmap.md](docs/roadmap.md). Decisions are in [docs/decisions.md](docs/decisions.md).

## How to build

Needs Xcode 27 with the iOS 27 simulator runtime, Go 1.25+, `buf`, `xcodegen`, and the protoc plugins listed in `buf.gen.yaml`.

```bash
cp backend/.env.example backend/.env   # fill in a Neon branch's URLs
make test                              # strap package + backend unit tests
make dev-backend                       # API on :9090
make run-ios                           # generate project, build, launch on a simulator
```

Put your own bundle and team id in `ios/Config/Local.xcconfig` (untracked) before running on a phone. The Simulator cannot talk to a strap ([NOOP's own note](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/docs/IOS.md#L354-L356)).

## Docs

- [AGENTS.md](AGENTS.md) — rules for coding sessions
- [docs/noop-reference.md](docs/noop-reference.md) — where the reference code lives
- [docs/protocol-notes.md](docs/protocol-notes.md) — strap BLE, from that code
- [docs/design.md](docs/design.md) — look and layout
- [docs/roadmap.md](docs/roadmap.md) — milestones
- [docs/decisions.md](docs/decisions.md) — decision log

## License

[PolyForm Noncommercial 1.0.0](LICENSE), the same license as upstream NOOP. Commercial use is not granted. [NOTICE](NOTICE) credits NOOP and the research it builds on.
