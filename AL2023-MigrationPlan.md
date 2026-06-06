# Plan: AL2 → AL2023 for future spot launches

## Context
The single spot instance behind `alireza.me` runs on AL2 (kernel 4.14, Python 2.7). AWS standard support for **Amazon Linux 2 ends 2026-06-30** — after that, no security patches.

Important constraint: the local ansible is **ansible-core 2.17.4** which dropped Python 2.7 support on managed nodes in 2.16. That's why `ansible/config.mainServer.yml` disables the `yum:` module (`when: false`, line 32-37) and uses `shell: yum ...` instead — AL2's Python 2.7 can't run modern ansible modules. AL2023 ships Python 3.9 → modern ansible modules (`dnf:`, `package:`, etc.) *should* work cleanly. But this assumption needs to be **verified empirically** before we commit any playbook changes.

This document is split into **two plans**:

- **Plan 1 (now)** — minimal AL2023 discovery launch, no playbook changes, no commits to `launch.spec.json`. Goal: collect facts about the AL2023 environment that Plan 2 will depend on.
- **Plan 2 (later)** — the actual migration. Drafted only after Plan 1's outcomes are recorded.

---

## Plan 1: AL2023 discovery launch

### Scope
**Opportunistic test** — wait for AWS to reclaim the production spot, then use the now-free AZ-a ENI to launch a throwaway AL2023 spot in its place. Run probes, record findings, tear down, then restart production on AL2. Trigger is unpredictable (current run 6+ days, prior max 192d in AZ a). Cost of waiting: zero. Cost of the test window: ~30-60 min of downtime for `alireza.me` services (production is already down at that moment due to the spot kill, so we're extending the outage by the probe duration + AL2 relaunch + ansible bootstrap).

### Pre-staged artifacts (prepare now, fire on trigger)
- **test.spec.json** — uncommitted, kept locally next to `launch.spec.json`. Identical to `launch.spec.json` except `ImageId` is the AL2023 AMI (`ami-098e39bafa7e7303d`). Reuses the production ENI `eni-0c189b31eb3005be1`.
- **probes.sh** — script that SSHes into the test instance and runs all 12 environment probes + 3 ansible probes (see tables below), capturing output to a timestamped log.
- **Trigger watcher** — quick check: `aws --profile root ec2 describe-instances --instance-ids i-0626dba62d335753f --query 'Reservations[].Instances[].State.Name' --output text`. When this returns anything other than `running` (e.g., `terminated`, `shutting-down`), the ENI is free.

### Procedure (executed when spot is killed)
1. **Confirm production instance is gone** and ENI is detached:
   ```bash
   aws --profile root ec2 describe-network-interfaces \
     --network-interface-ids eni-0c189b31eb3005be1 \
     --query 'NetworkInterfaces[0].Status'  # expect "available"
   ```
2. **Submit AL2023 spot request** with test.spec.json:
   ```bash
   aws --profile root --region us-east-1 ec2 request-spot-instances \
     --spot-price "0.0075" --instance-count 1 --type "one-time" \
     --launch-specification file://test.spec.json
   ```
3. Wait for `fulfilled`, capture the new instance ID. SSH in (`ssh ec2-user@54.84.117.224` — same public IP since the ENI is unchanged).
4. **Run probes.sh** — 12 env probes + 3 ansible probes. Save log to `probe-findings-YYYYMMDD.log`.
5. **Terminate the AL2023 test instance** (releases the ENI):
   ```bash
   aws --profile root ec2 terminate-instances --instance-ids <test-instance-id>
   # wait until ENI status is "available" again
   ```
6. **Restart production on AL2** (no spec change needed — `launch.spec.json` still has the AL2 AMI):
   ```bash
   ./aws.spot.sh
   # then run ansible bootstrap as usual to restore services
   ```

### Probes (record output for each)
| # | Probe | Command | Why it matters |
|---|---|---|---|
| 1 | Boot mode actually used | `[ -d /sys/firmware/efi ] && echo UEFI \|\| echo BIOS` | AMI is `uefi-preferred`; t3 should be UEFI — confirm |
| 2 | Kernel version | `uname -r` | Confirm 6.1.x |
| 3 | Default Python | `/usr/bin/python3 --version; which python3` | Confirm 3.9.x at expected path (matches `hosts.yml:17`) |
| 4 | Package manager | `dnf --version; rpm -q dnf yum` | Confirm dnf is primary; yum present as alias |
| 5 | OpenSSL major | `openssl version` | Confirm 3.0.x (affects custom Postfix tarball) |
| 6 | SELinux state | `getenforce; sestatus` | Confirm enforcing by default |
| 7 | iptables backend | `iptables --version; alternatives --display iptables` | Confirm nft backend, legacy still callable |
| 8 | xt_recent module | `modprobe xt_recent && lsmod \| grep xt_recent` | Required by existing `/ec2str/ipt.rules` |
| 9 | net-tools (netstat) | `which netstat \|\| echo missing` | Used by `state.mainServer.yml:15` — confirm it's missing so we know to switch to `ss` |
| 10 | LUKS / cryptsetup | `cryptsetup --version` | Required for /ec2Store mount |
| 11 | Required pkgs available | `dnf info bind httpd mod_ssl squid certbot python3-certbot-apache s-nail openssl-devel perl-Mail-SPF perl-Mail-DKIM perl-Sys-Syslog 2>&1 \| grep -E "^(Name\|Error)"` | Verify every package the playbook installs is available |
| 12 | EPEL not required for above | (implicit from probe 11) | Confirm we can drop the EPEL setup task |
| 13 | EBS device symlinks on Nitro | attach a 1 GiB test EBS as `/dev/xvdy`, then `ls -l /dev/xvdy /dev/sdy /dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_*` | Determines whether `config.mainServer.yml:58` (`cryptsetup create ec2Store /dev/xvdx`) needs a device-path rewrite. AWS BDM name is `/dev/xvdx`, but Nitro presents NVMe; AL2023's `ec2-utils` udev rules may or may not create a backwards-compatible `/dev/xvd*` symlink |

### Ansible probes (run from the Mac)
After basic SSH probes pass, add the test instance to a temporary inventory and try:
1. `ansible -i <test-inventory> testhost -m ping` — does ansible's connection plugin work cleanly on AL2023?
2. `ansible -i <test-inventory> testhost -m dnf -a "name=cowsay state=absent"` — does the `dnf:` module work?
3. `ansible -i <test-inventory> testhost -m package -a "name=jq state=present"` — does the generic `package:` module pick `dnf` correctly?

### Expected outcomes (informs Plan 2)
| Outcome | Plan 2 implication |
|---|---|
| All probes pass, `dnf:` module works | Plan 2 can replace `shell: yum` with `dnf:` module — cleaner playbooks, also remove the `when: false` dead code |
| `dnf:` module fails but shell-`dnf` works | Plan 2 keeps `shell:` wrapper, just renames `yum`→`dnf` and updates package names |
| Any package missing in core repos | Plan 2 needs to source it elsewhere (Fedora EPEL with caveats, build from source, drop the feature) |
| `xt_recent` not loadable | Plan 2 needs to migrate `/ec2str/ipt.rules` to nftables or use a different rate-limiting approach |
| `/dev/xvdx` symlink missing on AL2023+Nitro | Plan 2 must rewrite `config.mainServer.yml:58` to target `/dev/sdx` (if udev creates it) or `/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_vol-<id>` (always stable) before the cipher will open |
| openssl3 ABI break for custom Postfix | Plan 2 includes a Postfix rebuild step against AL2023 |

### Findings (executed 2026-06-06, AL2023 instance i-0208a5155a0879c27)

| # | Probe | Result |
|---|---|---|
| 1 | Boot mode | **UEFI** ✓ (`/boot/efi` present; t3.micro) |
| 2 | Kernel | **6.1.166** ✓ |
| 3 | Python | **3.9.25** at `/usr/bin/python3` ✓ (matches `hosts.yml:17`) |
| 4 | Package manager | **dnf 4.14**; `yum` is a symlink → `dnf-3` ✓ |
| 5 | OpenSSL | **3.5.5** (newer than the assumed 3.0) → AL2 Postfix tarball (OpenSSL 1.1) won't link |
| 6 | SELinux | enabled (ext4 mounted with `seclabel`); **not disruptive** — all services started under default policy |
| 7 | iptables backend | **not re-tested this run** (`/ec2str/ipt.rules` not yet re-applied) — residual |
| 8 | xt_recent | **not re-tested this run** — residual (verify when ipt.rules is re-applied) |
| 9 | netstat | `state.mainServer.yml:15` still calls `netstat` — **TODO: switch to `ss`** (net-tools not default on AL2023) |
| 10 | cryptsetup | **2.6.1** ✓ |
| 11 | Required pkgs | **ALL in core `amazonlinux` repo** ✓ — bind 9.18.33, httpd/mod_ssl 2.4.66, squid 6.13, openssl-devel 3.5.5, certbot 2.6.0, python3-certbot-apache, perl-Mail-SPF 2.9.0, perl-Mail-DKIM, perl-Sys-Syslog, mailx 12.5, rsyslog 8.2204 |
| 12 | EPEL needed? | **No** — every package is in core; `amazon-linux-extras` line removed |
| 13 | EBS device naming | `/dev/xvdx` **compat symlink EXISTS** on Nitro → `nvme1n1`; stable by-id path also present (`/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_<volid-no-hyphen>`) |
| A1 | ansible connection | **OK** over IPv6 SSH (Gathering Facts ok) ✓ |
| A2 | `dnf:` module | **works** (Python 3.9 dnf bindings load) ✓ — replaced all `shell: yum` |

**Critical cryptsetup finding (corrects the Plan 2 assumption below):** the data volume is **plain dm-crypt, not LUKS**. The `create` → `open --type plain` switch is *not* a free drop-in: plain dm-crypt has no header, so cipher/hash/key-size must match the original `create`. Empirically, AL2 `create` and AL2023 `open --type plain` share the same plain-mode defaults — **cipher `aes-cbc-essiv:sha256`, hash `ripemd160`, key-size 256** (cipher/key-size confirmed via `dmsetup table`) — so the data decrypts correctly. These are now **pinned explicitly** in the playbook so a future cryptsetup default change can't break access.

---

## Plan 2: migration — EXECUTED & VALIDATED (2026-06-06)

Done in-place via step-by-step tagged runs of `config.mainServer.yml`; all 9 phases green, all 5 services (`httpd`, `rsyslog`, `squid`, `postfix`, `named`) active and listening (:80/:443, local, :3128, :25, :53) on a live AL2023 spot.

Changes landed (committed):
- **`config.mainServer.yml`** — `shell: yum` → native `dnf:` module (deleted the `when:false` dead block); `openssl11-devel`→`openssl-devel`; `python2-`→`python3-certbot-apache`; added `rsyslog`; `mailx` kept (in core); removed `amazon-linux-extras epel`; Postfix tarball → native `dnf postfix` (3.7.2, OpenSSL 3.x); cryptsetup `create /dev/xvdx` → `open --type plain` with **explicit** `--cipher aes-cbc-essiv:sha256 --key-size 256 --hash ripemd160` on the **by-id** path; added `pre_tasks: include_vars vars.yml` (needed so `ec2str` renders the by-id path); `ignore_errors` on stop-postfix; `no_log: true` on the cipher task; `stop` tag → `stp`.
- **`launch.spec.json`** — AMI → AL2023 `ami-098e39bafa7e7303d`; added `IamInstanceProfile: SSMInstanceRole`; t3.micro.
- **`vars.yml`** — `msi` tracks the live instance in the working tree only (committed only once terminated; see mode's Instance-ID commit policy).

Two bugs hit & fixed during validation:
1. **`ec2str` undefined** — `config.mainServer.yml` never loaded `vars.yml`; fixed with `include_vars` (the by-id path needs the var). The original literal `/dev/xvdx` had no var dependency, so this only surfaced after the by-id change.
2. **Passphrase mismatch** on one attempt — masked initially by `no_log: true`; once visible, a wrong `-e` value was the cause (the params were fine).

Residual / not-done:
- `state.mainServer.yml:15` still uses `netstat` → switch to `ss` (probe 9).
- `ipt.rules` / `xt_recent` (probes 7, 8) not re-validated — verify when firewall rules are re-applied.
- Defensive **snapshot** of the data volume before cutover — recommended but not taken (this validation reused the real volume directly).
- SELinux left at default (enforcing/seclabel) — non-disruptive, no labeling work needed so far.
- DNS: `dns.yml` (Route53 `AAAA`) is **obsolete** post-Spaceship migration — remove/rewrite separately.

---

## Future enhancements (not migration-blocking)

- **Persist SSH host keys across relaunches.** ✅ **IMPLEMENTED.** Root volume is ephemeral, so `/etc/ssh/ssh_host_*` are regenerated every spot launch → `known_hosts` churn / "REMOTE HOST IDENTIFICATION HAS CHANGED" (ENI/EIP/IPv6 are stable, host identity was not). The current keys are seeded **once** on the encrypted volume at `/ec2str/ssh/`, and the `hostkeys`-tagged block in `config.mainServer.yml` (last in the play, post-`ec2str` mount) copies them into `/etc/ssh` — sshd's **default** `HostKey` paths, so **no `sshd_config` change** — then `restorecon`s to `sshd_key_t`, validates `sshd -t`, and restarts sshd only if changed. Perms: **`640 root:ssh_keys` private / `644 root:root` public** (NOT `600` — sshd privsep reads the key as group `ssh_keys`). `block`/`rescue` so a missing mount can never abort the play or lock SSH out (SSM is the backstop). One-time `known_hosts` prime needed on the ansible control Mac for the 3 names (EIP / IPv6 / alireza.me); already-connected clients are unaffected since the *current* keys were persisted. Keys are ecdsa + ed25519 only (AL2023 mints no rsa host key at boot). Irreducible caveat: brief boot→bootstrap window where sshd answers on throwaway keys until the task runs.
