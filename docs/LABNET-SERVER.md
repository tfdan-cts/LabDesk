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

## As built, 2026-09-03

The server exists. What follows is what was done, so the next person does not repeat it.

- Oracle Cloud, tenancy `trapadmin`, region us-chicago-1, availability domain 1. Instance
  `labnet-netbird`, `VM.Standard.A1.Flex` with 1 OCPU and 6 GB, Ubuntu 24.04 Minimal aarch64,
  50 GB boot volume. Public address `64.181.204.25`, private `10.30.20.160`. This VM bills
  (the tenancy's free A1 hours are used by other instances): $0.01 per OCPU-hour plus
  $0.0015 per GB-hour, about $14 a month.
- Its own network security group, `labnet-netbird`: ingress 80/tcp, 443/tcp, 3478/udp from
  anywhere; the VCN's shared security list was left alone. The host firewall carries the same
  three ports, persisted in `/etc/iptables/rules.v4` (Oracle's images reject by default).
- SSH from the workstation goes through the Safe Sight backend as a jump host:
  `ssh -J ubuntu@100.111.222.91 ubuntu@10.30.20.160`. Port 22 is reachable only from inside
  the subnet.
- `nb.lab-desk.net` is an `A` record to the public address, proxied off.
- Installed with `getting-started.sh` from the v0.78.0 release, unattended
  (`NETBIRD_DOMAIN`, `NETBIRD_LETSENCRYPT_EMAIL=mgmtsrvr@lab-desk.net`,
  `NETBIRD_REVERSE_PROXY_TYPE=0`, `NETBIRD_NON_INTERACTIVE=true`) as root, in
  `/home/ubuntu/netbird/`. Three containers: `netbird-traefik`, `netbird-server`,
  `netbird-dashboard`. Certificate from Let's Encrypt, valid to 2026-12-03 and renewed by
  Traefik.
- The first admin was created through the setup API with `NB_SETUP_PAT_ENABLED=true` set on
  `netbird-server` for that one step and removed afterwards. Admin: `trapadmin@proton.me`,
  password in `/root/netbird-admin.txt` on the VM, mode 600, nowhere else. Sign in at
  `https://nb.lab-desk.net`.
- Service user `lab-desk-net` (admin) with token `labdesk-worker`, valid to 2027-09-04, in
  `/root/netbird-labdesk-token` on the VM (mode 600) and on the lab-desk.net Worker as
  `NETBIRD_TOKEN`, alongside `NETBIRD_API_URL=https://nb.lab-desk.net`. Renew before it expires.
- The default all-to-all policy was deleted. Verified from outside: `GET /api/peers` 200 `[]`,
  `GET /api/policies` `[]`, a STUN binding request to UDP 3478 answered.

## What is exposed, and why each port exists (verified 2026-09-03)

The owner asked whether the open ports are needed at all. Each was checked against the
server's own configuration and the client source, not the installer's summary.

| Port | Verdict | Evidence |
|---|---|---|
| 80/tcp | **Closed.** | Traefik obtains certificates by TLS-ALPN on 443 (`--certificatesresolvers.letsencrypt.acme.tlschallenge=true`), so 80 only served an HTTP-to-HTTPS redirect. Removed from Traefik, the host firewall and the security group. |
| 443/tcp | **Open, and necessary; the admin paths on it are fenced.** | Peers register and receive their network map over gRPC (`/management.ManagementService/`), exchange connection candidates over gRPC (`/signalexchange.SignalExchange/`), and fall back to the relay over WebSocket (`/relay`, `/ws-proxy/`). Every one of those is TLS, and a peer authenticates with its one-off setup key and its WireGuard key; the server never holds a peer's private key and cannot read relayed traffic. The daemon never calls `/api` or `/oauth2` (no code path in `client/` does), so `/api`, `/oauth2` and the dashboard sit behind a Traefik IP allow list: Cloudflare's published ranges (the lab-desk.net Worker's calls arrive from 172.69.x, measured with a probe Worker), the VM's own address and its Docker network. From anywhere else they answer 403. |
| 3478/udp | **Open, kept by owner decision (2026-09-03).** | STUN. A peer sends one small request and learns the public address and port its NAT gave it, which is what lets two machines behind two NATs connect directly. The server can replace it with external STUN (`server.stuns` in `config.yaml`; the embedded listener switches off when external servers are listed, `combined/cmd/config.go`), or run without STUN (peers then meet only through the relay on 443). |
| 22/tcp | Reachable from inside the subnet only (the shared security list allows it from 10.30.20.8, the jump host). | |
| 111 (rpcbind) | **Disabled.** Ubuntu's default `rpcbind` was listening on every interface for nothing this server does. | |

Operator access to the dashboard and API now goes through the box: from the VM itself
(`curl https://nb.lab-desk.net/api/...`), or through an SSH tunnel from the workstation:

```
ssh -J ubuntu@100.111.222.91 -L 8443:localhost:443 ubuntu@10.30.20.160
```

then `curl --resolve nb.lab-desk.net:8443:127.0.0.1 https://nb.lab-desk.net:8443/api/users`
(the routers match on the host name, so the name must be kept). A browser needs a hosts-file
entry for the same reason.

What the design does not do: expose the network. A machine that enrols becomes reachable to
nobody until a session rule or a labnet names it, and the data path between two machines is
WireGuard between those two machines. The control plane coordinates; it does not carry.
