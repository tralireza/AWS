# nftables firewall — `/ec2str/firewall.nft` (AL2023)

Packet-traversal schematic of the live `inet fw` input chain (first match wins; fall-through hits `policy accept`). Native nft port of the former AL2 `iptables` + `xt_recent` rules, with **per-source per-port rate limits + a shared cross-port ban**.

> **Security:** the management `/64` is redacted (`<mgmt-IPv6-/64>`); the full ruleset (76 blocklist CIDRs, literal values) lives **only** on `/ec2str/firewall.nft` (encrypted volume) — intentionally **not** committed to this repo.

```
      INBOUND  →  table inet fw · chain input        (policy: ACCEPT)       
                                     │                                      
╔══════════════════════════════════════════════════════════════════════════╗
║ ① TRUST                    →  ACCEPT & stop                              ║
╟──────────────────────────────────────────────────────────────────────────╢
║ ct state established,related          → ACCEPT  (live SSH ok)            ║
║ iif lo                                → ACCEPT                           ║
║ ip  saddr 127.0.0.1                   → ACCEPT                           ║
║ ip  saddr 172.16.0.0/12   (VPC)       → ACCEPT                           ║
║ ip6 saddr <mgmt-IPv6-/64> (admin)     → ACCEPT                           ║
║ tcp dport 25  SES senders             → ACCEPT  ◄ bypasses below         ║
╚══════════════════════════════════════════════════════════════════════════╝
                                     │                                         (not trusted)
╔══════════════════════════════════════════════════════════════════════════╗
║ ② STATIC BLOCKLIST         →  DROP & stop                                ║
╟──────────────────────────────────────────────────────────────────────────╢
║ ip  saddr @bl4   (76 CIDRs)           → DROP                             ║
║ ip6 saddr @bl6   (2 CIDRs)            → DROP                             ║
╚══════════════════════════════════════════════════════════════════════════╝
                                     │                                         (not blocklisted)
╔══════════════════════════════════════════════════════════════════════════╗
║ ③ CROSS-PORT BAN GATE      →  DROP & stop                                ║
╟──────────────────────────────────────────────────────────────────────────╢
║ ip  saddr @v4_block                   → DROP                             ║
║ ip6 saddr @v6_block                   → DROP   (tripped a limiter; 12h)  ║
╚══════════════════════════════════════════════════════════════════════════╝
                                     │                                         (not banned; NEW conns only below)
╔══════════════════════════════════════════════════════════════════════════╗
║ ④ PER-PORT LIMITERS    (over rate → add @block + DROP)                   ║
╟──────────────────────────────────────────────────────────────────────────╢
║ 25  SMTP   over 13/hour  burst 13     → +ban  LOG DROP   v4+v6           ║
║ 22  SSH    over 11/hour  burst 11     → +ban  DROP       v4+v6           ║
║            over 7/hour   burst 13     → +ban  DROP       v4+v6           ║
║ 80  HTTP   over 124/hour burst 31     → +ban  DROP       v4              ║
║ 443 HTTPS  over 92/hour  burst 23     → +ban  DROP       v4              ║
║ any trip → 12h ban on ALL ports via @block ──► caught at ③               ║
╚══════════════════════════════════════════════════════════════════════════╝
                                     │                                      
╔══════════════════════════════════════════════════════════════════════════╗
║ ⑤ COUNTERS                 (tally NEW conns, no verdict)                 ║
╟──────────────────────────────────────────────────────────────────────────╢
║ tcp 25/22/80/443/53 ct state new counter   ·   udp 53 counter            ║
╚══════════════════════════════════════════════════════════════════════════╝
                                     │                                      
╔══════════════════════════════════════════════════════════════════════════╗
║ ⑥ EXPLICIT v6 SERVICE ALLOW                                              ║
╟──────────────────────────────────────────────────────────────────────────╢
║ ip6 tcp dport {22,25,53,80,443} accept                                   ║
║ ip6 udp dport 53 accept                                                  ║
╚══════════════════════════════════════════════════════════════════════════╝
                                     │                                      
               policy ACCEPT  →  ACCEPT   (allow-by-default)                
```

## Cross-port ban (the key behaviour)

Each port has its **own** per-source rate detector. When a source trips **any** detector, the limiter rule does `add @v4_block { ip saddr }` (or `@v6_block`) **and** drops — so the source is then caught at stage ③ and dropped on **every** port for **12h**.

```
e.g. 9.9.9.9 opens >124 new HTTP conns/h  →  trips v4_http  →  add @v4_block  →  drop
     next packet from 9.9.9.9 to SSH/SMTP/…  →  ip saddr @v4_block drop   (12h)
```

## Supporting objects

```
static sets    : bl4 (76 ipv4 CIDRs, flags interval) · bl6 (2 ipv6 CIDRs, interval)
ban sets       : v4_block · v6_block    type addr · flags dynamic,timeout · timeout 12h
detectors (×8) : v4_smtp v4_ssh_1h v4_ssh_2h v4_http v4_https · v6_smtp v6_ssh_1h v6_ssh_2h
                 type addr · size 2048 · flags dynamic,timeout · timeout 1h/2h/15m
```

## Notes

- **Order is the policy** — trust (① incl. SES) → blocklist → ban → limiters. The mgmt `/64` and SES senders are accepted before any limiter, so they can never be banned.
- **Cross-port** — tripping one port's rate bans the source on all ports (shared `@v{4,6}_block`, 12h).
- **Stateful** — ① accepts established; stages ③-⑥ only ever see `ct state new`.
- **Allow-by-default** — no terminal `drop`; `policy accept` passes whatever survives.
- **`v4_ssh_2h` = 7/hour** (≈ the old 6.5/hour = 13-per-2h, rounded up), burst 13.
- Load `nft -f /ec2str/firewall.nft` · validate `nft -c -f` · inspect ban `nft list set inet fw v4_block`.

