# Agents

Read this before changing Aloft. The product summary is in [README.md](README.md). The reference map is [docs/noop-reference.md](docs/noop-reference.md).

Aloft is pre-code. The first implementation milestone is a strap package, a durable on-device store, and a debug screen that proves a real sync. Do not start the WHOOP-style UI before that proof exists.

## Hard rules

- **Small, verifiable pull requests.** One concern per PR. Subtract before adding. If a NOOP type is not on the milestone path, leave it out.
- **Prove it before calling it done.** Package tests for protocol and store behavior. Simulator screenshots on iPhone Duo (Xcode 27.1) and on a normal iPhone for any UI. A real-device check for Bluetooth: the Simulator has no CoreBluetooth path to a strap. Vision person segmentation, if a later milestone needs it, is also a device check; no such call was found in the NOOP files read for these docs.
- **Ryan merges and ships.** Never merge to `main`, upload a TestFlight build, or submit for App Store review unless Ryan has explicitly said yes in the conversation that asks for it.
- **Noncommercial only.** [PolyForm Noncommercial 1.0.0](LICENSE). Do not add paid features, ads, or a commercial license.
- **Never copy GPL code.** NOOP itself is PolyForm Noncommercial, not GPL. Port only what these docs mark as in scope, keep [NOTICE](NOTICE) accurate, and do not paste source from projects whose license is missing or incompatible (including the unlicensed reverse-engineering repos named in NOTICE).
- **No personal data in git.** No health exports, SQLite files, strap logs from a real session, photos, emails, Apple team ids, bundle ids, or App Store Connect details. The GitHub repo is public.
- **No secrets.** No tokens, API keys, `.env` files, or provisioning profiles.
- **On device only.** No accounts, no backend, no analytics SDK, no network calls in the strap path.
- **Ack the strap only after the bytes are durable.** See the WAL lesson in [docs/noop-reference.md](docs/noop-reference.md).

## How to work

1. Read the milestone in [docs/roadmap.md](docs/roadmap.md) and the decision log in [docs/decisions.md](docs/decisions.md).
2. Prefer a failing test or a checked-in note of expected behavior before the implementation.
3. Keep the strap package free of SwiftUI and CoreBluetooth types in the decoder and the store, matching NOOP's split (`WhoopProtocol` and `WhoopStore` are platform-pure; `BLEManager` is the app-side Bluetooth owner).
4. When borrowing a protocol fact, cite the pinned NOOP file in the commit message. When borrowing behavior, rewrite it smaller. Do not copy a file in and delete later.
5. Info.plist purpose strings belong in the project generator spec if a generator is used. NOOP lost `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` because they lived only in the plist ([ryanhill4L/noop#4](https://github.com/ryanhill4L/noop/pull/4)). Skipping XcodeGen is also fine.
6. Open pull requests as drafts until the proof in the PR body is real (tests, screenshots, or a device note). Do not merge them yourself.

## Verify

| Change | Proof |
|---|---|
| Framing, CRC, command encode/decode | Package tests, no device |
| SQLite durability | Insert, copy the main file without `-wal`/`-shm`, reopen, row is still there. Repeat after a process relaunch |
| Any screen | iPhone Duo simulator and a normal iPhone simulator |
| Pair, bond, sync, live HR | Physical iPhone and the strap. Say so in the PR when this was not run |

## Do not bring over

The private fork's friends backend (`backend/`, `Packages/NoopShare`), Android, watch app, widgets, Oura, Polar, coach, lift log, Liquid Metal / Neka UI, and the rest of `Strand/Screens`. The map of what to port is in [docs/noop-reference.md](docs/noop-reference.md).

## Pins

Facts in `docs/` were read at these commits. Re-read the file before treating a line as current.

- Upstream NOOP (public): [`ryanbr/noop` `2a1de7609843b095505274ad6fc811757210be80`](https://github.com/ryanbr/noop/commit/2a1de7609843b095505274ad6fc811757210be80) (2026-10-25)
- Private fork HEAD: [`ryanhill4L/noop` `0a6bad593a8966cd0d48056b40e362dcca4d040a`](https://github.com/ryanhill4L/noop/commit/0a6bad593a8966cd0d48056b40e362dcca4d040a) (2026-11-02)
- WAL checkpoint fix, merged: [`ec3032010ff177098b304394d4a37380d4661264`](https://github.com/ryanhill4L/noop/commit/ec3032010ff177098b304394d4a37380d4661264) ([pull request 3](https://github.com/ryanhill4L/noop/pull/3))

The fork is private. If a session cannot read it, use upstream and say so.
