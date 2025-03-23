# Setup Notes

This is a massive work-in-progress.

## Hardware

Minimum recommended - two SSDs:
1. Boot Drive (min 128GB, recommend 256GB or 512GB)
2. Data Drive (recommend 2TB+, depends on use case)

If it's a NAS:
1. Boot Drive (min 128GB, recommend 256GB or 512GB)
    - NVMe recommended, so it's in a different IOMMU group to the SATA controller
    - relevant if you're virtualising a NAS OS, e.g. TrueNAS or Unraid
2. 2-4 large HDDs (in my case, 4x16TB)
3. OPTIONAL: Cache Drive (in my case, 4TB NVMe SSD)

## Base OS - Proxmox

Download the latest version of Proxmox Virtual Environment (PVE):

* [Proxmox - Downloads](https://www.proxmox.com/en/downloads)

Create a bootable USB flash drive using a tool such as:

* [Rufus](https://rufus.ie/en/) (Windows)
* [Balena Etcher](https://etcher.balena.io/) (macOS, Linux, Windows)
* [Ventoy](https://www.ventoy.net/en/download.html) (macOS, Windows)

Install Proxmox.

### Post-Install

Remove the Enteprise repositories, and replace them with the "Non-subscription"
repositories.

There are three files to edit.

-   File 1: `nano /etc/apt/sources.list.d/pve-enterprise.list`
    -   Comment out the following line:
    -   `#deb https://enterprise.proxmox.com/debian/pve bookworm pve-enterprise`
-   File 2: `nano /etc/apt/sources.list`
    -   Add the following line:
    -   `deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription`
-   File 3: `nano /etc/apt/sources.list.d/ceph.list`
    -   Comment out the following line:
    -   `#deb https://enterprise.proxmox.com/debian/ceph-quincy bookworm enterprise`
    -   Add the following line:
    -   `deb http://download.proxmox.com/debian/ceph-squid bookworm no-subscription`

Then:

```bash
# Fetch info for the newly enabled repositories
apt update

# Upgrade all installed packages
apt upgrade
```

Useful packages that don't come pre-installed:

```bash
apt install fish
apt install git
apt install screen
apt install tmux
```

### Download ISOs:

-   Datacentre > proxmox > local > ISO Storage > Download from URL
-   Paste the URL
-   Verify integrity
    -   Tick advanced
    -   Paste the SHA-x checksum from the source website, and select the correct algorithm

Some useful ISOs to have on hand (as of March 2025):

-   [Ubuntu Server 24.04.2 LTS](https://releases.ubuntu.com/24.04.2/ubuntu-24.04.2-live-server-amd64.iso),
    [Checksum](https://releases.ubuntu.com/24.04.2/SHA256SUMS)
-   [Debian 12.10.0](https://cdimage.debian.org/debian-cd/current/amd64/iso-dvd/),
    [Checksum](https://cdimage.debian.org/debian-cd/current/amd64/iso-dvd/SHA256SUMS)
-   [NixOS 24.11](https://channels.nixos.org/nixos-24.11/latest-nixos-gnome-x86_64-linux.iso),
    [Checksum](https://channels.nixos.org/nixos-24.11/latest-nixos-gnome-x86_64-linux.iso.sha256)
-   [TrueNAS Scale 24.10.2](https://download.sys.truenas.net/TrueNAS-SCALE-ElectricEel/24.10.2/TrueNAS-SCALE-24.10.2.iso),
    [Checksum](https://download.sys.truenas.net/TrueNAS-SCALE-ElectricEel/24.10.2/TrueNAS-SCALE-24.10.2.iso.sha256)
-   [Kali Linux](https://www.kali.org/get-kali/#kali-installer-images)

## HDD Burn-In

```bash
git clone https://github.com/Spearfoot/disk-burnin-and-testing.git ~/code/public/disk-burnin-and-testing

tmux new-session -s drives
mkdir ~/disk_logs
cd ~/disk_logs
~/code/public/disk-burnin-and-testing/disk-burnin.sh /dev/sda  # Replace with the device you want to test
```

This script does a full `badblocks` plus a SMART long test, and then writes
everything neatly to a log file.

Each pass of `badblocks` writes to every sector on the disk, and then reads back
each sector (to confirm that it wrote correctly). Each run uses a different
pattern of bytes.

This takes a LONG FRICKING TIME on large drives - BEWARE.

On a 16TB drive (rated ~250MB/sec), **it took more than a week**:

* SMART short test - 2 minutes
* `badblocks` four passes - 7 days, 4 hours (avg 216MiB/sec)
* SMART long test - 32 hours
= 8 days, 12 hours total

## Power Management

### BIOS

tl;dr version:

- Disable XMP
- Enable anything to do with CPU C-States
- Enable anything to do with PCIe ASPM
- Disable anything not needed (HD audio, excess USB, etc)

#### Motherboard Specifics - ASRock B760M Pro-A Wifi

This is **every** change I made in the BIOS (not just power management-related).

**Key:** = Default -> **Selected** _(Available Options)_

- OC Tweaker
    - CPU Configuration
        - Boot Performance Mode      = Turbo Performance -> **Max Battery**
        - OPTIONAL: reduce PL1 (long) and PL2 (short) power limits
    - DRAM Configuration
        - Disable XMP (run at stock JDEC) for lower voltage
- Advanced
    - CPU Configuration
        - CPU C States Support       = Disabled -> **Enabled** _(Disabled / Enabled)_
        - Enhanced Halt State (C1E)  = Auto     -> **Enabled** _(Auto / Disabled / Enabled)_
        - CPU C6 State Support       = Auto     -> **Enabled** _(Auto / Disabled / Enabled)_
        - CPU C7 State Support       = Auto     -> **Enabled** _(Auto / Disabled / Enabled)_
        - Package C State Support    = Auto     -> **Enabled** _(Auto / Disabled / Enabled)_
    - Chipset Configuration
        - PCI Express Native Control = Disabled -> **Enabled** _(Disabled / Enabled)_
        - PCIE ASPM Support          = Disabled -> **L0sL1**   _(Disabled / L0s / L1 / L0sL1)_
        - PCH PCIE ASPM Support      = Disabled -> **L1**      _(Disabled / L1 / auto)_
        - DMI ASPM Support           = Disabled -> **Enabled** _(Disabled / Enabled)_
        - PCH DMI ASPM Support       = Disabled -> **Enabled** _(Disabled / Enabled)_
        - IGPU Multi-Monitor         = Disabled -> **Enabled** _(Disabled / Enabled)_
        - Onboard HD Audio           = Enabled -> **Disabled** _(Disabled / Enabled)_
        - Onboard WAN Device         = Enabled -> **Disabled** _(Disabled / Enabled)_
    - ACPI Configuration
        - RTC Alarm Power On         = By OS -> **Disabled**   _(Disabled / Enabled / By OS)_
    - UEFI Configuration
        - UEFI Setup Style           = Easy Mode -> **Advanced Mode** _(Easy / Advanced)_
- Tool
    - ASRock Polychrome RGB
        - Set Style = **OFF**, tick apply to all
    - Auto Driver Installer          = Enabled -> **Disabled** _(Disabled / Enabled)_
- Boot
    - Setup Prompt Timeout           = 1 -> **3**
    - Boot Beep                      = Enabled -> **Disabled** _(Disabled / Enabled)_

### Host OS (Proxmox)

```bash
apt install linux-cpupower
apt install powertop

# Check the current scaling governor used (for each core)
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Set the scaling governor
cpupower frequency-set -g powersave  # Does not persist between reboots!

# Enable all available power-saving tweaks
powertop --auto-tune  # Does not persist between reboots!

# ASPM - Notthebee (Wolfgang's Channel)'s script
git clone https://github.com/notthebee/AutoASPM ~/code/public/AutoASPM
python3 ~/code/public/AutoASPM/autoaspm.py  # Does not persist between reboots!
```

## VM - TrueNAS Scale

-   **Start/Shutdown Order:** `1` - start first, so the network shares are available when other VMs boot
-   **System > Machine**: `q35` - modern option, better for PCIe passthrough
-   **System > BIOS**: `SeaBios` - UEFI bootloader does not play nicely with TrueNAS Scale install ISO
-   **Disks**: 32GB, enable SSD emulation. Data disks passed through separately as PCIe devices
-   **vCPUs**: `2 cores` - don't need many, since this VM is dedicated purely to storage (no containers etc)
-   **Memory**: `32768 MiB` - half the total system RAM. ZFS rule of thumb is 1GB per 1TB usable storage

TODO: Set up hugepages

### PCIe Passthrough

Determining which PCIe devices to pass through for storage drives:

```bash
# List all storage block devices on Proxmox
lsblk

# List the PCIe device associated with storage 
readlink -f /sys/block/nvme*n1/device  # NVMe devices (nvme0n1, nvme1n1, ...)
readlink -f /sys/block/sd*/device      # SATA devices (sda, sdb, ...)

# List the PCIe devices themselves
lspci
```

In my case, I wanted to pass through:

-   the NVMe controller for `nvme1n1`, which corresponded to PCIe `2:00.0)
-   the whole SATA controller (for all four of `sda`/`sdb`/`sdc`/`sdd`),
    which corresponded to PCIe `00:17.0`)

Therefore, after finishing the VM creation wizard, add two PCI devices to the VM:

-   Raw device -> 0000:02:00.0 (tick PCI Express, leave ROM BAR ticked)
-   Raw device -> 0000:00:17.0 (tick PCI Express, leave ROM BAR ticked)

