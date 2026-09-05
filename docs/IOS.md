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

### First run

Item 2 is built. A fresh install shows one screen before the tabs: choose a
server, by signing in to lab-desk.net or by adding a server profile, with a
"Not now" that is remembered so nobody is asked twice.

It asks for nothing else. There is no camera prompt and no notification prompt
on that screen, and a test asserts the words do not appear on it, because a
permission asked for before the feature that needs it is a permission asked for
without a reason. Nothing in the application requests a permission at launch
either: no permission plugin is invoked on startup, and `AppDelegate.swift`
registers no push.

The screen exists because of a fact rather than a preference. A phone has no
installer to carry a server in, so a fresh install has none until it is signed
in or given a profile, and until then the core falls back to a default the
operator never chose. That is traced in full in
`docs/plans/2026-09-05-004-ios-session-notes.md`.

The line about the current server is read, not written. When a server is
configured the screen names it; when none is, it says the built in default is in
use and does not invent a name, because this client cannot currently read the
effective server back out of the core. `bind.mainIsUsingPublicServer` reports
the same condition, and `using_public_server` in `src/common.rs` is exactly
"no custom rendezvous server is set".

Split as usual. `needsServerSetup` and `FirstRunView` in
`flutter/lib/mobile/widgets/first_run.dart` take everything through arguments
and import no model, so both the rule and the screen are tested without the
generated bridge. Nine tests cover them. The wiring is in the phone's home page
and is gated to iOS.

**Unverified.** Not seen running. In particular, whether it appears at the right
moment on a genuinely fresh install is a thing only a fresh install can show.

### The machine list

Item 4 is built. The phone gains a Machines tab beside Connection and Settings,
and it reads through exactly the code the desktop console reads through:
`buildMachineRows` in `flutter/lib/labdesk/console_data.dart`, over the same
`LabDeskPeerStatusStore`. Nothing about reachability is re-decided for the
phone, which is the point: two implementations of three states would drift.

The states are not decided here either. `labdeskDotFor` in
`flutter/lib/common/labdesk_peer_status.dart` is the shared decision, and the
phone calls it, so the phone's dot and the console's cannot drift apart. Online
is a filled green dot, offline a filled error-coloured dot, unknown a hollow
ring, and a machine whose query is still out is hollow and amber and says
Checking. Hollow covers both cases where nothing is known, because neither an
unasked question nor an open one may be drawn as an answer.

A machine no response has named carries no times at all: no last seen, no last
checked, and never the word Offline. Absence of an answer is not an answer, and
a phone screen that shades it into "down" would have the operator chasing a
machine that is fine.

The list repaints when an answer arrives because it watches the binding's
`revision`. The store keeps its states in a plain map, so folding a response
into it changes nothing a widget would otherwise notice.

The list is split the same way the console screens are. `MachineListView` in
`flutter/lib/mobile/widgets/machine_list.dart` takes everything through its
constructor and imports neither the FFI nor a model, so it is tested without the
generated bridge; `MachinesPage` in `flutter/lib/mobile/pages/machines_page.dart`
is the wiring. Seven widget tests cover it in
`flutter/test/labdesk_ios_machine_list_test.dart`, including the one that
matters: a machine nobody has asked about must not read as down.

A key icon marks the machines this client already holds a password for, so the
operator can see which taps will ask for one. One tap connects. Pull down to
refresh; the list also refreshes every thirty seconds while it is on screen, and
stops when it is not.

The tab is gated to iOS. Android would benefit from it too, but that client
belongs to another lane and this change does not reach into it.

### Leaving a session in a pocket

Item 7 is built. A phone must not hold a remote session open while it is in a
pocket: the far end cannot tell a backgrounded phone from an attentive one, so
the machine keeps showing somebody connected to it.

Backgrounding the session screen starts a twenty second grace. Coming back
inside it cancels the grace, because switching apps for a moment is not leaving.
When it runs out the session is closed through the same path the close button
uses, so teardown is the one that already works.

The grace is checked in two places on purpose, and the reason is iOS rather than
taste. While iOS still gives the process runtime after backgrounding, a timer
fires and the session closes properly, with a disconnect the far end sees. If
iOS suspends the process first no timer fires at all, so the elapsed time is
checked again against the wall clock on the way back to the foreground, and a
session that outlived its grace while suspended is closed then instead of handed
back.

