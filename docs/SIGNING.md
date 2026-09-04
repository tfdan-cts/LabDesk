# Signing LabDesk releases

A release carries two different signatures, because there are two different
questions to answer.

- **Authenticode over the installer** answers "does this machine's Windows
  trust whoever published this file". It is what decides whether SmartScreen
  warns the person who double-clicks it. That is the subject of the rest of
  this page, up to the update-manifest section.
- **Ed25519 over the update manifest** answers "did the LabDesk release
  pipeline really publish this update". It is what stops a compromised website
  from pushing a different binary to a fleet that has already decided to trust
  us and installs updates without a human present. It does not stop someone who
  can make the pipeline itself sign for them, and that limit is set out in
  [What this does not close](#what-this-does-not-close). See
  [Signing the update manifest](#signing-the-update-manifest).

Neither one substitutes for the other, and they are held in different places
for a reason given in each section.

LabDesk's build runs on GitHub's machines, and a signing key does not belong
there, so continuous integration publishes unsigned binaries. Signing happens
afterwards, on a machine that holds the key, with `scripts/sign-labdesk.ps1`.

## What signing buys, and what it does not

Windows judges an installer on the identity behind its signature, not on the
presence of one.

- **Unsigned.** SmartScreen warns on first run for every user. Windows 11's
  Smart App Control, where it is enabled, blocks unknown unsigned code outright
  rather than warning.
- **Self-signed.** The file carries a real signature and a publisher name, and
  it verifies on any machine that has been told to trust the certificate.
  Everywhere else it is worse than nothing to look at: Windows reports a
  signature from an untrusted publisher. This is the right choice for a fleet
  you administer and the wrong one for software strangers install.
- **Signed by a public certificate authority.** Verifies everywhere with no
  preparation. Note that extended-validation certificates stopped bypassing
  SmartScreen in 2024, so the expensive tier no longer buys silence; reputation
  accrues to a consistent publisher identity over many clean installs. For
  distribution outside a fleet you control, Microsoft's own recommendation is
  Azure Trusted Signing, at roughly ten dollars a month.

LabDesk currently uses a self-signed certificate. Anyone outside the fleet will
see an untrusted-publisher warning, and Smart App Control will refuse the
installer. Moving to a public certificate is a change of thumbprint in the same
script, not a rework.

## Creating the certificate

Once, on the machine that will do the signing. The private key stays in that
user's certificate store and is never exported to the repository, to
continuous integration, or to a command line.

```powershell
New-SelfSignedCertificate `
  -Type CodeSigningCert `
  -Subject "CN=LabDesk, O=trapLab" `
  -FriendlyName "LabDesk code signing" `
  -KeyUsage DigitalSignature `
  -KeyAlgorithm RSA -KeyLength 3072 -HashAlgorithm SHA256 `
  -KeyExportPolicy Exportable `
  -CertStoreLocation Cert:\CurrentUser\My `
  -NotAfter (Get-Date).AddYears(3)
```

Record the thumbprint it prints. `-KeyExportPolicy Exportable` is what lets you
back the key up; without a backup, losing the machine means every future
release is signed by a different publisher, and any trust you deployed has to
be deployed again.

Back it up to a password manager, not to a file beside the code:

```powershell
# Prompts for the password rather than taking it on the command line.
$pw = Read-Host -AsSecureString "Export password"
Export-PfxCertificate -Cert Cert:\CurrentUser\My\<THUMBPRINT> `
  -FilePath labdesk-signing.pfx -Password $pw
```

## Signing a release

```powershell
# With no thumbprint it lists what it can find, which is how you get the value.
.\scripts\sign-labdesk.ps1 -Path .\dist

.\scripts\sign-labdesk.ps1 -Path .\dist -Thumbprint <THUMBPRINT>
```

It signs every `.exe` and `.msi` it finds, timestamps each one, and then
verifies each one separately. Signing and verifying are different questions,
and a signature that does not verify is worse than none because it looks
handled. Timestamping is on by default: without it the signature dies with the
certificate, so every installer you ever shipped breaks on the day it expires.

On a machine that has not been told to trust the certificate, signing succeeds
and verification fails with

```
SignTool Error: A certificate chain processed, but terminated in a root
certificate which is not trusted by the trust provider.
```

That is expected for a self-signed certificate and the script says so. On a
machine that does trust it, the same message is a real failure.

## Making your machines trust it

Export the public half. This file contains no private key and is safe to
distribute.

```powershell
Export-Certificate -Cert Cert:\CurrentUser\My\<THUMBPRINT> `
  -FilePath labdesk-signing.cer
```

Then install it into **Trusted Root Certification Authorities** and **Trusted
Publishers** on each machine that should accept LabDesk installers.

> Windows deliberately requires a human to confirm adding a root certificate.
> Running `Import-Certificate` into the root store from a script raises a
> security dialog and waits for a person, so this step cannot be automated on a
> single machine and must not be scripted as though it can. Deploy it through
> management instead, which is the supported path and prompts nobody.

**Group Policy.** Computer Configuration, Policies, Windows Settings, Security
Settings, Public Key Policies. Import the `.cer` into both Trusted Root
Certification Authorities and Trusted Publishers.

**Intune.** Devices, Configuration, Create policy, Windows 10 and later,
Templates, Trusted certificate. Upload the `.cer` and choose the Computer
certificate store, Root. Add a second profile targeting Trusted Publishers.

**One machine, by hand, elevated.** Only where management is not available:

```powershell
Import-Certificate -FilePath labdesk-signing.cer `
  -CertStoreLocation Cert:\LocalMachine\Root
Import-Certificate -FilePath labdesk-signing.cer `
  -CertStoreLocation Cert:\LocalMachine\TrustedPublisher
```

Adding a root certificate means that key can vouch for any software on that
machine. Deploy it only to machines you administer, and only from a copy you
produced.

## Verifying a machine ended up in the right state

```powershell
Get-AuthenticodeSignature .\LabDesk-1.2.0-x86_64-install.exe |
  Format-List Status, SignerCertificate, TimeStamperCertificate
```

`Status` reads `Valid` on a trusting machine. `UnknownError` with the LabDesk
subject present means the file is signed but this machine does not trust the
publisher, which is the untrusted-root case above, not a broken signature.

## When the certificate expires

Timestamped signatures stay valid after expiry, so already-released installers
keep working. New releases need a new certificate, and a new self-signed
certificate is a new publisher identity that every machine has to be told to
trust again. Certificates from a public authority are capped at 460 days from
2026-03-01 under CA/Browser Forum ballot CSC-31, so that rotation becomes
annual if LabDesk moves to one.

# Signing the update manifest

Every release publishes `SHA256SUMS`, a line per asset giving that asset's
SHA-256, and `SHA256SUMS.sig`, a detached Ed25519 signature over that file.
`.github/workflows/release-checksums.yml` produces both. The installed client
carries the public half as a constant and checks the signature before it
believes any digest in the manifest, in `src/updater.rs`.

The same workflow carries a `release-dry-run` job. It makes those two files
from a fixture and a key that lives for one job, checks the signature is the 64
raw bytes the client expects, and checks that a manifest edited afterwards no
longer verifies. It reads no secret and publishes nothing. It runs on pull
requests that touch this page, the workflow or `src/updater.rs`, so an openssl
change on the runner, or a mistake in the commands below, is found there rather
than on a production tag.

## Why the digest alone is not enough

The digest was worth having on its own. It closes tampering in transit, a
poisoned cache, a truncated download, and a file swapped in the temporary
directory by another local user between the download and the elevated install.

What it cannot close is the case where the thing publishing the digest is the
thing that has been taken over. The digest and the asset come out of the same
GitHub release and travel through the same Cloudflare Worker, so anyone who
controls the Worker controls both halves and can serve a matching pair. The
client hashes the file, the hash agrees, and it hands a hostile installer to a
process running as SYSTEM or root, unattended, on every machine in the fleet.
That is the whole reason this project exists to be careful about, so a hash was
always going to be the first half of the answer and not the answer.

A detached signature closes that half. The private key never reaches the site,
so a compromised Worker can serve any bytes it likes and still cannot produce a
manifest the client accepts. It also closes a release asset that was replaced
without the pipeline running again, because the published signature still
covers the digests the manifest had when it was signed. The client pins the
public half at build time, so nothing served at runtime gets to nominate the
key that vouches for the update.

What it does not close is an actor who can make the pipeline sign for them, and
several other things worth naming. Read
[What this does not close](#what-this-does-not-close) before deciding this
problem is solved.

## Where the two halves live

- **Private key.** A repository secret named `RELEASE_SIGNING_KEY`, holding an
  Ed25519 private key as a PKCS#8 PEM. Only the signing step of
  `release-checksums.yml` reads it. It is written to the runner with `umask
  077` and removed by a shell trap however that step ends.
- **Public key.** `RELEASE_SIGNING_PUBLIC_KEY_B64` in `src/updater.rs`, base64
  of the raw 32 bytes. It is compiled into every client.

This key does live in continuous integration, unlike the Authenticode key
above, and that is a deliberate difference rather than an oversight. It has to
sign an artifact that only the pipeline can produce, at the moment the pipeline
produces it, so there is nowhere else for it to be without a human signing
every release by hand. What makes it acceptable is the blast radius: the
Authenticode key vouches for arbitrary code to Windows itself on any machine
that trusts the publisher, while this one vouches for one file in one update
channel, and replacing it is a new secret plus a client release rather than a
new publisher identity every machine has to be told about again.

## What this does not close

Written down because a page that says a threat is closed will stop anyone
looking for the ones that are not.

**Anyone who can make the pipeline sign.** The private key is a secret in this
repository and this workflow has a `workflow_dispatch` trigger, so repository
write access, a stolen Actions token, a compromised maintainer account, or a
malicious change to a workflow on the default branch is enough: replace the
installer on the release, dispatch **Release checksums**, and the pipeline signs
the new digests with the pinned key. Every enforcing client accepts the result.
Against that actor the signature adds nothing, and the defences are the ones
around the repository: who has write access, branch protection on the default
branch, review on workflow files, and required two-factor authentication.

**A downgrade, or a fleet frozen on a known-bad build.** The signature carries
no version, no timestamp and no expiry, and the client only asks that the
offered version be higher than the one it is running
(`src/common.rs`, `do_check_software_update`). A compromised site can therefore
answer the update check with an older release that is still newer than what a
machine has, say 1.2.3 while 1.9.0 carries the fix, and serve that release's
genuine manifest, genuine signature and genuine asset. Every check passes and
the fleet sits on a build with a known hole for as long as the site keeps
answering that way. What the mechanism does bind is a manifest to the release
its asset came from: the client fetches `SHA256SUMS` from the same
`/releases/download/<version>/` path as the file, so a manifest from one release
cannot vouch for another release's asset.

**Denial of updates.** A site that 404s the manifest, or serves a signature that
does not verify, stops every enforcing client from updating at all. That is the
deliberate direction to fail in, and it is still a fleet that cannot be patched.
It is also indistinguishable, from the client, from a release that was never
backfilled, which is why the backfill in
[Turning enforcement on](#turning-enforcement-on) is not optional.

**Anything after the installer runs.** This vouches for the bytes handed to the
installer. Everything the installer then does with SYSTEM or root rights is
outside it.

## The key ceremony

**Not yet performed.** The constant in `src/updater.rs` is an empty
placeholder, which pins no key, which means the client does not enforce
signatures. That is what makes the pipeline half safe to ship first. Until the
steps below are done, an update is protected by its digest and nothing more.

Do this on a machine you control, not on a runner and not in a shared shell.

```bash
# 1. The keypair. This file is the whole secret; it never enters the repository.
openssl genpkey -algorithm ed25519 -out labdesk-release-signing.pem

# 2. The public half, in the form the client's constant wants: base64 of the
#    raw 32 bytes. An Ed25519 SubjectPublicKeyInfo is a 12-byte header plus the
#    key, so the last 32 bytes of the DER are the key itself.
openssl pkey -in labdesk-release-signing.pem -pubout -outform DER | tail -c 32 | base64 -w0

# 3. The public half as a PEM as well, for verifying releases by hand later.
#    This file is not a secret.
openssl pkey -in labdesk-release-signing.pem -pubout -out labdesk-release-signing.pub.pem
```

On macOS, `base64` has no `-w` flag; drop it and remove the line breaks by hand,
or use `openssl base64 -A`.

Then:

4. Put the contents of `labdesk-release-signing.pem`, the whole PEM including
   the `BEGIN PRIVATE KEY` and `END PRIVATE KEY` lines, into the repository
   secret `RELEASE_SIGNING_KEY` (Settings, Secrets and variables, Actions).
5. Put the private key in the password manager, and the public PEM somewhere
   you can find it. Losing the private key is recoverable but not cheap: see
   [rotation](#rotation-and-loss).
6. Delete the private PEM from the machine's disk once both copies exist.

## Turning enforcement on

Only after every release channel has a signed manifest, in this order.

1. **The workflow is on the default branch.** GitHub runs the default branch's
   copy of a `workflow_run` workflow, and offers `workflow_dispatch` only for
   workflows that exist there, so on a feature branch the file does nothing.
2. **The secret is set**, as above. Until it is, `release-checksums.yml` still
   publishes digests but ends red on every run. That red mark is the reminder,
   deliberately chosen over a warning in a log.
3. **The site can serve the manifest.** See the outstanding item below.
4. **Every published tag is backfilled.** Actions, Release checksums, Run
   workflow, once per tag that any release channel points at. Older releases
   have neither file, and a client that enforces signatures refuses an update
   whose manifest it cannot fetch and verify.
5. **Only then** paste the base64 public key into
   `RELEASE_SIGNING_PUBLIC_KEY_B64` in `src/updater.rs` and cut a client
   release. That constant is the switch, and it is the only change needed:
   filling it in makes every client built from that commit demand a signature.

Step 5 before step 4 gives you a fleet that refuses to update, which is the
safe direction to fail in and still a dead update channel.

## Outstanding: the site does not serve the manifest yet

The client fetches `https://lab-desk.net/releases/download/<version>/SHA256SUMS`
and `.../SHA256SUMS.sig`. As the site stands, both return 404.

`labdesk-site/src/worker/routes/updates.ts:124` resolves every download through
`resolvePublishedAsset` (`:60`), which only accepts a name that appears in the
release channel row's per-platform asset map (`:64`). `SHA256SUMS` and
`SHA256SUMS.sig` are release assets but not platform assets, so they are not in
that map. The existing digest route (`:97`) reads the manifest server side and
returns one asset's digest as text, which is not a byte stream a signature can
be checked against.

The site needs to serve those two names verbatim from the published release.
That is a change in the site repository, not this one, and it belongs to
whoever owns the updates route. Until it lands, leave the public key constant
empty; the client on the digest path does not ask for either file.

## Verifying a release by hand

With the public PEM from step 3 of the ceremony:

```bash
curl -fsSLO https://lab-desk.net/releases/download/1.2.2/SHA256SUMS
curl -fsSLO https://lab-desk.net/releases/download/1.2.2/SHA256SUMS.sig
openssl pkeyutl -verify -rawin -pubin -inkey labdesk-release-signing.pub.pem \
  -in SHA256SUMS -sigfile SHA256SUMS.sig
```

`Signature Verified Successfully` is the only acceptable answer. Anything else,
including `Signature Verification Failure`, means the manifest is not the one
the pipeline signed, and the release should be treated as compromised until
proven otherwise rather than re-signed to make the message go away.

## Rotation and loss

The public key is compiled into clients, so changing it is a client release,
and clients that have not taken that release still expect the old key. Rotation
is therefore: generate the new pair, ship a client that pins the new public
key, wait for the fleet to take it, then change the secret and re-run the
backfill for every published tag. Changing the secret first strands every
client that has not updated yet, which is exactly the population that most
needs to be able to update.

If the private key is lost with no compromise, the same sequence applies
without the hurry. If it is believed to be compromised, the order has to invert
and the fleet has to be told, because a client that still pins the old key will
accept anything the holder of that key signs. Nothing in the client lets a
server revoke a pinned key, by design, so there is no shortcut here.
