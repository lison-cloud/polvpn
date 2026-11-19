# polvpn

Your own WireGuard VPN server, in any Google Cloud zone, from scratch, with one command.

polvpn is meant for one person with a few devices (laptop, phone, tablet). It creates a small
VM with OpenTofu, sets up WireGuard on it with Ansible, and gives you a config file and a QR
code for each device. You can run several servers in different places, for example `fra` in
Frankfurt and `nyc` in South Carolina, and remove them when you don't need them.

```
./polvpn up fra europe-west3-a
```

Everything (OpenTofu, Ansible, gcloud, ssh) runs inside a Docker "toolbox" image that the
`polvpn` script builds for you. You don't install any of those tools yourself.

## Prerequisites

- Linux or macOS with **bash 4.4 or newer** and **Docker**. Your user must be able to run
  `docker ps` without sudo. `curl` is used to find your public IP.
  macOS ships bash 3.2: run `brew install bash` and make sure the Homebrew bash comes first
  in your `PATH` (`./polvpn` runs the first `bash` in `PATH`), or start polvpn with it
  explicitly: `"$(brew --prefix)/bin/bash" ./polvpn ...`. polvpn refuses to run on an older
  bash and tells you so.
- A **Google Cloud account with billing enabled**. The free trial credit works.

## Google Cloud setup

1. Create a project at <https://console.cloud.google.com/projectcreate>, or with
   `gcloud projects create <id>` if you already have gcloud. Note the **project ID** (for
   example `my-vpn-123456`), which is not always the same as the project name.
