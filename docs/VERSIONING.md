# Versioning

LabDesk has a version of its own. It is not the version of the RustDesk core it is built on.

## The rule

- **Semantic versioning**, `MAJOR.MINOR.PATCH`, and a build number after `+`.
  - `MAJOR` when an existing installation cannot be upgraded in place, or a server profile,
    peer store or option written by the previous version can no longer be read.
  - `MINOR` for a new capability an operator can see: a section, a tool, a trigger, a probe.
  - `PATCH` for a fix that changes no interface and no stored data.
  - The build number (`+N`) increases by one on every version change and is never reused. It is
    what Windows installer upgrade detection compares.
- **One number, everywhere it is read.** The version is written in several places and they must
  agree. `scripts/set-version.ps1 <version>` rewrites all of them; nothing edits them by hand.

  | File | Read by |
  |---|---|
  | `Cargo.toml` `version` | `labdesk --version`, the About page, the connection manager's title |
  | `libs/portable/Cargo.toml` `version` | the portable wrapper exe |
  | `flutter/pubspec.yaml` `version` | the Flutter bundle; the `+N` is the build number |
  | `.github/workflows/flutter-build.yml` `VERSION` | asset names, `LabDesk-<version>-<arch>-install.exe` |
  | `appimage/AppImageBuilder-*.yml` `version` | the AppImage metadata |
  | `res/rpm*.spec` `Version:` | the `.rpm` package names and metadata |
  | `Cargo.lock`, `libs/portable/Cargo.lock` | our own crates' entries, so a `--locked` build agrees |

- **A tag is a release.** `v<version>` on the commit that is released, created by the owner when
  the release pull request lands on `master`. A tag is never moved.
- **Pre-releases** carry a suffix: `1.2.0-rc.1`. The build number still increases.
- **The core version is stated, not versioned.** The RustDesk commit this is built on is in the
  README's *Modifications* section (`1d09760ef`, release line 1.4.9). When the base moves, that
  line moves and LabDesk takes at least a `MINOR` bump.

## History, and why 1.2.0

Until 2026-09-02 the binaries reported `1.4.9`, the upstream core's number, while the
repository's tags said `v1.0.0` to `v1.1.0`. Two numbers for one artifact meant neither could be
trusted: an installed copy could not tell you which LabDesk it was. `v1.1.0` had already been spent
on the 2026-08-29 console preview, so the first version the binaries themselves carry is
**1.2.0**, and from here the tag and the binary agree.

## Bumping

```
pwsh scripts/set-version.ps1 1.2.1
```

The script refuses a version that is not `MAJOR.MINOR.PATCH[-suffix]`, computes the next build
number from `pubspec.yaml`, rewrites every file in the table, and prints them for the commit. Add the
`CHANGELOG.md` entry in the same commit; the commit subject is `chore(version): 1.2.1`.
