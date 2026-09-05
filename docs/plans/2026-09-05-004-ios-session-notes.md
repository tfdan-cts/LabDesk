---
type: session-notes
created: 2026-09-05
status: open
related:
  - docs/IOS.md
  - docs/research/2026-09-05-ios-reference-teamviewer.md
  - docs/plans/2026-09-05-001-production-program.md
---

# iOS lane, session notes

What was actually done, in order, with the evidence for each claim. Anything not
proved by a tool result is marked unverified. The branch is `feat/ios`, cut from
`feat/labnet` at `bb8ccd682`, worked in the worktree
`.claude/worktrees/ios`. Nothing here has been merged anywhere.

There is no Mac in this fleet, so every iOS claim below rests on a GitHub
Actions macOS runner. Evidence that does not fit in the repository (CI logs,
screenshots, downloaded artifacts) is kept under the session scratchpad at
`AppData/Local/Temp/claude/C--Users-DVonR/275fde7d-4fb4-405a-9436-e65532de5402/scratchpad/ios/`.

## Ground truth, established before building

Three questions, three answers, each from a tool result rather than a reading of
the code.

**Why the iOS CI job reports skipped.** The job `build rustdesk ios ipa` in
`.github/workflows/flutter-build.yml` carries its own
`if: ${{ inputs.upload-artifact }}`, and `flutter-ci.yml`, which is Full Flutter
CI, calls the reusable workflow with `upload-artifact: false`. The job therefore
evaluates false and skips. It runs only from `labdesk-dispatch.yml`,
`flutter-nightly.yml` and `flutter-tag.yml`. Nothing was broken; the skip is the
workflow doing what it was told.

**Whether the inherited iOS target builds on a macOS runner.** Not since this
morning. The job last succeeded in run 33931151246 at 2026-09-05T00:01Z, then
failed in runs 33944666923 and 33948273476 with four `E0433` errors at
`src/client.rs` lines 401, 402, 479 and 480: `crate::ipc::set_option_async` on a
platform where `src/lib.rs` declares `pub mod ipc` under
`#[cfg(not(any(target_os = "ios")))]`. `git log -L` on those lines named
`b3fe22bc5` as the commit that introduced it. This was reported to dvonr-02,
who owns that file; the fix is theirs, committed as `82a6d8f27`, and it was
reviewed here before it landed. Until it lands on `feat/labnet` and this branch
rebases onto it, no iOS build of any kind can be green.

A separate fact worth recording: the successful iOS runs produced nothing to
download. The artifact upload and release steps of that job are commented out,
so no iOS build has ever left this repository.

**What the mobile entry point renders.** `flutter/lib/main.dart:49` sends any
non-desktop platform to `runMobileApp`, which at line 181 calls `runApp(App())`,
and `App.build` sets `home` to `HomePage()` for the non-desktop non-web case.
That is upstream's `flutter/lib/mobile/pages/home_page.dart`, whose `initPages`
builds a connection page and a settings page on iOS; the chat and incoming
service tabs are gated on `isAndroid`. The LabDesk console is desktop only:
every console screen is under `flutter/lib/desktop/`. Two pieces are already
shared and usable from the phone, `flutter/lib/common/labdesk_profiles.dart` and
`flutter/lib/common/labdesk_status_binding.dart`; dvonr-02 confirmed neither is
mid-change, though the phase 1 console work is actively editing
`flutter/lib/labdesk/` and consumes the status binding.

## Piece 1: the verification path

The strongest verifier available without a Mac is a booted simulator on a macOS
runner. Before writing that job, a throwaway probe workflow measured the runner
rather than assuming it (run 33982479503, deleted in the same commit that added
the real job):

- `macos-latest` is arm64, macOS 26.6.2, Xcode 26.6.
- Simulator runtimes present: iOS 26.2, 26.4 and 26.5. Device types include
  iPhone 11 through iPhone 17.
