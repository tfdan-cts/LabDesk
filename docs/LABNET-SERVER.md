# The labnet server

labnet, LabDesk's encrypted direct path, runs on a NetBird control plane that
LabDesk hosts itself: management, signal, relay and STUN in one container,
behind Traefik, on one small Linux VM. Clients never talk to lab-desk.net
about it except to be told which server to register with; the server's API
token lives only in the lab-desk.net Worker.

This is the runbook for standing that server up and for handing its token to
the Worker. Everything a client does is in `docs/CONSOLE.md`.

## What the VM needs

Verified against NetBird's own documentation and the v0.78.0 source:

- A Linux VM with at least 1 CPU and 2 GB of memory. The Oracle free tier
  shape the owner chose (2 CPU, 12 GB) is well above that.
- A public name that resolves to the VM: `nb.lab-desk.net`. Add it in
  Cloudflare DNS as an `A` record with the proxy **off** (grey cloud). The
  clients speak gRPC over HTTP/2 and STUN over UDP, neither of which goes
  through Cloudflare's proxy.
- Inbound TCP 80 and 443, and inbound UDP 3478, open on the VM's firewall and
  on the Oracle security list. Oracle's default list drops UDP; without 3478
  peers still connect, but relayed rather than direct.
- Docker with the compose plugin, `curl`, `jq`.

## Install

```
curl -fsSL https://github.com/netbirdio/netbird/releases/download/v0.78.0/getting-started.sh | bash
```

Pick the bundled Traefik when asked. The script writes `docker-compose.yml`,
`config.yaml` and `dashboard.env` and starts three containers: `traefik`,
`dashboard` and `netbird-server`. TLS comes from Let's Encrypt over port 80.

Then open `https://nb.lab-desk.net`. With no users yet it redirects to
`/setup`, where the first admin account is created. No external identity
provider is needed; NetBird keeps local users itself since 0.62.

## Make the network closed by default

A fresh NetBird account carries a policy named `Default` that lets every
peer reach every other peer. labnet is built on the opposite: a machine is
reachable by nobody until a session rule or a labnet says otherwise. Delete
that policy before any machine enrols. In the dashboard: Access Control,
Policies, delete `Default`. Or by API, once the token below exists:

```
curl -H "Authorization: Token $NETBIRD_TOKEN" https://nb.lab-desk.net/api/policies
curl -X DELETE -H "Authorization: Token $NETBIRD_TOKEN" https://nb.lab-desk.net/api/policies/<id>
```

The Worker refuses to enrol anything while a policy with the `All` group as a
source still exists, so a forgotten step shows up as a plain sentence on the
first machine, not as an open network.

## The Worker's token

Create a service user in the dashboard (Team, Service Users) and a personal
access token for it. Store it on the Worker without ever putting it on a
command line that a transcript records:

```
cd labdesk-site
wrangler secret put NETBIRD_API_URL     # https://nb.lab-desk.net
wrangler secret put NETBIRD_TOKEN       # the personal access token
```

Both are read at request time; nothing needs a redeploy.

## Prove it

From any machine:

```
curl -H "Authorization: Token $NETBIRD_TOKEN" https://nb.lab-desk.net/api/peers
```

answers `200` and `[]` before the first enrolment, and
`https://nb.lab-desk.net/api/policies` answers `[]` once `Default` is gone.
After the first machine turns on encrypted direct connections under This
machine, `netbird status --json` on it reports `management.connected: true`
and `signal.connected: true`.

## What the clients are told

The Worker hands each enrolling machine the management address it holds in
`NETBIRD_API_URL` and a one-off setup key it created for that machine's own
group. Nothing else about the server reaches a client.
