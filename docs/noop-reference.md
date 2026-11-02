# NOOP reference map

Aloft learns from NOOP. It does not live in that tree.

Two repos were read for this page:

| Repo | Role | Commit |
|---|---|---|
| [ryanbr/noop](https://github.com/ryanbr/noop) | Public upstream. Protocol, store, and scores below are from here unless noted. | [`2a1de760`](https://github.com/ryanbr/noop/commit/2a1de7609843b095505274ad6fc811757210be80) |
| [ryanhill4L/noop](https://github.com/ryanhill4L/noop) | Private fork. Same client layout under `clients/noop/`, plus a friends backend. Home of the WAL fix and the sync debug sheet. | [`0a6bad59`](https://github.com/ryanhill4L/noop/commit/0a6bad593a8966cd0d48056b40e362dcca4d040a) |

Upstream paths below are at the repo root (`Packages/WhoopProtocol/...`). On the fork, prefix them with `clients/noop/`. The fork was readable for this pass. The private links only resolve with access.

Upstream's own map is [`docs/ARCHITECTURE.md`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/docs/ARCHITECTURE.md) and [`docs/PROTOCOL_IMPLEMENTATION.md`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/docs/PROTOCOL_IMPLEMENTATION.md).

## Where the strap path lives

| Concern | Upstream | Fork-only note |
|---|---|---|
| GATT UUIDs, hello bytes, header CRC kind | [`Packages/WhoopProtocol/.../DeviceFamily.swift`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Packages/WhoopProtocol/Sources/WhoopProtocol/DeviceFamily.swift) | Same path under `clients/noop/` |
| CRC, frame verify | [`Framing.swift`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Packages/WhoopProtocol/Sources/WhoopProtocol/Framing.swift) | |
| Packet-type names and field offsets | [`Resources/whoop_protocol.json`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Packages/WhoopProtocol/Sources/WhoopProtocol/Resources/whoop_protocol.json), loaded by [`Schema.swift`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Packages/WhoopProtocol/Sources/WhoopProtocol/Schema.swift) | |
| Historical row decode | [`HistoricalStreams.swift`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Packages/WhoopProtocol/Sources/WhoopProtocol/HistoricalStreams.swift), [`Streams.swift`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Packages/WhoopProtocol/Sources/WhoopProtocol/Streams.swift) | |
| Scan, bond, subscribe, reassembly | [`Strand/BLE/BLEManager.swift`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Strand/BLE/BLEManager.swift#L524-L549) | Huge. Rewrite the connect path; do not copy the file |
| Commands the app is willing to send | [`Strand/BLE/Commands.swift`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Strand/BLE/Commands.swift#L1-L45) | Safe subset. Destructive opcodes stay out |
| Live decode into UI state | [`Strand/BLE/FrameRouter.swift`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Strand/BLE/FrameRouter.swift), [`LiveState.swift`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Strand/BLE/LiveState.swift) | `LiveState.log` is a 5,000-line ring (`maxLogLines`, [line 802](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Strand/BLE/LiveState.swift#L802)) |
| History state machine and ack | [`Strand/Collect/Backfiller.swift`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Strand/Collect/Backfiller.swift#L574-L582) | Ack payload slice: [`endData`, line 389](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Strand/Collect/Backfiller.swift#L389-L395). Insert-before-ack: [line 877](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Strand/Collect/Backfiller.swift#L868-L885) |
| SQLite schema | [`Packages/WhoopStore/.../Database.swift`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Packages/WhoopStore/Sources/WhoopStore/Database.swift) | `makeMigrator()` runs v1 through `v48-ecg-waveform` at this pin. `WhoopStoreInfo.schemaVersion` is still `18` ([WhoopStore.swift line 11](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Packages/WhoopStore/Sources/WhoopStore/WhoopStore.swift#L11)) and is not the migration count |
| Store actor, WAL checkpoint API | [`WhoopStore.swift`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Packages/WhoopStore/Sources/WhoopStore/WhoopStore.swift#L183-L208) | Upstream checkpoints on backup/import, not after every strap insert. The fork does. See below |
| On-disk path and file protection | [`Strand/Collect/StorePaths.swift`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Strand/Collect/StorePaths.swift#L1-L30) | `<Application Support>/OpenWhoop/whoop.sqlite`. iOS protection `completeUntilFirstUserAuthentication` so a locked phone can still open the file |
| Scores | [`Packages/StrandAnalytics`](https://github.com/ryanbr/noop/tree/2a1de7609843b095505274ad6fc811757210be80/Packages/StrandAnalytics/Sources/StrandAnalytics) | Milestone 2. Not part of the strap package |
| Debug sheet | Upstream has Test Centre and strap logs, not this sheet | [`clients/noop/Strand/Screens/SyncDebugSheet.swift`](https://github.com/ryanhill4L/noop/blob/0a6bad593a8966cd0d48056b40e362dcca4d040a/clients/noop/Strand/Screens/SyncDebugSheet.swift) at fork HEAD |

Android twins (`android/app/src/main/java/com/noop/ble`, `.../protocol`) mirror the Swift path. Aloft is iPhone-only. Leave them.

## Lessons checked against the repos

### The strap pairs with one app at a time

Upstream copy, shown when a WHOOP 5.0/MG scan finds nothing:

> WHOOP 5.0/MG pairs with one app at a time. If nothing's found, unpair it in the official WHOOP app and fully close that app, then Scan.

Source: [`Strand/Onboarding/OnboardingWizard.swift` line 564](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Strand/Onboarding/OnboardingWizard.swift#L564). Live view uses the same rule with slightly different wording ([`LiveView.swift` line 578](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Strand/Screens/LiveView.swift#L578)). Android says "bonds to one device at a time, so unpair it from the official WHOOP app first" ([`AddDeviceWizard.kt` line 925](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/android/app/src/main/java/com/noop/ui/AddDeviceWizard.kt#L925)). [`docs/BUILD.md` line 214](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/docs/BUILD.md#L214) and [`docs/ANDROID.md` line 468](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/docs/ANDROID.md#L468) say the strap must be out of range of the official app during initial bonding. [`docs/FEATURES.md` line 82](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/docs/FEATURES.md#L82) says only one host can hold it at a time.

Ryan's stronger note (pairing Aloft unpairs the official app, and the reverse) matches that "one at a time" behavior. These docs did not find a separate code path that programmatically tells the official app to forget the bond. Treat "unpair in the official app, then pair here" as the verified instruction.

### WAL durability

SQLite is WAL mode (`DatabasePool` in [`WhoopStore.swift`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Packages/WhoopStore/Sources/WhoopStore/WhoopStore.swift)). A commit is visible to the open pool and absent from `whoop.sqlite` until a checkpoint. Upstream's `checkpointWAL()` (`PRAGMA wal_checkpoint(TRUNCATE)`) runs around backup and import, not after strap inserts.

The fork lost synced history that way. Fix: [ryanhill4L/noop#3](https://github.com/ryanhill4L/noop/pull/3), merge commit [`ec303201`](https://github.com/ryanhill4L/noop/commit/ec3032010ff177098b304394d4a37380d4661264). After an insert that wrote rows, `WhoopStore.foldWALIntoMainFile` runs `PRAGMA wal_checkpoint(PASSIVE)`, then one `FULL` if frames remain, before `insert` returns and therefore before `Backfiller` acks the strap. Backgrounding calls `checkpointWAL()` (TRUNCATE) when the store is already open (`StrandiOS/App/StrandiOSApp.swift` in that commit). The store directory and `whoop.sqlite` / `-wal` / `-shm` are stamped `completeUntilFirstUserAuthentication` (upstream already did this in `StorePaths`; the fork stamps again after open and after checkpoint).

Tests, in the fork only: [`WALDurabilityTests.swift`](https://github.com/ryanhill4L/noop/blob/ec3032010ff177098b304394d4a37380d4661264/clients/noop/Packages/WhoopStore/Tests/WhoopStoreTests/WALDurabilityTests.swift).

- A raw insert is visible on the open pool and missing from a copy of the main file opened without `-wal`/`-shm`.
- `WhoopStore.insert` of one HR sample is still present in that main-file-only copy.

Aloft's store has to pass the same test, including a relaunch after the sidecars are deleted. Ack stays after that fold.

### XcodeGen drops plist keys that are not in the spec

[ryanhill4L/noop#4](https://github.com/ryanhill4L/noop/pull/4), on fork HEAD. `xcodegen generate` rewrites `StrandiOS/Resources/Info.plist` from the `NOOPiOS` target's `info.properties` in [`clients/noop/project.yml`](https://github.com/ryanhill4L/noop/blob/0a6bad593a8966cd0d48056b40e362dcca4d040a/clients/noop/project.yml). Purpose strings that existed only in the checked-in plist disappeared, which crashes camera capture. The spec now carries `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` (onboarding photo used to draw a figure).

If Aloft uses a generator, every Info.plist key lives in the spec. Otherwise skip the generator and edit the plist directly. Aloft's first milestone does not need camera or photo-library access.

### Simulator limits

[`BLEManager`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Strand/BLE/BLEManager.swift#L524-L526) says it cannot run in the Simulator and was verified on device. [`docs/IOS.md`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/docs/IOS.md#L354-L356) says the same: CoreBluetooth has no simulator support.

A search of upstream for Vision person-segmentation calls found none. The fork's camera strings are for a figure photo, and the implementation of that segmentation was not located in the files read here. Ryan's rule still stands for later UI: do not treat the Simulator as proof of Vision person segmentation.

## What to port

Rewrite these as one small Swift package plus a thin app. Behavior to keep, structure to shrink.

| Piece | Why |
|---|---|
| BLE scan, connect, bond, notify, write for WHOOP 4 (`61080001-…`) and WHOOP 5/MG (`fd4b0001-…`) | The product is the strap |
| Frame reassembly, CRC, the safe command subset, history offload, ack-after-durable-commit | Without this, sync lies |
| SQLite tables for samples the strap actually sends (HR, R-R, battery, events, the biometric history rows the first sync needs) and the WAL fold | Durability is the milestone 1 proof |
| A debug screen: connection, last sync, last error, row counts, recent log lines, copy/share | The only UI until sync is proven. Model it on the fork's `SyncDebugSheet` (link, bond, last sync, last error, path, main/WAL sizes, HR / R-R / daily / sleep counts, last 80 log lines, Copy, Share). Drop Focus mode and Test Centre |

## What to skip

| Piece | Why |
|---|---|
| `backend/` and `Packages/NoopShare` on the fork | Friends accounts and day summaries. Aloft has no server |
| `android/`, `NOOPWatch/`, `StrandiOSWidgets/`, menu bar | Other platforms and surfaces |
| `OuraProtocol`, `PolarProtocol`, Garmin/Huami/Xiaomi importers | Other devices |
| `StrandDesign` Liquid Metal, Charge/Effort/Rest naming, the onboarding figure photo | Different visual language. See [design.md](design.md) |
| Coach, journal, lift log, biofeedback, alarms, firmware load, DFU, `FORCE_TRIM` | Out of scope, and several of those commands are destructive |
| Most of `Database.swift` after the strap tables (Oura, lab book, lift log, ECG waveform, coach messages, …) | The migration chain is the whole NOOP product |
| `StrandAnalytics` until milestone 2, and then only recovery, strain, sleep, HRV, and resting HR | Scores are approximate and not required to prove a sync |

## Score code (later)

Pure functions. They do not touch SQLite. Upstream says they are approximate and not the proprietary WHOOP models.

| Score | File |
|---|---|
| Orchestrator | [`AnalyticsEngine.swift`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Packages/StrandAnalytics/Sources/StrandAnalytics/AnalyticsEngine.swift) (`analyzeDay` → `DayResult`) |
| Recovery (0–100, HRV-dominant) | [`RecoveryScorer.swift`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Packages/StrandAnalytics/Sources/StrandAnalytics/RecoveryScorer.swift) |
| Strain | [`StrainScorer.swift`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Packages/StrandAnalytics/Sources/StrandAnalytics/StrainScorer.swift). Output was rescaled from 0–21 to **0–100** ("Effort"). Official WHOOP strain is still 0–21. See [design.md](design.md) |
| Sleep stages | [`SleepStager.swift`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Packages/StrandAnalytics/Sources/StrandAnalytics/SleepStager.swift) (approximate 4-class). `SleepStagerV2.swift` is a second implementation; do not port both until one is chosen |
| HRV (RMSSD, SDNN) | [`HRVAnalyzer.swift`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Packages/StrandAnalytics/Sources/StrandAnalytics/HRVAnalyzer.swift) |
| Resting HR | [`PrimarySessionRestingHR.swift`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Packages/StrandAnalytics/Sources/StrandAnalytics/PrimarySessionRestingHR.swift) |
| Baselines the recovery score needs | [`Baselines.swift`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Packages/StrandAnalytics/Sources/StrandAnalytics/Baselines.swift) |

Cached outputs land in `dailyMetric` and `sleepSession` ([`Database.swift` v4](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Packages/WhoopStore/Sources/WhoopStore/Database.swift#L92-L121)).
