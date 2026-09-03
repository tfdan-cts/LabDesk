# Third-party software shipped with LabDesk

LabDesk is a modified RustDesk (AGPL-3.0; see `LICENCE`). The following
software is shipped inside the LabDesk installers beside it, under its own
terms.

## NetBird client (labnet)

The encrypted direct path between LabDesk machines runs on the NetBird
client, shipped as the `netbird` command and daemon under the `netbird`
directory of the installation. NetBird's client is licensed under the
BSD-3-Clause license; only NetBird's server components are AGPL, and LabDesk
ships none of them. The license text is in the NetBird release archive
(`LICENSES/BSD-3-Clause.txt`) and at
https://github.com/netbirdio/netbird/blob/main/LICENSE.

Copyright (c) NetBird GmbH and contributors. Neither the NetBird name nor the
names of its contributors may be used to endorse or promote LabDesk.

Pinned version: 0.78.0. The exact release archives and their SHA-256 sums are
recorded in `third_party/netbird/manifest.txt`; the build refuses an archive
whose sum differs.

## Wintun (Windows only)

On Windows the NetBird client needs the Wintun driver, shipped as
`wintun.dll` beside `netbird.exe`. Wintun's source is GPL-2.0; the signed
prebuilt `wintun.dll` LabDesk ships is distributed under the Wintun Prebuilt
Binaries License, which allows redistribution alongside software that uses
Wintun only through its permitted API. The license text is at
https://www.wintun.net/ and inside the Wintun release archive.

Copyright (c) WireGuard LLC. WireGuard and Wintun are trademarks of Jason A.
Donenfeld.