- All four Rust iOS targets are installable, including `aarch64-apple-ios-sim`.
- vcpkg carries `arm64-ios-simulator` as a community triplet.

That last line decided the shape of the job. An iOS simulator build needs
simulator slices of libvpx, libyuv, aom and opus, and `arm64-ios` builds device
slices; without a simulator triplet the job would have had to hunt an Intel
runner. `macos-13` never scheduled during the probe and is treated as gone.

`.github/workflows/ios-verify.yml` is the result. It reuses `bridge.yml` rather
than copying the codegen, builds the Rust core for `aarch64-apple-ios-sim`
without `hwcodec` (matching the inherited `flutter/ios_x64.sh`), builds the app
with `flutter build ios --simulator --debug`, creates and boots an iPhone 17,
installs and launches the app, screenshots it at three, seven and ten seconds,
collects its log, and uploads all of it. It fails unless `launchctl` inside the
simulator still lists the app twenty seconds after launch.

One shortcut is deliberate and marked in the workflow: `Runner.xcodeproj` links
`target/aarch64-apple-ios/release/liblibrustdesk.a` as a literal path, so the
job copies the simulator slice to that path instead of forking the project file
for a job that never ships a build. The device build in `flutter-build.yml` is
untouched by it.

**Unverified as of this note.** The job has not yet completed a green run. Run
33982913736 is the first attempt. It is expected to fail at the Rust build until
`82a6d8f27` lands, and neither the vcpkg `arm64-ios-simulator` install nor the
`flutter build ios --simulator` step has been observed to succeed even once.
Nothing in `docs/IOS.md` claims otherwise.

## Piece 2: the target's identity

Changed, and each verified by reading the file back:

- `PRODUCT_BUNDLE_IDENTIFIER` in all three build configurations from
  `com.carriez.flutterHbb` to `net.lab-desk.LabDesk`. That prefix already exists
  in the project: the Linux packaging ships a polkit action named
  `net.lab-desk.LabDesk.install-update`, so this is not an invented identifier.
- `DEVELOPMENT_TEAM = HZF9JMC8YN`, upstream RustDesk's team, removed from all
  three configurations rather than replaced. There is no LabDesk team identifier
  until the owner holds an Apple Developer membership, and an empty team is the
  truthful state.
- `CFBundleDisplayName` and `CFBundleName` from `RustDesk` to `LabDesk`, and
  `CFBundleURLName` from `com.carriez.rustdesk` to `net.lab-desk.LabDesk`.
- `Runner.entitlements` reduced to an empty dictionary carrying the reason.
  Upstream asked for `aps-environment`, which needs a membership and which this
  application does not use, and
  `com.apple.developer.networking.wifi-info`, which nothing here asks for. A
  grep of `src/` and `flutter/lib/` found no SSID or network-name reader.
- The app icon set regenerated from `res/icon.png`, which already carries the
  LabDesk mark while the iOS icons still carried RustDesk's blue ring. The
  generator is committed at `flutter/tool/make_ios_app_icons.py`. It writes
  square opaque images with no alpha and no pre-applied rounding, because the
  App Store rejects a marketing icon with an alpha channel and iOS applies its
  own corner mask.
- The camera and photo library purpose strings rewritten to say what LabDesk
  actually does with each.

Both plists were parsed with `plistlib` after editing, and all three files kept
their CRLF endings.

**Left alone on purpose.** The `rustdesk://` URL scheme. It is parsed by shared
Dart in `flutter/lib/common.dart` and declared in the Android manifest, so
renaming it is a coordinated change across three clients rather than an iOS
decision. It is recorded in `docs/IOS.md` as an open branding item.

**Unverified.** None of these values has been seen in a built application yet.
The workflow reads the bundle identifier and display name out of the built app
and prints them, so the first green run will either confirm them or not.

