---
type: log
created: 2026-09-05
status: active
supersedes: nothing
related:
  - docs/plans/2026-09-05-001-production-program.md
  - docs/plans/2026-09-05-002-phase1-contracts.md
---

# Phase 1 session notes

Written in the client repository while the vault (`~/trapLab-brain`) is under a data-loss
incident owned by another session; the lead merges these into the vault's development log after
recovery. One entry per lane and round, newest last.

## Client lane, RUST CORE, round 1 (2026-09-05)

What landed, all on `feat/labnet`:

- `Cargo.toml`: `Win32_NetworkManagement_IpHelper` added to the `windows` features as its own
  commit, the way WP10's two were, so CI proves the feature string before code is written
  against it.
- WP10, the disk platform layer, proven on real hardware for the first time. homebox-devserver
  (Lubuntu 26.04, kernel 7.0.0-30) carries a Micron 3400 NVMe and a Seagate ST1000VX008 SATA
  disk. A harness that compiled `src/labdesk/disk/` verbatim (source hashes recorded beside the
  output) ran as root: `NVME_IOCTL_ADMIN_CMD` answered the 512 byte log page (temperature 27 C,
  4,500 hours, 1 percent used, verdict `ok`, source `nvme_logpage`) and `SG_IO` with the ATA
  PASS-THROUGH(16) CDB answered the attribute table with a valid checksum (verdict `ok`, source
  `ata_smart`). Unprivileged, both refused and both drives reported `unreadable` with source
  `sysfs`, never `ok`. Three defects found by the hardware and fixed, tests first: attribute 9
  on the Seagate carries a second counter in its upper bytes (71 trillion hours as read; the low
  24 bits, 47,210, are the hours); the NVMe hwmon sits on the controller
  (`/sys/class/nvme/nvme0/hwmon1`), not under `device/`; and neither drive's firmware was read
  from sysfs. Both captures are committed as fixtures with their provenance in
  `src/labdesk/disk/fixtures/README.md`. `labdesk --disk-health` is the harness the crate now
  offers for the same check on any machine.
- WP13 on the agent: `src/labdesk/tools.json` (the catalog, byte for byte the Worker's copy) and
  `src/labdesk/tools.rs` (parse and check the catalog, validate parameters, build argv, run each
  step with `std::process::Command` under one timeout, cut output to 16 KiB with its SHA-256,
  refuse `already_ran` from a 256 entry ledger beside the identity file). The collector reads
  `jobs` and `collectNow` from the batch answer, runs jobs on a thread of their own, and sends
  at most four `jobResults` a batch. Section 11 of the contracts records the divergences: the
  pattern subset, the leading `-` refusal, the seat0 user appended to `power_logoff` on
  Linux, Linux `active_user` entries running in the daemon, Windows launches whose exit
  status is not observed. The site lane wrote its `tools.json` first (labels and 30 s power
  timeouts); the client adopted those bytes, and `cmp` of the two copies is silent.
- WP15, the ticket claim path: `Data::ConnectTicket` over the main IPC channel,
  `insert_pending_ticket` and `claim_pending_ticket` in `src/server/connection.rs` beside the
  switch-sides map (`cargo test claim_once`), the hook at the top of `validate_password`, the
  `handle_hash` branch in `src/client.rs` with `PasswordSource::Ticket`, and
  `src/labdesk/ticket.rs` reading `tickets` from the batch answer and delivering them.
- The self-heal switch: `selfheal::enabled()` parses the daemon's config file on every tick,
  `start()` spawns always, and the running step is published as `net.reachability`.
- The network view: `src/labdesk/netview.rs` walks `getifaddrs` on Linux and macOS, the
  collector sends `net.adapters` and `net.reachability` in the `attrs` member with the change
  rules in section 11 of the contracts. Windows sends no `net.adapters` until the
  `GetAdaptersAddresses` call is written against the feature above.

How it was checked before CI: the pure parts (`tools.rs`, `netview.rs`, `ticket.rs`,
`selfheal.rs`) were compiled and their 25 tests run on homebox in a shim harness
(`gauntlet-evidence/p1-rust-core/round-1/`); the disk module's 64 tests ran there too after the
fixes. `collector.rs`, `ipc.rs`, `connection.rs`, `client.rs` and `core_main.rs` are proven by
the CI run on the pushed head only.

Open after this round:

- Windows `net.adapters` (the `GetAdaptersAddresses` call).
- The exit status of an `active_user` launch on Windows.
- Field checks that need a built binary: `labdesk --disk-health` on homebox from the branch's
  own Linux build (the harness proved the module, not the shipped binary) and on Foundry, where
  the QEMU virtual disks cannot prove SMART and the honest expectation is `unreadable`; the
  self-heal switch flip on both; a job end to end and a ticket end to end, which also need an
  enrolled machine and therefore an owner-minted token.
- `CHANGELOG.md` and the program plan's phase 1 row carry another session's uncommitted edits
  in this checkout and were left alone.
