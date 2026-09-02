# Signing LabDesk releases

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
