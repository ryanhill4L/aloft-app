# WHOOP strap protocol (as NOOP implements it)

Notes for Aloft, taken from upstream NOOP at [`2a1de760`](https://github.com/ryanbr/noop/commit/2a1de7609843b095505274ad6fc811757210be80). The authoritative write-up is NOOP's own set: start at [`docs/PROTOCOL.md`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/docs/PROTOCOL.md), then [`PROTOCOL_TRANSPORT.md`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/docs/PROTOCOL_TRANSPORT.md), [`PROTOCOL_COMMANDS.md`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/docs/PROTOCOL_COMMANDS.md), [`PROTOCOL_WHOOP4.md`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/docs/PROTOCOL_WHOOP4.md), and [`PROTOCOL_WHOOP5.md`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/docs/PROTOCOL_WHOOP5.md).

This page is the subset the first Aloft milestone needs. It is not a second protocol spec. Where NOOP marks a behavior as observed on one firmware, Aloft should too.

NOOP is not affiliated with WHOOP. Neither is Aloft.

Version baselines NOOP states: WHOOP 4 centered on firmware **41.17.6.0**; WHOOP 5/MG contracts on **50.42.1.0** unless a paragraph names an older capture. WHOOP 4 and 5 do not share a frame layout. Do not shift offsets from one generation onto the other.

Ryan's strap is a **WHOOP 5.0/MG** (2026-11-03). Firmware on that unit is still unconfirmed. Alarm and haptic frames are built for both generations; the 5/MG builders are the ones to send.

## Services and characteristics

UUID strings live in [`DeviceFamily.swift`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Packages/WhoopProtocol/Sources/WhoopProtocol/DeviceFamily.swift#L46-L53) and are repeated as `CBUUID`s in [`BLEManager.swift`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Strand/BLE/BLEManager.swift#L530-L549). The protocol package does not import CoreBluetooth.

### WHOOP 4.0 — service `61080001-8d6d-82b8-614a-1c8cb0f8dcc6`

| Role | UUID | Direction |
|---|---|---|
| Service | `61080001-8d6d-82b8-614a-1c8cb0f8dcc6` | |
| Command write | `…0002…` | app → strap |
| Command-response notify | `…0003…` | strap → app |
| Event notify | `…0004…` | strap → app |
| Data notify (fragmented) | `…0005…` | strap → app |

### WHOOP 5.0 / MG — service `fd4b0001-cce1-4033-93ce-002d5875f58a`

| Role | UUID |
|---|---|
| Service | `fd4b0001-cce1-4033-93ce-002d5875f58a` |
| Command write | `fd4b0002-…` |
| Notify | `fd4b0003`, `fd4b0004`, `fd4b0005`, `fd4b0007` (same suffix `-cce1-4033-93ce-002d5875f58a`) |

5.0 and MG share this service. NOOP tells some units apart with the Device Information Service (model `0x2A24`, serial `0x2A25`, hardware revision `0x2A27`): serial prefix `5AG` / hardware containing `WG50` read as 5.0, model `MG` or serial prefix `5AM` read as MG. Conflicting signals stay unresolved ([`PROTOCOL_WHOOP5.md`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/docs/PROTOCOL_WHOOP5.md#L62-L83)).

Other custom services (`11500001-…`, Monument `8a580001-…`, Symphony `59830001-…`) are diagnostic-only in `WhoopGattServiceFamily`. NOOP does not connect them.

### Standard SIG services (both generations)

From `BLEManager`: Heart Rate service `180D` / measurement `2A37` (HR and R-R; works without an encrypted bond on 5/MG), Battery `180F` / `2A19`. WHOOP 4's proprietary battery command is the one to trust when both exist; the standard battery characteristic has been observed stuck at 100 ([transport doc](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/docs/PROTOCOL_TRANSPORT.md#L114-L121)).

## Bond and connect

WHOOP 4, from [`PROTOCOL_WHOOP4.md`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/docs/PROTOCOL_WHOOP4.md#L98-L127): scan the custom service, connect, discover, one confirmed write (NOOP uses `GET_BATTERY_LEVEL`) on `…0002`, subscribe `…0003` / `…0004` / `…0005` / `2A37` / `2A19`. A write acknowledgement is not proof of a persistent OS bond. Command traffic is treated as usable after one confirmed write succeeds. There is no fixed client-hello (`DeviceFamily.whoop4.clientHello` is `nil`).

Then, once per connection: `GET_HELLO_HARVARD` (35), `GET_ADVERTISING_NAME_HARVARD` (76), `REPORT_VERSION_INFO` (7), `SET_CLOCK` (10), `GET_CLOCK` (11), `SEND_R10_R11_REALTIME` (63) with `[0x00]` to stop the type-43 flood, `GET_DATA_RANGE` (34), then the first history offload. Clock command forms are outside the documented 41.17.6.0 set; read the clock back.

WHOOP 5/MG: write this fixed 16-byte client hello to `fd4b0002` with a response, and only then subscribe the fd4b notify characteristics. The confirmed write is what asks the OS to start a just-works bond. Subscribing `fd4b0003` / `0004` / `0005` / `0007` first is refused (authentication or encryption insufficient) and wedges that bond. The bytes are command 145, not a key exchange ([`DeviceFamily.whoop5ClientHello`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Packages/WhoopProtocol/Sources/WhoopProtocol/DeviceFamily.swift#L270-L274), and the later hardware-verified order in noop `BLEManager.didDiscoverCharacteristics`, issue 17):

```text
AA 01 08 00 00 01 E6 71 23 01 91 01 36 3E 5C 8D
```

`LiveState` separates `bonded` from `encryptedBond`. On 5/MG, standard-profile HR can set `bonded` without an encrypted link. History, haptics, and alarms need `encryptedBond` ([`LiveState.swift`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Strand/BLE/LiveState.swift#L14-L26)).

One host at a time: see [noop-reference.md](noop-reference.md). Straps do not show up under system Bluetooth settings ([`docs/FEATURES.md`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/docs/FEATURES.md#L60-L61)).

## Frame format

CRCs are implemented in [`Framing.swift`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Packages/WhoopProtocol/Sources/WhoopProtocol/Framing.swift): CRC-8 poly `0x07` over the two length bytes (WHOOP 4 header), CRC-16 Modbus poly `0xA001` init `0xFFFF` (WHOOP 5 header), zlib CRC-32 poly `0xEDB88320` over the inner bytes (both).

### WHOOP 4

```text
AA | length u16 LE | crc8 | type | seq | cmd | payload… | crc32 u32 LE
```

`length` is the offset of the CRC-32 trailer. Total size is `length + 4`. Accept only when length ≥ 7, the frame is long enough, CRC-8 matches byte 3, and CRC-32 matches. Data-characteristic notifications fragment; reassemble to the declared size before decoding. Command responses are packet type 36: command at offset 6, originating sequence at 7, result at 8, body at 9.

### WHOOP 5/MG format 1

| Offset | Width | Meaning |
|---:|---:|---|
| 0 | 1 | `aa` |
| 1 | 1 | format `01` |
| 2 | 2 | declared length = complete size − 8 |
| 4 | 2 | header fields (`00 01` on many requests, `01 00` on responses) |
| 6 | 2 | CRC-16 over bytes 0–5 |
| 8 | 1 | packet type (35 = command) |
| 9 | 1 | sequence |
| 10 | 1 | command number |
| 11 | … | body, zero-padded to a multiple of 4 |
| end−4 | 4 | CRC-32 over the padded body from offset 8 |

A response has type 36 at offset 8, command at 10, **originating request sequence at 11**, result at 12, body at 13. Correlate on command plus origin sequence, not on the response's own sequence byte.

Result bytes NOOP records: 0 failure, 1 success (not proof the async work finished), 2 pending, 3 unsupported, anything else unknown.

## Packet types

From [`whoop_protocol.json`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Packages/WhoopProtocol/Sources/WhoopProtocol/Resources/whoop_protocol.json#L4-L10):

| Type | Name | Role in sync |
|---:|---|---|
| 35 | `COMMAND` | App → strap |
| 36 | `COMMAND_RESPONSE` | Strap → app |
| 38 | `PUFFIN_COMMAND_RESPONSE` | Aliased to `COMMAND_RESPONSE` |
| 40 | `REALTIME_DATA` | Live. Dropped during offload |
| 43 | `REALTIME_RAW_DATA` | Live raw flood. WHOOP 4 stops it with command 63 |
| 47 | `HISTORICAL_DATA` | Stored records. Layout depends on the version byte |
| 48 | `EVENT` | Wrist on/off, battery, double-tap, … |
| 49 | `METADATA` | History start / end / complete |
| 50 | `CONSOLE_LOGS` | Strap debug text. Not biometric rows |
| 56 | `PUFFIN_METADATA` | Aliased to `METADATA` |

`MetadataType`: 1 `HISTORY_START`, 2 `HISTORY_END`, 3 `HISTORY_COMPLETE`.

## Commands Aloft should know

The full matrix is IDs 1–159 in [`PROTOCOL_COMMANDS.md`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/docs/PROTOCOL_COMMANDS.md#L61-L223). [`WhoopCommand`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Strand/BLE/Commands.swift#L1-L45) is the curated send list. Firmware load, DFU, force-trim, and fuel-gauge reset are excluded so the app cannot form those bytes.

Milestone 1 send list (names as in NOOP):

| ID | Name | Use |
|---:|---|---|
| 22 | `SEND_HISTORICAL_DATA` | Start offload. WHOOP 4 body `00` does not require the 5/MG range preflight |
| 23 | `HISTORICAL_DATA_RESULT` | Ack a chunk. Body `01` plus the 8-byte end block. Only after a durable commit |
| 20 | `ABORT_HISTORICAL_TRANSMITS` | Stop an offload. Not a trim. Unacked records stay on the strap |
| 34 | `GET_DATA_RANGE` | Stored range |
| 26 | `GET_BATTERY_LEVEL` | WHOOP 4 percent is `u16le / 10` |
| 35 | `GET_HELLO_HARVARD` | WHOOP 4 identity. The response also carries key material; do not log that region |
| 145 | `GET_HELLO` | 5/MG hello (name, firmware). A 4.0 answers unsupported |
| 10 / 11 | `SET_CLOCK` / `GET_CLOCK` | 5/MG also has 146 / 147 |
| 63 | `SEND_R10_R11_REALTIME` | WHOOP 4: `[0x00]` stops the type-43 flood |

Do not send `FORCE_TRIM` (25), `SET_READ_POINTER` (33), or the image-transfer and certificate commands. An ack that advances the trim lets the strap delete history the phone does not have.

## History flow

WHOOP 4, from the transport doc and `Backfiller`:

1. Command 22 starts the offload.
2. Type 49 metadata marks START, END, and COMPLETE. Type 47 frames between markers are records.
3. On END, keep the 8-byte acknowledgement block verbatim. WHOOP 4: frame bytes 17–24 (`Backfiller.endData` uses 17 for WHOOP 4 and 21 for WHOOP 5). First `u32` is the trim cursor. Do not rebuild the block from decoded timestamps.
4. Persist decoded rows. If the write throws, return without acking so the strap re-sends the chunk (`finishChunk` in `Backfiller`).
5. Then send command 23, body `01 || end_data[8]`.
6. COMPLETE ends the session. It does not commit an open chunk. Timeouts do not authorize an ack.

WHOOP 5/MG uses the same command numbers on the puffin envelope. High-frequency sync can send one START and repeated ENDs; each END is its own chunk and each must be acked. NOOP's `enterHighFreqSync` (96) is marked unconfirmed in `Commands.swift` (never sent by a build in that repo's history). Do not add it in milestone 1 unless a capture shows the strap already sitting in that mode.

The fork's extra rule: `insert` must fold the WAL into `whoop.sqlite` before it returns, so the ack cannot race a checkpoint that never happened. See [noop-reference.md](noop-reference.md).

## Alarms, haptics, and events

5/MG is the path to prove. NOOP treats 5/MG alarm execution as experimental: one captured strap-driven wake, on firmware **50.41.1.0**. A command acknowledgement is not that wake ([`PROTOCOL_ALARMS.md`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/docs/PROTOCOL_ALARMS.md#L7)). WHOOP 4's nine-byte SET is the confirmed frame (NOOP pull request 535) and stays buildable so it cannot be confused with the 5/MG record.

Sources for the bodies: [`PROTOCOL_ALARMS.md`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/docs/PROTOCOL_ALARMS.md), [`whoop_protocol.json`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Packages/WhoopProtocol/Sources/WhoopProtocol/Resources/whoop_protocol.json) `CommandNumber` and `EventNumber`, [`Commands.swift`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Strand/BLE/Commands.swift) `setAlarmPayload`, and the 5/MG golden in [`DeviceFamilyFramingTests.swift` line 349](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Packages/WhoopProtocol/Tests/WhoopProtocolTests/DeviceFamilyFramingTests.swift#L349). The WHOOP 4 byte string is the 7:00 capture in the unlicensed [bWanShiTong README line 114](https://github.com/bWanShiTong/reverse-engineering-whoop-post/blob/master/README.md#L114); only those bytes are used.

The strap stores a one-shot. It compares whole seconds about twice a second, emits event 57, and clears the slot. The app has to re-arm on the next connect. Event 58 is an app-triggered run. Event 56 is alarm set.

| ID | Name | 5/MG body | WHOOP 4 body |
|---:|---|---|---|
| 66 | `SET_ALARM_TIME` | Rev 4, 21 bytes: `04 \|\| slot 1–6 \|\| epoch u32le \|\| fraction u16le` (1/32768 s) `\|\|` effects `2F 98` then six zeros `\|\|` loop `u16le` 0 `\|\|` repeats 7 `\|\|` duration 30 `\|\|` crescendo 0 | `01 \|\| epoch u32le \|\| 00 00 00 00` |
| 67 | `GET_ALARM_TIME` | `04 \|\| slot`. The reply is that same record | `01` |
| 68 | `RUN_ALARM` | `02 \|\| slot` | `01` |
| 69 | `DISABLE_ALARM` | `02 \|\| slot`, or `02 FF` for all six | `01` |
| 19 | 5/MG buzz | `01 2F 98` then six zeros, loop `00 00`, then `repeats − 1` (clamped to 0–7) | Do not send. On a WHOOP 4 this number is `SET_R7_REALTIME_STREAM` |
| 79 | `RUN_HAPTICS_PATTERN` | Do not send. A 5/MG answers result 3 | `02 03 00 00 00` (preset 2, three loops) |
| 122 | `STOP_HAPTICS` | `01` | `00` |

Command 19 exists only on the 5/MG encoder. Command 79 exists only on the WHOOP 4 encoder. The shared command enum does not carry either number, so the wrong generation cannot name it.

### Responses and events

Type 36, from `COMMAND_RESPONSE` in `whoop_protocol.json` and [`FrameRouter.commandResultByte`](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/Strand/BLE/FrameRouter.swift): the four bytes at **5/MG offsets 10–13** (WHOOP 4 offsets 6–9) are the command, the request's sequence, the result, and the first body byte. Result codes: 0 failure, 1 success, 2 pending, 3 unsupported. Anything else stays the raw number. Success means the strap accepted the bytes, not that the motor moved. Hello replies carry key material; log the result, not the body.

Type 48, from the `EVENT` fields in `whoop_protocol.json` (id at offset 6, timestamp `u32le` at offset 8; add four on 5/MG):

| ID | Name |
|---:|---|
| 9 | wrist on |
| 10 | wrist off |
| 14 | double tap |
| 56 | alarm set |
| 57 | alarm fired |
| 58 | alarm fired by app |
| 60, 100 | haptics fired (60 is `HAPTICS_FIRED`, 100 is `HAPTICS_TERMINATED`; the raw id is kept) |

Any other id is stored as its number. Event frames are not history records. They are written to the on-device `event` table, and that insert folds the WAL before it returns, same as `heart_rate`.

### Device checks

Not run yet. A phone and Ryan's 5.0/MG have to answer these:

- Firmware on this unit. The captured 5/MG wake was 50.41.1.0; this strap may differ.
- Whether a strap-stored alarm fires with the phone away.
- Whether it fires only while the strap treats the wearer as asleep.
- Slot behaviour: which of 1–6 holds the alarm, whether `02 FF` clears every slot, and whether two slots due together both fire.

## Open questions

- Firmware on Ryan's 5.0/MG, and therefore which hello behaviour and which history offsets to confirm on that unit. The generation itself is a 5.0/MG.
- Whether an unacknowledged `HISTORY_END` is retransmitted byte-for-byte, and what replay looks like after a disconnect. NOOP lists both as unknown for the WHOOP 4 baseline ([transport doc](https://github.com/ryanbr/noop/blob/2a1de7609843b095505274ad6fc811757210be80/docs/PROTOCOL_TRANSPORT.md#L110-L112)).
- WHOOP 4 reboot frame. Opcode 29 with an empty body is confirmed on 5.0 firmware 50.40.1.0 and ignored by a 4.0 in NOOP's notes (`Commands.swift`). Not needed for milestone 1.
- Command 96's wire value. NOOP's comment says an APK decompile disagrees by 11. Leave it unset.
- Absolute ECG timing, SpO₂ calibration, and most physiological field meanings. Out of scope until a later milestone, and still unresolved in NOOP's protocol index.
- Format 2 on WHOOP 5/MG is a separate contract in the transport doc. Milestone 1 should implement the format the strap actually emits and refuse the other, not guess.
- The alarm device checks in the section above: phone-away firing, the asleep-only hypothesis, and 5/MG slot behaviour. 5/MG alarm support stays experimental until those are seen on Ryan's strap.
