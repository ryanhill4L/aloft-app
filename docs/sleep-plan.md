# Sleep

Ryan wants three things: set an alarm in the app, have the app watch the night, and see a recap in the morning. His strap is a WHOOP 5.0/MG. Pairing works on a phone (main, including the off-wrist path from pull request 12). This page splits the rest into small pull requests. It does not start the Today screen, and it does not send health data to the backend.

## Questions for Ryan

These block the alarm screen and the recap. They do not block storing the night.

1. **Smart wake.** Should the alarm be a single time, or a window that tries to buzz near the end of a lighter stretch? If a window, how long (for example 20 or 30 minutes before the time he set)?
2. **Sleep goal.** A target duration (and where it is shown), or no goal?
3. **Morning recap.** A notification, a screen he opens, or both? If a notification, what one line should it say?
4. **Phone fallback.** If the strap never buzzes, should the phone fire its own alarm? The strap path is still experimental (one captured wake, on firmware 50.41.1.0, and this unit's firmware is unconfirmed). A phone alarm needs notification permission and will sound even if the strap is out of range.

## What already exists

| Piece | Where | State |
|---|---|---|
| Pair, encrypted hello on `fd4b0002`, off-wrist guidance | `StrapLink`, `Pairing` | On a real phone. The Simulator still has no Bluetooth path to a strap. |
| History offload (command 22), chunk ack (command 23) after the WAL is folded into `aloft.sqlite` | `HistorySync`, `StrapStore.insert` | Built and covered by package tests. Not yet shown on a night of Ryan's strap. An empty or undecoded chunk is still acked, which lets the strap trim those bytes. |
| Heart rate and R-R from WHOOP 5 layout 18 and WHOOP 4 layouts 5, 7, 9, 12, 24 | `Frame.historicalSamples` | Stored. R-R is already milliseconds. |
| Motion | was missing | This pull request. See below. |
| Respiratory rate in breaths per minute | not a field on layout 18 | Not stored. WHOOP 4 layout 24 has a raw ADC at absolute offset 80 (`resp_rate_raw` in NOOP's protocol JSON). That is not a rate, and it is not decoded here. |
| Alarm frames | `CommandEncoder` where the generation is WHOOP 5 | `SET_ALARM_TIME` (66) revision 4, 21 bytes, slots 1–6. `GET_ALARM_TIME` (67) reads the same record back. `RUN_ALARM` (68), `DISABLE_ALARM` (69) including `02 FF` for every slot. Buzz is command 19, not 79. The strap stores a one-shot and clears the slot when it fires, so the app re-arms on the next connect. A command result means the bytes were accepted, not that the motor moved. |
| Alarm controls | Log tab | Buzz, arm slot 1 two minutes out, read it back, disarm all. Debug controls, not a bedtime screen. |
| SQLite | `aloft.sqlite` in Application Support | `heart_rate`, `rr_interval`, `event`. `insert` checkpoints the WAL before it returns. File protection stays `completeUntilFirstUserAuthentication`. |

Offsets for the new fields were read from the fork's `clients/noop/Packages/WhoopProtocol` (Interpreter field table and the v18 tests) and from `whoop_protocol.json` for WHOOP 4 layout 24. They are not a +4 shift of the other generation. Layout 18 gravity is absolute 45/49/53 (float32, g). The strap's gravity-removed magnitude is absolute 41, kept only when it is inside 0...8 g. Byte 81 is a coarse band flag, not a stage: the high nibble is 0 wake, 1 still, 2 asleep, 3 up. Deep, REM, and light are not in that byte. WHOOP 4 layouts 12 and 24 carry gravity at absolute 40/44/48 and no byte 81.

## Pull requests

### 1. Overnight series — this one

Decode and store, per second, before the existing ack:

- Gravity in milli-g (1000 = 1 g), only when the vector magnitude is inside 0.25...4 g. A zeroed or absurd vector is dropped. Heart rate on that second is still stored.
- Dynamic acceleration in milli-g when the float is inside 0...8 g.
- The raw layout-18 byte 81, including zero. It is stored because an ack lets the strap delete the record, and the detector should be able to see the strap's own flag later. It is not shown as a stage.

The Log tab gains a motion-row count (rows that have gravity). The first history record of a connection logs `history layout <version>` once, so a device check can see whether this unit is actually on layout 18.

Reads for a time window: `heartRate(fromMs:throughMs:)`, `rrIntervals(fromMs:throughMs:)`, `motion(fromMs:throughMs:)`. Health data stays in this file.

### 2. Sleep detector

A pure function over one stored night. No Bluetooth and no network.

- In-bed start, sleep onset, wake, and duration.
- Efficiency as time asleep divided by time in bed, and only when both ends were found.
- Stages only if a small motion-and-heart-rate heuristic is worth showing. Label it as an on-device estimate. It is not WHOOP's model, and it is not medical. Byte 81 can be a hint and a later comparison point. It cannot be drawn as deep, REM, and light.
- Honest accuracy note on the screen and in this doc once the rule exists: what it uses, what it ignores (no breaths-per-minute channel, no cloud model), and that a match against Ryan's WHOOP numbers is still to be done.

### 3. Alarm screen

Depends on questions 1 and 4.

- Pick a time. Arm slot 1 with the revision-4 body. Read slot 1 back and show the epoch the strap stored, next to the time he picked.
- Re-arm on the next connect, because the slot clears when it fires.
- Smart wake, if he wants it, is "choose an epoch inside the window," not a new strap command. It needs the detector running while the phone is connected. Until that is proven, the screen sets the time he picked.
- Phone fallback, if he wants it, is a local notification at the same time. It is not a second source of truth for whether the strap buzzed.
- The Log tab buttons stay, so a phone can still buzz and disarm without the new screen.

### 4. Morning recap

Depends on questions 2 and 3, and on the detector.

- Duration, efficiency, heart rate from the stored night (mean, and the low stretch if it is obvious), stages only when pull request 2 produced them.
- A place to write the WHOOP app's numbers beside Aloft's, for him to compare later. Those notes stay on the phone.
- Notification, screen, or both, per question 3. Missing data stays missing. No score dial and no backend upload.

## Device checks still open

Not run from the Simulator.

- After a real sync, Log shows motion rows, and `history layout` in the strap log is 18. If heart-rate rows grow and motion stays at 0, this unit is not sending layout 18 and the offsets above must be re-read before anything is trusted. Sharing `strap-trace.log` is the way to look; do not commit the trace.
- A gravity sample from a still wrist is near 1000 milli-g in magnitude.
- The alarm questions already in [protocol-notes.md](protocol-notes.md): firmware on this strap, whether a stored alarm fires with the phone away, whether it fires only while the strap treats him as asleep, and how slots 1–6 behave.
- The recap, once it exists, against a morning he also reads in the WHOOP app.

## Out of this work

Today's recovery and strain dials, HealthKit, widgets, a watch app, and syncing health chunks to the API. Respiratory rate as breaths per minute, until a field or an on-device estimate is written down the same way the gravity offsets were.