**Still upstream's answer.** `ITSAppUsesNonExemptEncryption` is `false` in
`Info.plist` and has not been checked against what the Rust core actually does
with cryptography. Answering it truthfully is a Tier 1 item and its own piece of
work.

## Piece 3: the machine list, Tier 1 item 4

Written test first. The seven tests in
`flutter/test/labdesk_ios_machine_list_test.dart` were red before the widget
existed and are green now; the whole `flutter test -j 1 test/labdesk_*.dart`
gate passes at 350 tests.

The find that shaped it: `buildMachineRows` in
`flutter/lib/labdesk/console_data.dart` is plain Dart with no FFI and no
platform gating, and `LabDeskPeerStatusStore` already holds real per-peer
three state reachability. So the phone did not need a reachability model of
its own; it needed a list widget over the one that exists. Two
implementations of three states would have drifted, and the desktop one is
the one dvonr-02 named as correct.

Worth recording because it was checked rather than assumed: the store does
get fed on the phone. `_attachLabDeskStatus` in
`flutter/lib/models/peer_model.dart` registers the online-state handler once
for the whole application, and `flutter/lib/common/widgets/peers_view.dart`,
which the mobile peer tabs use, already calls `bind.queryOnlines`. So the
dots carry real answers rather than sitting at unknown forever.

Also worth recording, because it contradicts a first reading: the shared
`getOnline` in `flutter/lib/common/widgets/peer_card.dart` still renders the
old two state model, a global `labdeskStatusChecking` flag plus a boolean,
so a peer nobody has asked about draws red there. That widget is shared with
the desktop client and was left alone. The machine list does not use it.

Files: `flutter/lib/mobile/widgets/machine_list.dart` (pure, no FFI),
`flutter/lib/mobile/pages/machines_page.dart` (wiring), one gated insertion
into `flutter/lib/mobile/pages/home_page.dart`. `dart analyze` on all three
returns four infos and no errors; three are `withOpacity` deprecations,
which the rest of this codebase also carries, and one is a pre-existing
`WillPopScope`.

**Unverified.** Nobody has looked at this list running. Widget tests prove
the rules, not the look, and the look cannot be judged until the simulator
job is green.

## Piece 4: the encryption declaration, Tier 1 item 9

`ITSAppUsesNonExemptEncryption` was `false`, inherited from upstream. It is
now `true`, and the reasoning is in `docs/IOS.md` with both Apple pages
cited.

The code side, read rather than remembered: `libs/hbb_common/Cargo.toml`
pulls `sodiumoxide 0.2`, and `src/common.rs`, `src/client.rs`,
`src/server.rs` and `src/custom_server.rs` use `crypto::box_`,
`crypto::secretbox`, `crypto::sign` and `crypto::hash::sha256`. Transport is
`tokio-rustls` with `ring` and `rustls-platform-verifier`, so the TLS is the
application's own rather than the system's. `openssl` is scoped in
`Cargo.toml` to Linux and Android and is not compiled for iOS.

The Apple side: the exemption is for an app whose encryption is limited to
what is within the Apple operating system. This one bundles libsodium and a
TLS stack, so it is not that app, and Apple says the developer carries the
liability for claiming an exemption inaccurately.

**Unverified, and owner work.** Whether a French encryption declaration is
needed depends on distributing in France, and whether anything more than
self classification is needed is a determination against the Export
Administration Regulations that Apple explicitly leaves to the developer.
Nothing has been filed and there is no account to file it against.
`ITSEncryptionExportComplianceCode` is left absent on purpose: that key
holds a code Apple issues after approving uploaded documentation, and
writing one there would be inventing it.

## Open items

- Rebase onto `feat/labnet` once `82a6d8f27` is pushed there, then rerun the
  verification workflow and read the screenshots.
- Nothing has been added to `CHANGELOG.md` yet. There is no iOS build a user
  can obtain, and the file is shared with another session's work in flight, so
  one entry covering the lane will be written when the first green simulator run
  produces a downloadable artifact.