2. Link a billing account to it: *Billing → Link a billing account*
   (<https://console.cloud.google.com/billing/linkedaccount>).
3. You don't need to enable any APIs. OpenTofu enables the Compute Engine API on the first
   `up`, which can take a minute.
4. Credentials: use **one** of these.
   - `./polvpn login` signs you in with your Google account. You get a URL to open in any
     browser, then you paste the code back. The credentials are stored in `.secrets/gcloud/`.
   - A **service-account key**: create a service account with the roles
     *Compute Admin*, *Service Usage Admin* and *Service Account User* (or simply *Editor*),
     download a JSON key and save it as `.secrets/gcp-sa.json`. If this file exists,
     polvpn uses it instead of the login credentials.

## Quick start

```sh
./polvpn init my-vpn-123456      # builds the toolbox, creates an SSH key, runs tofu init
./polvpn login                   # skip if you use .secrets/gcp-sa.json
./polvpn up fra europe-west3-a   # create the server and print the QR codes
```

The first run builds the toolbox image, which takes a few minutes. Later runs reuse it.

When `up` finishes, it prints the path of each client config and shows its QR code in the
terminal:

```
clients/fra/laptop.conf   clients/fra/laptop.png   clients/fra/laptop.qr.txt
clients/fra/phone.conf    clients/fra/phone.png    clients/fra/phone.qr.txt
```

By default polvpn creates two clients, `laptop` and `phone`. To change them, see
[Adding and removing devices](#adding-and-removing-devices).

## Commands

| Command | What it does |
|---|---|
| `./polvpn init [project-id]` | Checks Docker, builds the toolbox, creates `.secrets/polvpn_ed25519`, saves the project ID to `tofu/terraform.tfvars`, runs `tofu init`. Asks for the project ID if you don't give one. You can run it again to change the project. |
| `./polvpn login` | Google sign-in, using a URL and a code you paste back. Sets up both gcloud and Application Default Credentials, and sets the quota project. |
| `./polvpn up <name> <zone> [machine_type]` | Adds the server (or updates it), runs `tofu apply`, configures WireGuard and prints the client files and QR codes. Without a machine type, a new server gets `e2-micro` and an existing server keeps its current type. Only the `e2-*`, `n1-*`, `n2-*` and `n2d-*` families are accepted. |
| `./polvpn down <name>` | Deletes that server, its static IP, its known_hosts entries and `clients/<name>/`. |
| `./polvpn list` | Shows your servers with their zone, machine type, IP and status. |
| `./polvpn sync [name]` | Runs OpenTofu and Ansible again, for all servers or just one. Use it after you edit clients, or when your IP has changed. |
| `./polvpn qr <server> <client>` | Prints a client's QR code again. |
| `./polvpn zones` | Lists the available GCP zones. |
| `./polvpn ssh <name> [args]` | Opens an SSH session on the server with the project key. |
| `./polvpn destroy` | Deletes **all** cloud resources after you type the project ID to confirm. Keeps your key and settings. |
| `./polvpn shell [cmd]` | Opens a shell in the toolbox, or runs one command there, for debugging. |
| `./polvpn help` | Shows the usage. |

A server name uses lowercase letters, digits and `-`. It must start with a letter and be at
most 20 characters long.

These environment variables change how polvpn works:

| Variable | Effect |
|---|---|
| `POLVPN_ADMIN_CIDR` | The address range allowed to SSH in, instead of the detected IP, for example `203.0.113.7/32`. You can give several, separated by commas. |
| `POLVPN_PROJECT` | The project ID for `init`, so it doesn't ask. |
| `POLVPN_ASSUME_YES=1` | Skips the confirmation in `destroy`. |
| `POLVPN_REBUILD=1` | Rebuilds the toolbox image. The image is also rebuilt automatically when `tools/Dockerfile` changes. |

## Choosing a zone

Pick a zone close to you for the lowest latency, or in the country you want your traffic to
appear from. Any zone works, and `./polvpn zones` shows all of them.

| City | Zone |
|---|---|
| Oregon, USA (free tier) | `us-west1-b` |
| Iowa, USA (free tier) | `us-central1-a` |
| South Carolina, USA (free tier) | `us-east1-b` |
| N. Virginia, USA | `us-east4-a` |
| Los Angeles, USA | `us-west2-a` |
| Montréal, Canada | `northamerica-northeast1-a` |
| São Paulo, Brazil | `southamerica-east1-a` |
| London, UK | `europe-west2-a` |
| Belgium | `europe-west1-b` |
| Netherlands | `europe-west4-a` |
| Frankfurt, Germany | `europe-west3-a` |
| Paris, France | `europe-west9-a` |
| Madrid, Spain | `europe-southwest1-a` |
| Warsaw, Poland | `europe-central2-a` |
| Finland | `europe-north1-a` |
| Tel Aviv, Israel | `me-west1-a` |
| Mumbai, India | `asia-south1-a` |
| Singapore | `asia-southeast1-a` |
| Tokyo, Japan | `asia-northeast1-a` |
| Sydney, Australia | `australia-southeast1-a` |

To move a server, run `up` with the same name and a new zone. OpenTofu replaces the VM, so
all WireGuard keys are generated again and the client files are rewritten. A move to another
region also gives the server a new IP; a move within the same region keeps it. Either way,
import the new files on your devices.

## Importing configs on your devices

Install the official WireGuard app from <https://www.wireguard.com/install/>.

- **Phone or tablet (Android, iOS):** in the app tap **+**, then **Scan from QR code**, and
  scan the QR code shown in your terminal. You can show it again with
  `./polvpn qr fra phone`, or open `clients/fra/phone.png`.
- **Windows or macOS:** in the app choose **Import tunnel(s) from file** and pick
  `clients/<server>/<client>.conf`.
- **Linux:** `sudo cp clients/fra/laptop.conf /etc/wireguard/fra.conf && sudo wg-quick up fra`,
  or import the file in NetworkManager with
  `nmcli connection import type wireguard file clients/fra/laptop.conf`.

Each device should have its own client entry. Don't use the same config on two devices at the
same time.

The `.conf` files contain private keys. Treat them like passwords, and delete copies you
send to other devices once you have imported them.

## Adding and removing devices

You define clients in `ansible/group_vars/all.yml`:

```yaml
wg_clients:
  - name: laptop
    id: 2
  - name: phone
    id: 3
  - name: tablet   # new
    id: 4          # unique, 2-254; gives the client the tunnel address 10.66.66.4
```

After you edit the file, apply the change to every server with:

```sh
./polvpn sync          # or: ./polvpn sync fra
```

When you add a client, sync creates its files under `clients/<server>/`. When you remove an
entry, sync revokes that client on the server and deletes its local files. Existing clients
keep their keys, so you don't need to import them again on your other devices.

## Costs

polvpn uses one `e2-micro` VM per server by default, which is enough for a few devices. Each
server has a 10 GB standard persistent disk (`pd-standard`); disk speed doesn't matter for a VPN.

Machine types are limited to the `e2`, `n1`, `n2` and `n2d` families: the x86 Debian 12 image
and the `pd-standard` boot disk don't work on the other families (for example Arm `t2a` or
the newer `c4`/`n4`).

- The always-free tier covers one `e2-micro` per month and 30 GB-months of standard
  persistent disk, **only in `us-west1`, `us-central1` and `us-east1`**. So one free-tier
  server there costs nothing for the VM and the disk (a second server, or a larger machine
  type, is billed). In any other region the VM and the disk are billed at the normal rate.
- **Outbound traffic (egress) is billed per GB, and it is usually the main cost** of a VPN:
  everything you download through the tunnel leaves Google's network again to reach you.
  Watching video over the VPN adds up quickly.
- The static external IPv4 address can also cost a little, and so does the disk outside the
  free tier.
- Prices change and depend on the region. Check the current
  [Compute Engine pricing](https://cloud.google.com/compute/all-pricing),
  [network pricing](https://cloud.google.com/vpc/network-pricing) and
  [free tier](https://cloud.google.com/free/docs/free-cloud-features#compute) pages, and set a
  [budget alert](https://console.cloud.google.com/billing/budgets) on your billing account.
- Remove servers you don't use with `./polvpn down <name>`, or remove everything with
  `./polvpn destroy`.

## Security notes

- Inbound, the firewall allows only WireGuard (UDP 51820), ping (ICMP) and SSH (TCP 22). **SSH is open only to the
  public IP you had when you last ran `up`, `sync` or `down`.** polvpn detects your IP with
  api.ipify.org. Set `POLVPN_ADMIN_CIDR` to use a different range.
- Home and mobile IPs change. If `./polvpn ssh` or `sync` times out, your IP has probably
  changed. Run `./polvpn sync` from where you are now. OpenTofu updates the firewall
  before Ansible connects, so this fixes it. WireGuard keeps working the whole time.
- Login is by key only, with a key created just for this project
  (`.secrets/polvpn_ed25519`). Host keys are pinned in `.secrets/known_hosts` per VM
  instance (under the name `polvpn-<name>-<instance id>`), not per IP, so a replaced VM
  that keeps its IP is not mistaken for an attacker.
- `.secrets/` (keys and Google credentials) and `clients/` (WireGuard private keys) are in
  `.gitignore`. Never commit them. Back up `.secrets/` if you want to manage the servers from
  another machine.
- The OpenTofu state (`tofu/terraform.tfstate`) is kept locally and contains your
  server details. Don't delete it while servers exist, or polvpn will lose track of them.
  You would then have to delete them in the Cloud Console.

## Troubleshooting

| Problem | Fix |
|---|---|
| `cannot talk to the Docker daemon` | Start Docker. On Linux, add your user to the `docker` group, then log out and back in. |
| `no Google Cloud credentials` | Run `./polvpn login`, or save a service-account key as `.secrets/gcp-sa.json`. |
| `... API has not been used in project ... or it is disabled` | Wait a minute after the first `up` and run it again. Enabling an API takes time to propagate. Make sure billing is linked to the project. |
| `Billing account ... is not found` / `billing must be enabled` | Link a billing account to the project (see [Google Cloud setup](#google-cloud-setup)). |
| `ZONE_RESOURCE_POOL_EXHAUSTED` or the machine type is not available | Try another zone in the same region (`-b`, `-c`), or a different machine type. |
| `zones` says the Compute API is not enabled | Run `./polvpn up` once (OpenTofu enables the API), or look the zone up in the table above. |
| SSH or Ansible times out | Your public IP has probably changed. Run `./polvpn sync`. If you are behind a proxy or have a strange route, set `POLVPN_ADMIN_CIDR=<ip>/32`. |
| `could not detect your public IP` | No internet access, or the IP services are blocked. Set `POLVPN_ADMIN_CIDR=<your ip>/32`. |
| `REMOTE HOST IDENTIFICATION HAS CHANGED` | Host keys are pinned per VM instance, so this should not happen when polvpn replaces a VM. If the host key of the same instance changed, find out why first. To accept it anyway, run `./polvpn shell ssh-keygen -R polvpn-<name>-<instance id> -f .secrets/known_hosts` (the instance id is in `ansible/inventory/hosts.yml` as `gcp_instance_id`), then run `sync` again. |
| `up` stops at "Wait for the freshly booted VM to accept SSH" and times out, although your IP is right | Your project is probably in an organization that enforces the `constraints/compute.requireOsLogin` policy. OS Login then ignores the `ssh-keys` metadata that polvpn uses to install its key. Use a project outside an organization, or ask your admin to relax that policy for the project. |
| `constraints/iam.disableServiceAccountKeyCreation` when creating a service-account key | Your organization forbids service-account keys. Use `./polvpn login` instead. |
| The VPN connects but no traffic flows | Make sure the device clock is right and that UDP 51820 isn't blocked on your network. Run `./polvpn sync <name>`, then `./polvpn ssh <name> sudo wg show` and check the "latest handshake" line. |
| Files owned by the wrong user, or `permission denied` in the container | polvpn runs the toolbox as your uid/gid. With rootless Docker or user namespaces, the IDs may be mapped differently. Run polvpn with a normal Docker setup. |
| Something odd in the toolbox | Run `POLVPN_REBUILD=1 ./polvpn help` to rebuild it, or `./polvpn shell` to look around (`tofu`, `ansible`, `gcloud` are all there). |

## How it works

- `tools/Dockerfile` is the toolbox image. It contains OpenTofu, ansible-core, the
  Google Cloud CLI, OpenSSH, qrencode and wireguard-tools, all at pinned versions. The image
  is built with your uid/gid so files it writes belong to you, and so OpenSSH finds a user
  entry. Its tag is a hash of the Dockerfile, so editing the Dockerfile triggers a rebuild.
- `tofu/` contains the network, the firewall, a static IP and a Debian VM per entry in
  `tofu/servers.auto.tfvars.json`. polvpn manages that file for you. OpenTofu also
  writes the Ansible inventory.
- `ansible/` installs and configures WireGuard, creates the client keys and QR codes, and
  fetches them to `clients/<server>/`.
