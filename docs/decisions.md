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

## 5. A backend for the profile and the Crew (partly reverses 3)

Ryan asked for a backend in Go with the database and auth on Neon, because Aloft needs a profile and a Crew. Health data still stays on the phone: heart rate, R-R, HRV, sleep, and scores live in the on-device store and Apple Health. The server holds the profile (name, birth year, height, weight, sleep window), Crew membership, one weather word per person per day (Clear, Fair, Overcast), and Lifts. A Crew sees weather, never numbers. The strap path makes no network calls. Ryan expects to sync health chunks to the backend later; that needs its own entry before any code.

Shape copies the lockecoffee monorepo: `proto/` is the contract, Connect-RPC over HTTP, generated Go and Swift, goose migrations that run at server start, Neon-tuned `database/sql` pool. Smaller on purpose: one service, `log/slog`, pgx instead of lib/pq.

Date: 2026-11-02. Status: accepted.

## 6. Sign-in is email code or Apple, through Neon Auth

The design signed people up by phone number. Neon's managed Better Auth supports phone OTP for existing users only, with a bring-your-own SMS provider, so Ryan chose email or Apple instead and no phone number. The app calls Neon Auth's REST endpoints directly (`/email-otp/send-verification-otp`, `/sign-in/email-otp`, `/sign-in/social` with an Apple identity token), keeps the session cookies in the Keychain, and trades them for a 15-minute EdDSA JWT from `/get-session`. The Go API verifies that JWT against the branch's JWKS and uses `sub` as the user id.

Open: Apple sign-in needs the Apple provider configured in Neon (client id = the real bundle id) and a team id in `ios/Config/Local.xcconfig`. Neither is in git. Production email needs a custom SMTP provider in Neon; the shared sender is for development.

Date: 2026-11-02. Status: accepted.

## 7. The Aloft design canvas is the visual source (supersedes the look in 4)

The Aloft design (11 screens in five iPhone Duo postures, its own tokens) replaces "follow the official WHOOP app" for color and type. Recovery bands become weather words: Clear (sky) 67–100, Fair 34–66, Overcast 0–33, never red. Type is Host Grotesk, IBM Plex Mono, and Newsreader italic (all OFL, bundled). Layout still follows design.md's rule: split by window size, never by device or hinge. Posture-only ideas in the canvas (resting the band on the open screen to pair, the half-folded sky clock) are not built: they need posture detection or hardware behavior that does not exist.

Date: 2026-11-02. Status: accepted.

## 8. Strap package: AloftStrap, system SQLite

Closes the open question in 2. The package is `AloftStrap` and talks to the system SQLite C API directly instead of taking GRDB. `StrapStore.insert` folds the WAL (PASSIVE, then FULL if frames remain) before it returns; `HistorySync` acks only after that. Tests cover the main-file-only copy and a relaunch with `-wal`/`-shm` deleted.

Date: 2026-11-02. Status: accepted.

## 9. The API runs on Cloud Run, managed by Terraform

Ryan chose Google Cloud Run for the Go API and Terraform to manage it (Pulumi was tried first and dropped the same day). `infra/` enables the APIs, builds `backend/` for linux/amd64 into Artifact Registry, keeps the Neon `main` pooled connection string in Secret Manager, and runs one Cloud Run service in `us-east4`, the region closest to Neon's aws-us-east-1. Scaling is 0 to 1 instances because migrations run at start. Invoke is public; every RPC still needs a Neon Auth JWT. Ryan stores the database URL in Secret Manager with `gcloud`; Terraform only names the secret and grants the API's service account access, so the URL is never in a file, in state, or in a plan. State lives in a GCS bucket; `terraform.tfvars` and `backend.hcl` name the project and stay out of git.

Neon stays outside Terraform for now. The project already exists, and the community `kislerdm/neon` provider has no Neon Auth resource. Neon Auth settings (the Apple provider, SMTP, the trusted origin) are a separate step.

Date: 2026-11-03. Status: accepted.
