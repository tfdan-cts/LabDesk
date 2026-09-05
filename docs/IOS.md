# The LabDesk iOS application

LabDesk on iPhone and iPad is not a separate product. It is the same Flutter
application and the same Rust core that the desktop client is built from, with a
different entry point: `flutter/lib/main.dart` sends every non-desktop platform
to `runMobileApp`, which renders the mobile widget tree under
`flutter/lib/mobile/`. The Xcode project that wraps it lives at `flutter/ios`.

The desktop LabDesk console does not exist on the phone. Every console screen
sits under `flutter/lib/desktop/`, and the mobile tree renders upstream
RustDesk's `HomePage`: a connection page and a settings page, with the chat and
incoming-service tabs gated to Android. What the phone gets instead is described
under Tier 1 below.

## Ground truth as of 2026-09-05

Everything in this section was read from a tool result, not remembered.

- The iOS job in `.github/workflows/flutter-build.yml` is called
  `build rustdesk ios ipa`. It reports skipped on Full Flutter CI runs because
  of its own job-level `if: ${{ inputs.upload-artifact }}`, and `flutter-ci.yml`
  calls the reusable workflow with `upload-artifact: false`. It runs only from
  `labdesk-dispatch.yml`, `flutter-nightly.yml` and `flutter-tag.yml`.
- That job has never produced a downloadable build. Its artifact upload and
  release steps are commented out, so no ipa has ever left this repository.
- The job last succeeded in run 33931151246 on 2026-09-05 at 00:01Z. It then
  failed in runs 33944666923 and 33948273476 with four `E0433` errors at
  `src/client.rs` lines 401, 402, 479 and 480: the labnet overlay-hint code
  called `crate::ipc::set_option_async`, and `src/lib.rs` declares `pub mod ipc`
  under `#[cfg(not(any(target_os = "ios")))]`, so iOS names a module it does not
  compile. Desktop and Android were unaffected.
- The inherited iOS target still carries upstream RustDesk's identity:
  `PRODUCT_BUNDLE_IDENTIFIER` is `com.carriez.flutterHbb`, `DEVELOPMENT_TEAM` is
  `HZF9JMC8YN`, `CFBundleDisplayName` and `CFBundleName` are both `RustDesk`,
  the app icon is RustDesk's blue ring, and `Runner.entitlements` asks for an
  `aps-environment` push entitlement that no account here can issue.

## How it is verified, since there is no Mac

There is no Mac anywhere in this fleet, and Claude Code's iOS Simulator pane
needs a local Mac with Xcode, so it is not available for this work. The
verification path is a GitHub Actions macOS runner, which carries Xcode,
`xcodebuild` and `xcrun simctl`. The CI job is the device.

`.github/workflows/ios-verify.yml` is that job. On every push to `feat/ios` that
touches something other than documentation, and on manual dispatch, it:

1. generates the flutter_rust_bridge output with the same `bridge.yml` the
   release build uses, so the two cannot drift;
2. installs the vcpkg dependencies for the `arm64-ios-simulator` triplet;
3. builds the Rust core for `aarch64-apple-ios-sim`, without `hwcodec`, matching
   the inherited `flutter/ios_x64.sh` simulator build;
4. builds the app with `flutter build ios --simulator --debug`;
5. creates and boots an iPhone 17 simulator, installs the app and launches it;
6. takes screenshots at three, seven and ten seconds, collects the app's log,
   and uploads both as artifacts;
7. fails unless `launchctl` inside the simulator still shows the app running
   twenty seconds after launch, because a launch that returns a process id and
   then dies is not a running app.

The runner facts behind those choices were measured, not assumed, by a throwaway
probe (run 33982479503) on 2026-09-05: `macos-latest` is arm64, Xcode 26.6, with
iOS 26.2, 26.4 and 26.5 simulator runtimes and iPhone 11 through iPhone 17
device types, and vcpkg carries `arm64-ios-simulator` as a community triplet.
The probe workflow was deleted once it had answered.

The honest ladder, strongest first, is: the simulator job above; Flutter widget
and unit tests, which run on any runner; and a build that merely compiles for
the iOS target. Reading code is not verification, and a green build is not a
working screen.

### What this cannot prove

A simulator is not a phone. These are named here rather than implied, and none
of them is verified today:

- Anything that needs a signing certificate or a provisioning profile. See the
  Apple Developer account section below.
- Hardware video decode through VideoToolbox, and the `hwcodec` feature
  generally, which the simulator build leaves out.
- Real camera input, so the QR scanner cannot be exercised end to end.
- Push notifications, background execution behaviour under real memory
  pressure, and cellular network transitions.
