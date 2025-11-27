# XEMI Linux Disk Helper

**Interactive Bash utility for managing disks and partitions safely on any Linux system.**  
Supports **AlmaLinux**, **Debian**, **Ubuntu**, **Fedora**, **Raspberry Pi OS**, and others.

> 💡 Typical use: prepare and mount external storage for persistent data —  
> e.g. `/srv/cloud_data` for a Django project, or `/mnt/backup` for a home server.

---

## 📖 Table of Contents

- [About](#about)
- [Features](#features)
- [Preview](#preview)
- [How It Works](#how-it-works)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
  - [Main Menu](#main-menu)
  - [List Disks](#1-list-available-disks)
  - [Mount Disk](#2-mount-a-device)
  - [Unmount Disk](#3-unmount-a-device)
  - [Change Label](#4-change-device-label)
  - [Format Partition](#5-format-a-device-dangerous)
- [Automatic fstab Entry](#automatic-etcfstab-entry)
- [Quick ext4 Format Helper](#quick-ext4-format-helper)
- [Example Workflow: Django Server](#example-workflow-django-server)
- [Logs](#logs)
- [Safety Notes](#safety-notes)
- [License](#license)

---

## 🧩 About

**XEMI Linux Disk Helper** is a cross-distro shell tool for managing disks without manually typing dangerous commands.  
It guides you interactively through **mounting, unmounting, formatting, labeling, and fstab persistence** — all while protecting your system disk.

It’s designed for:
- sysadmins and developers who work with multiple servers
- Raspberry Pi and homelab setups
- quick deployment in web environments (e.g. Django media disks)

---

## ⚙️ Features

- 🔍 **Detects all partitions** (size, fs type, label, mountpoint, status)
- 🧱 **Mounts devices** safely to `/mnt`, `/media`, `/srv`, or custom paths
- 🧠 **Smart FS detection**:
  - Detects empty or NTFS drives
  - Suggests converting to `ext4`
- 📦 **Persistent mounts via `/etc/fstab`**
  - Uses `UUID` instead of `/dev/sdX`
  - Creates automatic `fstab` backups
- 🏷️ **Change partition labels** (`ext4`, `vfat`, `ntfs`)
- 🧹 **Format helper** (ext4, FAT32, NTFS)
- 🔐 **Prevents system/root disk modifications**
- 📝 **Action logs** (`~/.xemi_logs/disk_manager.log`)
- 🎨 **Colored TUI for clarity**

---

## 🖼️ Preview

Example menu:

```text
=== XEMI Linux Disk Helper ===
Disk management tool for Linux systems.
----------------------------------------
User: baker
Time: 2025-11-27 23:42:10
----------------------------------------

Choose an option:

 1) List available disks
 2) Mount a device
 3) Unmount a device
 4) Change device label
 5) Format a device (DANGEROUS)
 6) Exit
----------------------------------------
Option [1-6]:
````

---

## 🧠 How It Works

Internally uses standard Linux tools:

| Category   | Commands                                         |
| ---------- | ------------------------------------------------ |
| Disk info  | `lsblk`, `blkid`, `findmnt`                      |
| Mounting   | `mount`, `umount`, `sudo`                        |
| Filesystem | `mkfs.ext4`, `mkfs.vfat`, `mkfs.ntfs` (optional) |
| Labels     | `e2label`, `fatlabel`, `ntfslabel`               |

Adds logic for:

* system disk protection
* colorized prompts
* automatic `/etc/fstab` management
* consistent logging

---

## 🧰 Requirements

### Required tools

* `lsblk`
* `mount`, `umount`
* `sudo`
* `mkfs.ext4`, `mkfs.vfat`
* `e2label`, `fatlabel`
* `blkid`, `findmnt`

### Optional for NTFS

* `mkfs.ntfs`, `ntfslabel`
* package `ntfs-3g`

### Supported package managers

`apt`, `dnf`, `pacman`, `zypper`

---

## ⚡ Installation

Clone and make executable:

```bash
git clone https://github.com/Vgarcan/xemi_linux_disk_helper.git
cd xemi_linux_disk_helper
chmod +x xemi_linux_disk_helper.sh
```

Run directly:

```bash
./xemi_linux_disk_helper.sh
```

> 🚫 Do **not** run as root — the script uses `sudo` where needed.

---

## 🧭 Usage

### Main Menu

All actions are interactive and color-coded.

### 1️⃣ List Available Disks

Displays partition table including:

* size, filesystem, label, mount point
* highlights `[ROOT PARTITION]` and `[SYSTEM DISK]`

### 2️⃣ Mount a Device

Guided mount flow:

* Validates device (e.g. `sdb1`)
* Detects filesystem
* Offers conversion to `ext4` if NTFS
* Mounts to your chosen folder
* Optionally adds `/etc/fstab` entry for persistence

### 3️⃣ Unmount a Device

Lists current mounts in `/mnt`, `/media`, `/run/media`
Safely unmounts after confirmation.

### 4️⃣ Change Device Label

Rename a partition label interactively (without formatting).
Detects correct command based on FS type.

### 5️⃣ Format a Device (⚠️ Dangerous)

* Confirms twice before execution
* Supports: `ext4`, `vfat`, `ntfs`
* Allows custom label
* Prevents system disk formatting

---

## 🧩 Automatic `/etc/fstab` Entry

Automatically adds a persistent mount entry using UUIDs.

1. Creates a backup of `/etc/fstab`
2. Adds line:

   ```text
   UUID=<uuid>  <mountpoint>  <fstype>  defaults  0  0
   ```
3. Tests with `mount -a`
4. Restores backup if test fails

---

## ⚡ Quick ext4 Format Helper

Appears automatically when:

* partition has no filesystem, or
* NTFS detected on a server disk.

You can confirm to convert to `ext4` instantly.

---

## 🧱 Example Workflow: Django Server

```bash
./xemi_linux_disk_helper.sh
```

1️⃣ Identify external disk (e.g. `/dev/sdb1`)
2️⃣ Mount it to `/srv/cloud_data`
3️⃣ Accept adding to `/etc/fstab`
4️⃣ Prepare folder:

```bash
sudo mkdir -p /srv/cloud_data/myproject_media
sudo chown -R myuser:mygroup /srv/cloud_data/myproject_media
sudo chmod -R 775 /srv/cloud_data/myproject_media
```

5️⃣ In your `settings.py`:

```python
MEDIA_URL = '/media/'
MEDIA_ROOT = '/srv/cloud_data/myproject_media'
```

---

## 🧾 Logs

Logs are saved to:

```bash
~/.xemi_logs/disk_manager.log
```

Example:

```text
[2025-11-27 23:40:01] USER=baker | Mounted /dev/sdb1 at /srv/cloud_data
[2025-11-27 23:41:10] USER=baker | Added fstab entry for /dev/sdb1 at /srv/cloud_data
```

---

## 🔒 Safety Notes

* Never touches root or system disks
* Confirms before destructive actions
* Always backs up `/etc/fstab`
* Displays all mountpoints clearly before acting

---

## 🪪 License

**MIT License**
Use, modify, and redistribute freely.
Contributions, feedback, and pull requests are welcome!

---

## 👨‍💻 Author

**Victor Garcia (Vgarcan)**
🔗 [GitHub Profile](https://github.com/Vgarcan)
💬 Developer & RPA Business Analyst — passionate about automation and Linux infrastructure tools.
