# Homelab

Configuration and personal documentation for my homelab - (eternal) WIP

<img src="./docs/img/patrick.jpg" width=511>

**Figure 1:** _Me trying to assemble this monstrosity_

## Tech Stack

-   **pfSense CE** - firewall sitting in front of all this (bare metal)
-   **Proxmox VE** - host OS (bare metal)
-   **Ubuntu Server** (22.04 LTS) - guest OS, hosts portainer
    -   TODO: move to NixOS for this layer
    -   **Docker + Docker Compose** - most services in containers
        -   **Portainer** - nice web GUI for docker stuff
        -   **Jellyfin** - media server
        -   **Jellyseerr** - automate requesting content
        -   **Servarr Suite** - automate ([legally!](#disclaimer)) obtaining various media files

## Todo

In no particular order:

- [x] Auto provision TLS certificates via Caddy
- [x] Close off container ports (i.e. web UIs only accessible via Caddy)
- [x] Expose containers to Tailnet. ✅ Single Tailscale instance for whole cluster (~~ports~~ **subdomains** for different services) ~~or one per service (allows subdomains)~~
- [x] Gluetun in containers (currently done at pfsense layer)
- [x] Figure out something for NAS layer
- [x] PCIe passthrough iGPU from Proxmox Host -> Ubuntu -> Jellyfin container, for transcoding
- [ ] Move to NixOS instead of Ubuntu
- [x] Add more RAM to host PC
- [ ] Set up auto offsite backups
- [ ] Automate deployment from scratch (Ansible? Nix?)
- [x] Add automated speed test tool (for periodically testing WAN speed through ISP)
- [x] Add self-hosted web-based speed test (for testing a client device's connection speed to the homelab, e.g. via Tailscale)
- [ ] Add Unifi network controller (for configuring local wifi access points, etc)
- [ ] Set up PiHole for DNS
- [x] Set up Watchtower for auto-updating non-critical containers
- [ ] Put Portainer in docker compose (rather than as a raw docker run command)

_**Note:** ~~I don't have a domain name and don't (currently) plan to purchase one, which adds some additional hoops to jump through (e.g. provisioning valid TLS certificates becomes slightly more difficult than just Caddy + Let's Encrypt)_~~ Ended up getting a domain after all

## Disclaimer

This was created as a learning exercise to upskill on various technologies, and is/has/will be only ever used for legally permissible purposes, such as obtaining media released to the public domain or sharing Linux ISOs.
