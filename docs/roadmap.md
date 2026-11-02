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

Out of this milestone: Today UI, scores, HealthKit, accounts, any network.

## 2 — Today

A single screen in the spirit of the official WHOOP app: recovery, strain, and sleep, computed on device from the stored strap data. Adaptive layout (one column when narrow, two panes when wide). Same screenshot pair as milestone 1, plus a device check that the numbers came from a real sync rather than a fixture alone.

Open until then: whether the strain dial shows WHOOP's 0–21 or NOOP's rescaled 0–100. See [design.md](design.md).

## 3+

Only after Today is in daily use. Candidates, not commitments:

- Trends for the three scores.
- HealthKit write, opt-in, on device.
- Sleep detail, then whatever Ryan asks for next.

Still out: cloud, friends sharing, watch app, widgets, Android, coach, firmware tools.