- Touch latency and gesture feel, which are the whole point of the session
  screens and can only be judged on a device in a hand.

## Tier 1, the current scope

Tier 1 comes from `docs/research/2026-09-05-ios-reference-teamviewer.md`, which
maps TeamViewer's iOS app against the inherited RustDesk client. In order:

1. Rebrand the target: bundle identifier, display name, icons, development team,
   and entitlements without upstream's push environment.
2. A first run that asks for nothing but a server profile or the lab-desk.net
   sign in, with no camera or notification prompt until a feature needs one.
3. A sign in that stays signed in, and a session that survives backgrounding.
4. A machine list carrying the same three state reachability the desktop console
   shows, including a real unknown state that is rendered as absence and never
   as offline.
5. Identifier and password connect, with a saved password per machine and one
   tap from the list.
6. The session itself: touch and mouse modes, the gesture sheet, the virtual
   mouse, soft and hardware keyboards, monitor switching, quality and codec, and
   the clipboard.
7. An explicit disconnect after a short grace on background, so the phone does
   not hold a session open.
8. Dark mode following the system.
9. The privacy manifest, the purpose strings, and an encryption declaration
   answered truthfully for the cryptography in the Rust core.

Tier 2 and Tier 3 are out of scope. Tier 3 items are owner decisions.

### Identity

What the target carries now, and what each value replaced:

| Setting | Was | Is |
|---|---|---|
| `PRODUCT_BUNDLE_IDENTIFIER` | `com.carriez.flutterHbb` | `net.lab-desk.LabDesk` |
| `DEVELOPMENT_TEAM` | `HZF9JMC8YN` | removed, not replaced |
| `CFBundleDisplayName`, `CFBundleName` | `RustDesk` | `LabDesk` |
| `CFBundleURLName` | `com.carriez.rustdesk` | `net.lab-desk.LabDesk` |
| App icon | RustDesk's blue ring | the LabDesk mark from `res/icon.png` |
| `Runner.entitlements` | `aps-environment`, `wifi-info` | empty, with the reason in the file |

`DEVELOPMENT_TEAM` is removed rather than set to something else because there is
no LabDesk team identifier to set until the owner holds an Apple Developer
membership. An empty team is the truthful state.

The entitlements file is deliberately an empty dictionary. Upstream asked for
`aps-environment`, a push notification environment, which this application does
not use and which cannot be issued without a membership; and
`com.apple.developer.networking.wifi-info`, which reads the current network
name and which nothing in this application asks for.

The icons are generated by `flutter/tool/make_ios_app_icons.py` from
`res/icon.png`, so they can be regenerated when the mark changes. That script
exists because `res/icon.png` is a rounded tile with transparent corners, which
is wrong twice for iOS: the App Store rejects a marketing icon carrying an alpha
channel, and iOS applies its own corner mask, so a pre-rounded icon shows a
second rounding inside the first. Every file it writes is square, opaque, and
unrounded.

The camera and photo library purpose strings now say what LabDesk actually does
with each: the camera is used only to scan a connection QR code and never during
a session, and a photo is read only when the operator picks one holding a QR
code. The encryption declaration, `ITSAppUsesNonExemptEncryption`, still carries
upstream's answer and has not been checked against what the Rust core actually
does. It is unverified and is its own piece of work.

The bundle identifier prefix is not new: the
Linux packaging already ships a polkit action named
`net.lab-desk.LabDesk.install-update` (`src/platform/linux.rs`,
`docs/CONSOLE.md`), so the iOS target joins a naming scheme the project already
uses rather than inventing one.

The `rustdesk://` URL scheme is deliberately left alone. It is parsed by shared
Dart in `flutter/lib/common.dart` and declared in the Android manifest as well,
so renaming it is a coordinated change across all three clients and not an iOS
decision. It is recorded here as an open branding item.

## What waits on an Apple Developer account

The owner holds no Apple Developer Program membership (99 USD per year). Until
there is one, the following cannot be done at all, by anyone, and nothing in
this repository pretends otherwise:

- A signing certificate and a provisioning profile, so no build can be installed
  on a real device.
- `DEVELOPMENT_TEAM`, which is why the value inherited from upstream is removed
  rather than replaced.
- TestFlight, and therefore any external tester.
- An App Store Connect record, the bundle identifier registration, and the App
  Store listing itself.
- The `aps-environment` entitlement, which is why it is removed from
  `Runner.entitlements` rather than left as upstream's `development`.

Section 6 of `docs/research/2026-09-05-ios-reference-teamviewer.md` lists the
App Store prerequisites in full.

Every build produced today is unsigned and runs only on a simulator.