The policy is a clock-free value type, `BackgroundGrace` in
`flutter/lib/mobile/background_grace.dart`, so both callers ask the same
question and it can be tested without waiting twenty seconds. Six tests cover it
in `flutter/test/labdesk_ios_background_grace_test.dart`, including a clock that
jumps backwards, which must not close a live session.

Gated to iOS. Android keeps a session alive deliberately: it runs a foreground
service and can be the controlled side.

**Unverified.** The grace has not been watched happening on a simulator. The
policy is proved by tests; the wiring into the session screen is not, and
backgrounding under real memory pressure is one of the things a simulator cannot
tell us anyway.

**Unverified.** The list has not been seen running. Widget tests prove the
rendering rules; they do not prove it looks right on a phone, and they cannot.
That waits on the first green simulator run.

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

The icons are regenerated with the tool this project already carries:

    cd flutter && dart run flutter_launcher_icons

`flutter_launcher_icons` is a direct dependency and its configuration is already
in `flutter/pubspec.yaml` under `flutter_icons`, pointed at `res/icon.png` with
`remove_alpha_ios: true`. The App Store rejects a marketing icon carrying an
alpha channel, which is what that flag is for: the generated iOS icons are
opaque RGB. It regenerates every platform, so run it deliberately and commit
only the platform you meant to change.

One detail, checked rather than assumed, because it looks alarming in a file
browser. `remove_alpha_ios` flattens the transparent corners of the rounded tile
onto black, so the raw 1024 asset has black corners. `res/icon.png` rounds at a
radius of 390 in a 2048 tile, which is 19 percent of the width, and the mask iOS
applies to an app icon is wider than that, so every black pixel sits in the
region iOS removes. The home screen screenshot the verification job takes is
what settles it rather than this paragraph.

The camera and photo library purpose strings now say what LabDesk actually does
with each: the camera is used only to scan a connection QR code and never during
a session, and a photo is read only when the operator picks one holding a QR
code.

### The encryption declaration

`ITSAppUsesNonExemptEncryption` is `true`. Upstream shipped `false`, which is
not true of this application.

What the Rust core actually does, read from the manifests and the code rather
than assumed. `libs/hbb_common/Cargo.toml` depends on `sodiumoxide 0.2`, which
is libsodium, and the client uses `crypto::box_` (X25519 key agreement with
XSalsa20 and Poly1305), `crypto::secretbox`, `crypto::sign` (Ed25519) and
`crypto::hash::sha256` in `src/common.rs`, `src/client.rs`, `src/server.rs` and
`src/custom_server.rs`. Transport security is `tokio-rustls` with the `ring`
backend plus `rustls-platform-verifier`, so even the TLS is the application's
own, not the system's. The one dependency that is not compiled on iOS is
`openssl`, which `Cargo.toml` scopes to Linux and Android.

Apple's exemption is narrow. Its export compliance reference says an app needs
no encryption documentation when "your app uses encryption limited to that
within the Apple operating system". LabDesk bundles its own libsodium and its
own TLS stack, so it does not qualify, and answering `false` would be claiming
an exemption that does not apply. Apple states plainly that the developer is
"responsible for all liabilities associated with misinterpretation of export
regulations or claiming exemption inaccurately", so the declaration is answered
against what the code does.

Sources, read on 2026-09-05:
<https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption>
and
<https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance>.

What this does not decide, and what waits on the owner. Apple distinguishes
standard algorithms from proprietary ones: an app using industry standard
algorithms that are not the operating system's needs the French encryption
declaration, and only then if it is distributed on the App Store in France; an
app using proprietary algorithms not accepted by a standards body such as IEEE,
IETF or ITU must upload a CCATS classification from the US Bureau of Industry
and Security. Everything LabDesk uses is standard and published, so the CCATS
path should not apply, but that determination is the owner's to make and Apple
points at the Export Administration Regulations for it. It is marked unverified
here because nobody has filed anything and there is no account to file it
against.

`ITSEncryptionExportComplianceCode` is deliberately absent. That key carries a
code Apple issues after approving uploaded documentation, and no documentation
has been uploaded, so writing a code there would be inventing one.

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
