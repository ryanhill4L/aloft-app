# Decisions

Short log. Newest at the bottom. A reversal gets a new entry; old entries stay.

## 1. Restart from zero

Aloft does not continue [ryanhill4L/noop](https://github.com/ryanhill4L/noop). That fork vendors upstream NOOP under `clients/noop` and adds a friends backend. It also grew widgets, a watch app, Android, and a UI Ryan found confusing. The strap path is the part worth keeping, and it is small enough to rewrite against the reference instead of inheriting the targets.

Date: 2026-11-02. Status: accepted.

## 2. One Swift package for the strap

Pairing, framing, history sync, and the SQLite store land in a single package with a small public surface. NOOP splits `WhoopProtocol`, `WhoopStore`, `StrandAnalytics`, and a very large `BLEManager`. Aloft keeps the useful boundary (decode and SQL stay free of SwiftUI; CoreBluetooth stays at the edge) without the package count. Analytics stays out of the package until milestone 2, and then only if pulling it in would not bloat the strap API.

Date: 2026-11-02. Status: accepted. The package name and whether persistence uses GRDB (MIT, as NOOP does) or SQLite another way are still open.

## 3. On device only

No account, no backend, no analytics SDK, no friends share. The fork's `backend/` and `NoopShare` package are the counterexample. SQLite on the phone is the store. Sync ack happens after the WAL is folded into the main file.

Date: 2026-11-02. Status: accepted.

## 4. WHOOP-style UI, not Neka and not NOOP's Liquid Metal

The interface to aim at is the official WHOOP app: dark, recovery / strain / sleep first. NOOP's shipped look is Charge / Effort / Rest on a 0–100 effort scale, with its own design system. The fork's onboarding figure (camera and photo-library purpose strings in `project.yml`) is the Neka-style surface to leave behind. Milestone 1 is a debug screen and does not pick colors.

Date: 2026-11-02. Status: accepted. The strain dial's numeric scale (0–21 vs 0–100) is open; see [design.md](design.md).
