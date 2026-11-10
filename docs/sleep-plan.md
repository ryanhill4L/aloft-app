# Sleep

Ryan wants three things: set an alarm in the app, have the app watch the night, and see a recap in the morning. His strap is a WHOOP 5.0/MG. Pairing works on a phone (main, including the off-wrist path from pull request 12). This page splits the rest into small pull requests. It does not start the Today screen, and it does not send health data to the backend.

## Decided

Ryan, 2026-11-04:

1. **Smart wake.** Yes. A 30-minute window that ends at the time he set.
2. **Sleep goal.** 8 hours.
3. **Morning recap.** A notification and a screen.
4. **Phone alarm.** No. The strap buzz is the only alarm. The phone does not sound if the strap misses it.

The 5/MG `SET_ALARM_TIME` revision-4 record is one epoch. It has no window field (NOOP `docs/PROTOCOL_ALARMS.md`, WHOOP 5/MG section). The guaranteed buzz is armed at the end of the window. An earlier buzz, if the phone is connected and the minute is a stir or a wake, is a separate strap buzz, then the slot is cleared so the deadline does not fire again.

The week repeats on the phone. Aloft arms only the next enabled morning, on slot 1, and writes the following one after that buzz. Whether slots 2–6 can be pre-armed with later mornings, so a night with no phone still buzzes, is open. It has not been tried on this strap.

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

A pure function over one stored night. No Bluetooth and no network. `stages` is nil.

- A minute is asleep when motion is at or under 0.015 g and heart rate is missing or at most 75. Beat intervals supply the rate only when the heart-rate byte is missing. A minute over 0.040 g, or a heart rate of 90 or more, is awake. Anything between is a stir (`restless`), not a stage.
- Onset is the first 10 asleep minutes. Wake is the first 5 awake minutes after that. The end of the recording is not a wake, so efficiency stays nil until a wake is found. Efficiency is time asleep divided by time in bed.
- Light, deep, and REM are not estimated. There is no breaths-per-minute channel and no cloud model. A match against Ryan's WHOOP numbers is still to be done on a real night.
- Smart wake uses the same minutes: inside the 30 minutes before the deadline, a stir or a wake that follows sleep asks for an early strap buzz. It does not move the deadline.

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
