---
type: research
created: 2026-09-05
status: draft
related:
  - docs/plans/2026-09-05-001-production-program.md
---

# TeamViewer Remote Control on iOS as the reference for the LabDesk iOS app

Every claim below carries the URL it was read from. All pages were fetched on 2026-09-05. Where a page shows its own date it is recorded next to the URL. Anything that could not be read from a page is marked unverified in the text and collected again in the last section.

The owner's ruling frames the brief: start with core fundamentals, remote access is core, and the user experience from App Store install to daily use is the priority. The TeamViewer app is the reference for how intricate the result should be, not a feature list to copy.

## 1. The two App Store listings side by side

| Item | TeamViewer Remote Control | RustDesk Remote Desktop |
|---|---|---|
| Listing | https://apps.apple.com/us/app/teamviewer-remote-control/id692035811 | https://apps.apple.com/us/app/rustdesk-remote-desktop/id1581225015 |
| Developer | TeamViewer Germany GmbH | Purslane Limited |
| Current version | 15.81.1, released 2026-08-25 (the page shows "Aug 25"; the listing's embedded version data carries the full date "Tue Aug 25 2026"); the most recent reviews of that version are dated 2026-08-28 (reviews feed below) | 1.4.9, released 2026-07-06 (the page shows "Jul 6"; the listing's time element carries 2026-07-06, and the GitHub release 1.4.9 was published 2026-07-06, https://api.github.com/repos/rustdesk/rustdesk/releases/latest) |
| Rating | 4.7, about 44,000 ratings | 4.2, 75 ratings |
| Minimum OS | iOS 15.4 | iOS 13.0, also visionOS 1.0 |
| Size | 126.9 MB | 64.8 MB |
| In-app purchase | Business Yearly Plan, US$619.99 | none |
| Stated scope | "Control your desktop, manage files, and support devices", bidirectional file transfer, real-time chat, multi-monitor support, Wake-on-LAN, camera permission for QR scanning, microphone for audio | "only has the ability to control, and it does not have the functionality of being controlled or screen sharing", plus a scam warning in the description |

TeamViewer's most recent release notes on the listing show what the app still changes at version 15.8x: a fix for saved connection passwords not being kept (15.77.1), a fix for connection issues when a connection was started via Easy Access and a separate fix for Picture-in-Picture stopping after the in-session settings were opened (15.80.1), a fix for remote screen video placement (15.80.2), and a search-view selection bug plus the "latest visual design" adoption (15.81.1). Source: the Version History section of the listing above.

## 2. TeamViewer on iOS, feature by feature

### 2.1 Onboarding and sign-in

TeamViewer's model is account first. A TeamViewer account "keeps all the devices that you connect to organized so that you can connect to them in a click" (https://www.teamviewer.com/en-us/global/support/knowledge-base/teamviewer-classic/licensing/personal-use/for-personal-use/, last modified Aug 18, 2025). Signing in on a new device for the first time triggers the Trusted Devices flow: a pop-up, an authorization email whose link is valid 24 hours, and a trust scope chosen in the Management Console (trust this device, trust the IP address, or trust once). Trust is per client: the page says separate trusts are needed "for the TeamViewer client, the Management Console (per browser), and each TeamViewer (Classic) application", and a browser's trust is lost when cookies are deleted; the page does not name the iOS app separately (https://www.teamviewer.com/en-us/global/support/knowledge-base/teamviewer-classic/security/trusted-devices/trusted-devices/, last modified Feb 5, 2026).

The app can also be used without an account, by ID and password, which is how the personal-use guide introduces the product: the ID is "a phone number for your device. You dial the TeamViewer ID, then use the password" (same personal-use page). No page describing the first-run screens of the iOS app itself was found; the onboarding sequence as experienced in the app is unverified.

### 2.2 Device list and grouping

The device list is account-side. A device enters it as a managed device, a bookmarked device, or through an .msi deployment; the "This device" flow on the remote machine is Sign in, Devices list, +Add device, name it (https://community.teamviewer.com/English/kb/articles/109744-add-a-new-device-to-your-account, last modified May 21, 2026). Groups are shared through the account: "If the device is in a shared group, then all contacts that use the group also have easy access to this device" (https://www.teamviewer.com/en-us/global/support/knowledge-base/teamviewer-classic/remote-control/connection-methods/remote-control-via-easy-access/, last modified Oct 16, 2024). Free accounts may hold up to 3 managed devices in that list (https://community.teamviewer.com/English/discussion/129407/teamviewer-remote-s-free-version-redesign, posted Apr 26, 2023, updated Aug 19, 2025).

### 2.3 Connecting: ID and password, saved devices, one tap

Three paths exist. ID plus password is the base. Easy Access is the one-tap path: "remote control your remote device without entering any ID or password when logged in to your TeamViewer account", set up on the remote device, protected by Trusted Devices, and the first Easy Access setup asks for two-factor validation (Easy Access page above). In the new "TeamViewer Remote" UI the same thing is unattended access through TeamViewer Host, and the free tier must install the Host by hand rather than through a QuickSupport session (https://www.teamviewer.com/en-us/global/support/knowledge-base/teamviewer-remote/remote-control/provide-unattended-remote-support/, last modified Aug 10, 2026). The 15.77.1 release note "Fixed a bug where connection passwords were not saved" confirms that saved per-device passwords exist in the iOS app (listing, Version History).

### 2.4 The remote control session

Interaction has two modes. Touch mode: "use the device as a remote touchscreen; to move the mouse to a specific location, tap the desired location". Mouse mode: "operate the remote device as a touchpad ... drag your finger across the screen". Sessions start in Mouse mode; the switch is under the arrow in the bottom right corner, then the pointing-finger icon, and each mode's gestures are shown in the same sheet (https://community.teamviewer.com/English/kb/articles/109353-interaction-methods-on-ios, last modified Feb 28, 2024).

Keyboard, multi-monitor, quality and clipboard on iOS specifically are thinly documented. The listing claims multi-monitor support and real-time sound and video; the 15.80.1 note mentions "in-session settings" and Picture-in-Picture; the same note says "sending clipboard content to the device" is now supported, but that sentence is about remote support for mobile devices from Linux, not about the iOS client's own session, so it says nothing about clipboard in the iOS app. The detailed session toolbar page (scaling Best fit / Original / Scaled, quality Auto / Optimize Speed / Optimize Quality / Custom, monitor switching, clipboard sync and one-time send, direct keyboard mode, black screen, Ctrl+Alt+Del, remote reboot) describes the desktop client; mobile appears only in its navigation links, not in the toolbar description (https://www.teamviewer.com/en/global/support/knowledge-base/teamviewer-remote/remote-control/remote-session-toolbar/, last modified Jul 7, 2026). Which of those controls the iOS app exposes is unverified.

### 2.5 File transfer

The listing states file transfer "in both directions". The free tier redesign limits free users to "one file at a time" in file transfer sessions (community post above, updated Aug 19, 2025).

### 2.6 Chat

The listing states real-time chat during sessions, and 15.77.1 added a message search field in Chat. The free tier no longer gets VoIP, video, or chat during remote sessions (community post above).

### 2.7 Session security: 2FA, biometric unlock, trusted devices

Three separate mechanisms, all of which the mobile app takes part in:

| Mechanism | What it protects | Where the phone sits | Source and date |
|---|---|---|---|
| Trusted Devices | account sign-in on a new device | the phone is the new device; email link, trust scope | https://www.teamviewer.com/en-us/global/support/knowledge-base/teamviewer-classic/security/trusted-devices/trusted-devices/, Feb 5, 2026 |
| 2FA for connections | inbound connections to a desktop | the phone is the approval device; QR scanned from Settings, "2FA for connections"; each connection must be approved by push; cannot be disabled remotely if the approval device is lost, so a backup device is recommended | https://community.teamviewer.com/English/kb/articles/108791-two-factor-authentication-for-connections, Jun 24, 2024 |
| Biometric Protection | the app itself when backgrounded | Settings, Security, "Unlock with Face/Touch ID"; lock delay "Immediately" or "After 1 minute"; if biometrics fail, a red "Disable Biometric Protection" button on the lock screen turns the feature off, signs the account out and deletes the connection history | https://www.teamviewer.com/en/global/support/knowledge-base/teamviewer-classic/security/security-features/biometric-protection/, Mar 7, 2024 |

### 2.8 Settings

Documented settings reachable in the iOS app: 2FA for connections (QR enrolment), Unlock with Face/Touch ID with a lock delay, and Settings, Get started, Upgrade Plan for the in-app purchase (https://www.teamviewer.com/en-us/global/support/knowledge-base/teamviewer-classic/mobile/ios/in-app-purchase-on-ios, last modified Feb 27, 2024). A full settings inventory of the iOS app was not found on any page and is unverified.

### 2.9 Free versus paid

| Tier | Price | What the pages say |
|---|---|---|
| Free, personal use | US$0 | "The personal use of TeamViewer is free" and the free version is "for people who are using it to help family and friends" (https://www.teamviewer.com/en-us/global/support/knowledge-base/teamviewer-classic/licensing/personal-use/commercial-use-suspected/, May 11, 2026). Free tier: unlimited outgoing devices, 3 managed devices, no VoIP/video/chat in sessions, no VPN, no Wake-on-LAN, one file at a time (community post, updated Aug 19, 2025) |
| Remote Access | US$24.90 per month, billed yearly, excl. tax | 1 licensed user, 1 concurrent connection, up to 3 sessions in tabs, 3 managed devices, file transfer and queuing, remote printing, mobile device support as an add-on (https://www.teamviewer.com/en-us/pricing/overview/, no page date) |
| Business | US$50.90 per month, billed yearly, excl. tax | 200 managed devices, 14-day trial, DEX Essentials, 25 AI credits per month, phone support (same pricing page) |
| Business via iOS in-app purchase | US$619.99 per year | the only plan sold in the app; "Upgrading the license bought by the In-App purchase is not possible" (IAP page above, Feb 27, 2024; price from the listing) |

The commercial-use flag is a policy, not a bug: "This alert also pertains to suspected commercial use", the page says reset requests are reviewed "within 72 hours" in one place and that TeamViewer is "aiming to solve all requests within seven business days" in its FAQ, and the flag is only removed after a reset request gets a positive reply, so uninstalling does not clear it (commercial-use page, May 11, 2026).

### 2.10 What the recent reviews complain about

Source: the App Store most-recent reviews feed for the app, https://itunes.apple.com/us/rss/customerreviews/id=692035811/sortBy=mostRecent/json, 50 entries dated 2026-02-06 to 2026-08-28, fetched 2026-09-05. Counted by theme; one review can hit more than one theme.

| Theme | Count in the 50 | Representative lines (dates) |
|---|---|---|
| Commercial-use flag, session caps, "geared toward businesses", price | 9 | "You reached the maximum session duration" after one minute (2026-06-26); flagged as commercial helping elderly parents, "wants 600 a year" (2026-06-23); "Connection constantly gets blocked" (2026-07-17); 28-day cancellation notice called shady (2026-05-29) |
| Missed clicks, pointer precision, external mouse and scroll on iPad | 6 | "Unusable with an external mouse ... several missed clicks, and scrolling does not function" (2026-07-31); "inability to consistently click the correct pixel" (2026-05-10); Bluetooth mouse not moving in mouse mode (2026-04-28); "regularly takes away your ability to click" (2026-08-18) |
| Connection drops, lag, cannot connect | 6 | "runs like a slide show" on fiber (2026-02-06); "connection drops constantly", no support reply (2026-02-06); paying US$200 and cannot connect (2026-08-12); device shows online on desktop but not mobile (2026-08-05) |
| Sign-in and session persistence | 3 | logged out within 3 minutes of closing a connection, SSO credentials not remembered (2026-05-20); "requires me to sign in but when I do it doesn't sign in" (2026-04-30); migration failure after upgrade (2026-08-01) |
| Battery and background behaviour | 1 | closing the app keeps the session open, 100% to 9% in a couple of hours (2026-07-09) |
| Setup and documentation | 3 | "Documentation and instructions are totally inadequate" (2026-03-20); "Didn't work after 15 minute set up" (2026-06-28); two dialog boxes that cannot be removed (2026-03-14) |
| Visual | 2 | "No dark mode" (2026-03-22); on-screen controls "almost impossible to see" (2026-02-23) |

The five-star reviews are about the same things working: access from anywhere, using the phone as a touch screen or drawing tablet, and reliability over years. The pattern for LabDesk is plain: the reference app loses users at the licence gate and at pointer precision, not for lack of features.

## 3. What RustDesk's iOS client provides today

### 3.1 From RustDesk's own pages

RustDesk describes the iOS app as "a full controller for any RustDesk host" with "an on-screen touchpad, a mouse mode, a software keyboard, and file transfer", and states that the phone "behaves the same as the desktop client". Being controlled is out: "no remote-desktop app can remotely control an iPhone or iPad, RustDesk included", because "iOS heavily restricts background execution, screen recording, and any form of synthetic input injection" (https://rustdesk.com/blog/rustdesk-remote-control-android-ios/, dated Jul 7, 2026 on the page). The FAQ points custom iOS clients at a discussion thread and gives iOS Simulator build notes (https://github.com/rustdesk/rustdesk/wiki/FAQ). The Android app was voluntarily pulled from Google Play over scam abuse while the iOS app stays on the App Store (blog post above).

### 3.2 Open iOS issues on the upstream tracker

From `gh search issues --repo rustdesk/rustdesk "iOS" --state open --sort updated`, run 2026-09-05 (repository last pushed 2026-09-05T03:44:51Z):

| Issue | Updated | Title |
|---|---|---|
| 16027 | 2026-09-02 | [iOS][VMware] Software keyboard input is misread as scan codes in a Windows guest |
| 16025 | 2026-09-02 | [iOS] A tap clicks the previous cursor position before clicking the new position |
| 15209 | 2026-08-06 | Scrolling problem iPad + Magic Keyboard |
| 13011 | 2026-06-15 | mouse mode = touch mode (and broken) when iPad external keyboard is attached |
| 12977 | 2025-12-27 | iOS clicks not registering |
| 8789 | 2025-11-22 | Mouse hover issue on menu bar when remotely controlling Mac (iPad to Mac) |
| 5871 | 2025-05-02 | Keyboard can't type uppercase on latest iOS update |

### 3.3 RustDesk App Store reviews

Source: https://itunes.apple.com/us/rss/customerreviews/id=1581225015/sortBy=mostRecent/json, 50 entries dated 2023-10-03 to 2026-08-20. Recurring praise: works with self-hosted servers, unattended access, "sick of TeamViewer constantly timing me out because it thought me accessing my laptop from my phone was commercial use" (2026-08-05). Recurring complaints: keyboard strokes stopped working from iPhone (2026-06-25), phone heats up (2026-06-20, 2026-04-14), pointer misaligned after an update on iPad (2026-03-15), letterboxing with no full screen (2026-05-23), "Remember password" not remembered (2025-11-27, 2024-10-13), key mismatch on iPad only (2025-04-14), Apple Pencil unsupported (2025-05-17), mouse actions not configurable and three-finger scroll unreliable (2025-05-01), double-click registered on single tap (2024-04-22).

### 3.4 What the inherited iOS target in this repository carries

Read from the working tree at commit 3754536e (2026-09-04). The mobile entry point is `runMobileApp()` in `flutter/lib/main.dart` line 48, which renders the inherited `HomePage`; the LabDesk console shell (`flutter/lib/labdesk/`) is desktop only and none of its screens are referenced from `flutter/lib/mobile/`.

| Area | What is there | Where |
|---|---|---|
| Home and peer list | tabs Recent, Favorites, LAN, Address book, Group (`enum PeerTabIndex`), plus LabDesk's local machine groups and per-peer icons stored in local options | `flutter/lib/models/peer_tab_model.dart`, `flutter/lib/common/widgets/peer_tab_page.dart`, `flutter/lib/common/widgets/labdesk_groups.dart` |
| Connect | ID entry page, QR scan page (camera permission string present) | `flutter/lib/mobile/pages/connection_page.dart`, `scan_page.dart`, `flutter/ios/Runner/Info.plist` |
| Session | Touch mode and Mouse mode with a gesture help sheet (One-Finger Tap, One-Long Tap, One-Finger Move, Two-Finger Move, Double Tap & Move, Pinch to Zoom, Canvas Move, Canvas Zoom, Three-Finger vertically, virtual mouse with size and relative mode, virtual joystick), soft keyboard with an iOS-specific input path and CapsLock inference, physical keyboard workaround after the virtual keyboard hides, monitor switching in the same tab, image quality and codec radios, privacy mode toggle, clipboard sync on foreground, text chat and voice call menu | `flutter/lib/mobile/pages/remote_page.dart`, `flutter/lib/mobile/widgets/gesture_help.dart`, `flutter/lib/models/input_model.dart` |
| File transfer | two-pane file manager; `UIFileSharingEnabled` is true in Info.plist | `flutter/lib/mobile/pages/file_manager_page.dart`, `flutter/ios/Runner/Info.plist` |
| Terminal | mobile terminal page with iOS-specific delete detection and close button | `flutter/lib/mobile/pages/terminal_page.dart` |
| Settings | account login and logout, ID/relay server, proxy, WebSocket, TLS fallback, theme, language, adaptive bitrate, hardware codec, session recording, 2FA and trusted devices for the controlled side, whitelists; the Android-only rows are guarded by `isAndroid` | `flutter/lib/mobile/pages/settings_page.dart` |
| Being controlled | `server_page.dart` exists but is Android's; the iOS app is outgoing only, matching the RustDesk listing | `flutter/lib/mobile/pages/server_page.dart` |
| Project identity | bundle id `com.carriez.flutterHbb`, display name RustDesk, `DEVELOPMENT_TEAM = HZF9JMC8YN` (upstream's team), deployment target 13.0, `ITSAppUsesNonExemptEncryption` false, entitlements `aps-environment` development and `wifi-info` | `flutter/ios/Runner.xcodeproj/project.pbxproj`, `Info.plist`, `Runner.entitlements` |
| Version | `flutter/pubspec.yaml` is 1.2.4+72 and `Cargo.toml` is 1.2.4, against upstream 1.4.9 on the App Store | those files |

Two things in that table need a decision rather than code: the 2FA and trusted-device settings rows are for a controlled endpoint and the iOS app has none, so whether they render on iOS at all is unverified from code alone; and the bundle identifier, team, display name and push entitlement are still upstream's and must change before any signed build.

## 4. Comparison

| Capability | TeamViewer iOS | RustDesk iOS (upstream 1.4.9) | LabDesk inherited target |
|---|---|---|---|
| Account sign-in with new-device trust | yes, email link and trust scope | account login exists in settings; trusted devices exist for the controlled side | same as RustDesk |
| Device list from the account | managed and bookmarked devices, shared groups | address book and group tabs when a server account exists | same, plus local LabDesk groups |
| ID and password | yes | yes | yes |
| Saved password, one tap | Easy Access / unattended Host | saved password per peer (reviews report it failing) | same code |
| Touch and mouse modes | yes | yes, plus virtual mouse and joystick | yes |
| Multi-monitor | claimed on listing | monitor switch in session | yes |
| Quality controls | unverified on iOS | quality and codec radios | yes |
| Clipboard | unverified on iOS; desktop toolbar sync documented; the 15.80.1 clipboard note is about Linux supporting mobile devices | sync on app foreground | yes |
| File transfer | yes, one file at a time on free | yes | yes |
| Chat | yes, paid only in sessions | text chat and voice call | yes |
| App lock by Face ID | yes, with lock delay | not found in the settings page strings | to build |
| Push approval of inbound connections | yes, 2FA for connections | no | owner decision |
| Being controlled | only through the separate QuickSupport app, where the user must "Accept the connection request every time" (https://apps.apple.com/us/app/teamviewer-quicksupport/id661649585); that listing lists "Remote control" among its key features without separating iOS from Android, so "screen share only" is not stated there; the pricing page's mobile device support add-on says it "Covers all Android devices and supports iOS screen sharing" (https://www.teamviewer.com/en-us/pricing/overview/) | no | no |
| Price gate | free for personal use, US$619.99 IAP | free | free |

## 5. Proposed LabDesk iOS scope in three tiers

Labels: inherited (already in the tree and expected to work after rebrand), to build, owner decision.

### Tier 1, fundamentals: install, sign in, connect, control

| Item | Status | Why it is in tier 1 |
|---|---|---|
| Rebrand the target: bundle id, display name, icons, team, entitlements without upstream's push environment | to build | nothing can be signed or submitted as is (section 3.4) |
| First run that asks for nothing but a server profile or the lab-desk.net sign-in, no camera or notification prompts until a feature needs them | to build | Apple 5.1.1(iii) data minimisation and the reviews about setup friction (https://developer.apple.com/app-store/review/guidelines/, last updated June 8, 2026) |
| Sign-in that stays signed in; a session that survives backgrounding and does not re-prompt within minutes | to build, verify | the SSO logout review of 2026-05-20 is the kind of complaint that costs a star |
| Machine list with Recent, Favorites, Address book, Group and LabDesk local groups, with the same three-state reachability the desktop console shows | inherited list, to build reachability | the production program already scopes the fleet list for the phone (docs/plans/2026-09-05-001-production-program.md) |
| ID plus password connect, saved password per machine, one tap from the list | inherited, verify | RustDesk reviews report the saved password being lost; that must be tested on a real device before it is called done |
| Session: touch and mouse modes, gesture sheet, virtual mouse, soft and hardware keyboard, monitor switch, quality and codec, clipboard on foreground | inherited, verify on iPad with a Magic Keyboard and a Bluetooth mouse | the top complaint about both reference apps is pointer precision and external input, and upstream issues 16025, 15209, 13011 are open |
| Explicit disconnect on background after a short grace, so the phone does not hold a session open | to build | the 2026-07-09 battery review; also Apple 2.5.4 background services must match a declared purpose |
| Dark mode following the system | inherited theme setting, verify | the 2026-03-22 "no dark mode" review |
| Privacy manifest, purpose strings, `ITSAppUsesNonExemptEncryption` answered truthfully for the crypto in the Rust core | to build | required for submission (https://developer.apple.com/documentation/bundleresources/privacy-manifest-files; https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption) |

### Tier 2, daily use

| Item | Status |
|---|---|
| Face ID / Touch ID app lock with a lock delay, modelled on TeamViewer's Biometric Protection | to build |
| File transfer with the Files app integration that `UIFileSharingEnabled` already declares | inherited, verify |
| Text chat during a session | inherited, verify |
| Terminal page | inherited, verify |
| Health board read from lab-desk.net | to build, already in the production program's scope |
| Hide the controlled-side settings (2FA, trusted devices, whitelists, recording of incoming sessions) on iOS where there is no controlled side | to build |
| Pointer and scroll tuning for iPad with external input, Apple Pencil as pointer | to build, driven by upstream issues and reviews |

### Tier 3, owner decisions

| Item | Status | Question for the owner |
|---|---|---|
| Push approval of inbound connections to fleet machines from the phone (TeamViewer's 2FA for connections) | owner decision | needs APNs and a server-side hook; strong security story, real cost |
| Voice call in session | inherited code, owner decision | microphone permission and a purpose string the reviewer will read |
| Being controlled or screen sharing from the phone | owner decision, likely no | RustDesk's blog states that Apple does not let any third-party app act as a remotely controlled host on iOS (section 3.1); TeamViewer's pricing page says its mobile support add-on "supports iOS screen sharing", through the separate QuickSupport app with per-connection consent (section 4) |
| Console sections beyond Connect, Fleet and Health on the phone (Tools, Automation, Actions, Network) | owner decision | the desktop console is not on mobile today (section 3.4) |
| Any paid tier or in-app purchase | owner decision | Apple 3.1.1 requires in-app purchase for unlocking features; the RustDesk listing has none |

## 6. App Store distribution prerequisites

| Prerequisite | What the page says | Source |
|---|---|---|
| Apple Developer Program | US$99 per membership year; individual enrolment needs a legal name, an Apple Account with two-factor authentication and a physical address; organisation enrolment needs a D-U-N-S number, a legal entity name, a work email on the organisation's domain and a functional public website | https://developer.apple.com/programs/enroll/ (no page date) |
| Guideline 4.2.7 remote desktop clients | applies only "if your remote desktop app acts as a mirror of specific software or services rather than a generic mirror of the host device"; then LAN-only, host-side account creation, no store-like UI, and "thin clients for cloud-based apps are not appropriate". A generic remote desktop client like LabDesk sits outside that clause, which is how TeamViewer and RustDesk are listed | https://developer.apple.com/app-store/review/guidelines/, last updated June 8, 2026 |
| 2.5.1 public APIs and 2.5.4 background services | only public APIs; background only for declared purposes such as VoIP, audio, location, task completion | same page |
| 3.1.1 in-app purchase | any feature unlock must use in-app purchase, no licence keys | same page |
| 4.8 login services | an alternative privacy-preserving login is required only when a third-party or social login is offered; "your app exclusively uses your company's own account setup and sign-in systems" is an explicit exemption | same page |
| 5.1.1 permission and data minimisation | consent for any collected data, purpose strings that "clearly and completely describe" the use, request only what the core function needs | same page |
| Privacy manifest `PrivacyInfo.xcprivacy` | declares collected data types and required-reasons APIs for the app and every third-party SDK, including the Flutter plugins in the target | https://developer.apple.com/documentation/bundleresources/privacy-manifest-files |
| Export compliance | `ITSAppUsesNonExemptEncryption` NO only if the app and all linked libraries use no encryption or only exempt encryption; otherwise YES plus an `ITSEncryptionExportComplianceCode`; without the key App Store Connect asks the questionnaire on every upload | https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption |
| TestFlight and the key ceremony | owner-only per the production program; the phase 2 verifier is an ipa built by CI plus a simulator test log | docs/plans/2026-09-05-001-production-program.md |

The inherited Info.plist already sets `ITSAppUsesNonExemptEncryption` to false. Whether that is true for LabDesk's Rust core, which carries its own transport encryption, is a legal question the owner answers before the first upload; the brief does not decide it.

## 7. Unverified

- Whether the TeamViewer iOS session exposes clipboard sync at all: the only clipboard mention in the iOS release notes concerns Linux supporting mobile devices (section 2.4).
- The first-run and sign-in screens of the TeamViewer iOS app: no documentation page describes them; section 2.1 is assembled from the account and Trusted Devices pages.
- Multi-monitor switching, quality controls and clipboard as exposed in the TeamViewer iOS session UI: the listing claims multi-monitor support and the release notes mention in-session settings, but the only detailed toolbar page is the desktop one.
- A full inventory of the TeamViewer iOS settings page.
- The privacy manifest enforcement date of February 12, 2025 appeared in a search snippet for https://docs.developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk; the sentence was not read on the page itself.
- Whether the inherited 2FA and trusted-device rows render on iOS; the code has no platform guard around them, but the app was not run.
- TeamViewer's pricing page shows no date; it was read on 2026-09-05. The RustDesk blog post is dated Jul 7, 2026 on the page.
- Whether iOS QuickSupport is screen sharing only: the QuickSupport listing lists "Remote control" as a key feature without an iOS qualifier; the only TeamViewer page read that limits iOS to screen sharing is the pricing page's add-on tooltip.
- Nothing in this brief was run on an iPhone or in the simulator. Every "inherited, verify" row stays unverified until the phase 2 simulator log exists.
