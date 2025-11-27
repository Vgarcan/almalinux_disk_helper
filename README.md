
# XEMI Disk Helper (v3.0)

Interactive Bash helper to manage disks on Linux servers  
(tested on AlmaLinux, but works on any distro with the required tools).

> Typical use case: prepare and mount an external disk for persistent
> storage (for example, `/srv/cloud_data` for a Django project).

---

## Table of contents

- [Features](#features)
- [How it works](#how-it-works)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
  - [Main menu](#main-menu)
  - [Option 1 – List available disks](#option-1--list-available-disks)
  - [Option 2 – Mount a device](#option-2--mount-a-device)
  - [Option 3 – Unmount a device](#option-3--unmount-a-device)
  - [Option 4 – Change device label](#option-4--change-device-label)
  - [Option 5 – Format a device](#option-5--format-a-device-dangerous)
- [Automatic `/etc/fstab` entry](#automatic-etcfstab-entry)
- [Quick ext4 format helper](#quick-ext4-format-helper)
- [Typical workflow for a server (example with Django)](#typical-workflow-for-a-server-example-with-django)
- [Logs](#logs)
- [Safety notes](#safety-notes)
- [License](#license)

---

## Features

XEMI Disk Helper provides an interactive TUI in the terminal:

- Detects and lists **all partitions** with:
  - name, size, filesystem, label, mountpoint, status
  - highlights system disk and root (`/`) partition for safety
- **Mounts** a partition to a chosen path:
  - predefined options (`/mnt`, `/media`, `/run/media/$USER`)
  - custom mountpoint
- Can **create a filesystem** before mounting:
  - Detects if there is no filesystem
  - Detects **NTFS** and explains why it is not ideal on Linux servers
  - Offers to convert it to `ext4`
- **Generates persistent `/etc/fstab` entries**:
  - Uses `UUID`, not `/dev/sdX`
  - Creates automatic backup of `fstab`
  - Tests the new entry with `mount -a` and restores backup if it fails
- **Unmounts** devices safely (never touches system disk)
- **Changes partition labels** (`ext4`, `vfat`, `ntfs` if tools exist)
- **Formats partitions** as:
  - `ext4` (recommended for Linux servers)
  - `vfat` (FAT32)
  - `ntfs` (if tools are installed)
- All actions are logged in a simple text log

---

## How it works

The script is a single Bash file that wraps common CLI tools:

- `lsblk`, `blkid`, `findmnt` for disk information
- `mount`, `umount` for mounting
- `mkfs.ext4`, `mkfs.vfat`, `mkfs.ntfs` for formatting
- `e2label`, `fatlabel`, `ntfslabel` for label changes

It adds:

- safety checks (never formats or mounts partitions from the system disk)
- interactive confirmations
- automatic `/etc/fstab` line generation
- a log file for traceability

---

## Requirements

Required commands (the script checks and can auto-install them):

- `lsblk`
- `mount`, `umount`
- `sudo`
- `mkfs.ext4`, `mkfs.vfat`
- `e2label`, `fatlabel`
- `blkid`
- `findmnt`

Optional commands (only needed for full NTFS support):

- `mkfs.ntfs`
- `ntfslabel`

Supported package managers:

- `apt`
- `dnf`
- `pacman`
- `zypper`

---

## Installation

Clone the repository and make the script executable:

```bash
git clone https://github.com/Vgarcan/almalinux_disk_helper.git
cd almalinux_disk_helper

chmod +x xemi_disk_helper.sh  # or the name you use
````

Run it from the terminal:

```bash
./xemi_disk_helper.sh
```

> You do **not** have to run the script as root directly.
> It uses `sudo` when needed (mount, format, fstab).

---

## Usage

### Main menu

When you run the script you will see something like:

```text
=== XEMI Disk Helper ===
Disk management tool for Linux servers.
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
```

You can always go back to the main menu by pressing ENTER when asked.

---

### Option 1 – List available disks

Shows a table of **all partitions** (`TYPE = part`) with:

* `NAME` (e.g. `sdb1`)
* `SIZE`
* `FSTYPE`
* `LABEL`
* `MOUNTPOINT`
* `STATUS`:

  * `[ROOT PARTITION]` → where `/` is mounted
  * `[SYSTEM DISK]` → same physical disk as the OS
  * `Mounted` or `Not Mounted`

This is the safest way to check which partition you want to use
before formatting or mounting anything.

---

### Option 2 – Mount a device

Guides you through mounting a partition, for example `sdb1`.

Steps:

1. Shows the same table as in option 1
2. Asks for the partition name (e.g. `sdb1`)
3. Validates that:

   * it exists
   * it is a **partition**, not a whole disk
   * it is **not** on the system disk
4. Detects filesystem (`FSTYPE`):

   * **no filesystem** → offers to create `ext4`
   * **NTFS** → explains limitations and offers:

     * reformat to `ext4` (recommended on servers)
     * try to mount NTFS
     * cancel
5. Asks for the mountpoint:

   * `/mnt/<dev>`
   * `/media/<dev>`
   * `/run/media/$USER/<dev>`
   * custom path
6. Creates the directory if needed and runs `mount`
7. After a successful mount, optionally offers to create a
   **persistent `/etc/fstab` entry** (see below)

If the mount fails because of filesystem issues, it can offer a quick ext4 format
and re-try the mount on the same mountpoint.

---

### Option 3 – Unmount a device

Shows all partitions that are currently mounted under:

* `/mnt`
* `/media`
* `/run/media`

Then:

1. Asks for the partition name (e.g. `sdb1`)
2. Refuses to unmount anything on the system disk
3. Asks for confirmation
4. Runs `sudo umount /dev/<dev>`

Useful when you want to safely disconnect a disk or change its filesystem.

---

### Option 4 – Change device label

Lets you change the **label** of a partition.

Flow:

1. Shows partitions table (similar to option 1)
2. Asks for a device (`sdb1`)
3. Refuses to act on system disk partitions
4. Detects filesystem and uses:

   * `e2label` for `ext2/3/4`
   * `fatlabel` for `vfat/fat32`
   * `ntfslabel` for `ntfs` (if installed)
5. Asks for new label (no spaces) and applies it

---

### Option 5 – Format a device (DANGEROUS)

Full manual formatter with extra confirmations.

Steps:

1. Shows partitions table
2. Asks for target partition (e.g. `sdb1`)
3. Verifies that it exists and is not part of the system disk
4. Double confirmation:

   * type `yes`
   * type `FORMAT`
5. Choose filesystem:

   * `ext4` (recommended)
   * `vfat`
   * `ntfs` (only if `mkfs.ntfs` exists)
6. Optional label
7. Runs the corresponding `mkfs.*` command

> This **erases all data** on the selected partition.
> Use it only if you are 100 % sure.

---

## Automatic `/etc/fstab` entry

When a mount succeeds, the script can generate a persistent entry in `/etc/fstab`.

What it does:

1. Gets `UUID` with `blkid`

2. Detects filesystem (`FSTYPE`) with `lsblk`

3. Builds a line:

   ```text
   UUID=<uuid>  <mountpoint>  <fstype>  defaults  0  0
   ```

4. Shows the line and asks for confirmation

5. Creates a timestamped backup:

   ```bash
   /etc/fstab.backup-YYYYMMDD-HHMMSS
   ```

6. Appends the line to `/etc/fstab` if there is no existing entry for
   that UUID or mountpoint

7. Runs `mount -a` to test the whole `fstab`:

   * if success → keeps the new file
   * if failure → restores the backup and shows the error

This makes it easy to have disks that re-mount automatically after reboot.

---

## Quick ext4 format helper

During **mount** or when the script detects:

* no filesystem
* NTFS where ext4 is preferred

you may see the *quick ext4* helper:

* Asks to type `ext4` to confirm
* Optional label
* Runs `mkfs.ext4` (with or without `-L`)
* Logs the action

This is useful when you plug in a Windows disk and want to convert it
quickly to a native Linux filesystem before using it for something like
database or Django media storage.

---

## Typical workflow for a server (example with Django)

Example scenario (like the author uses):

> Attach an external disk and use it for `MEDIA_ROOT` in a Django project.

1. Plug the disk and run the script:

   ```bash
   ./xemi_disk_helper.sh
   ```

2. Use **Option 1** to identify the partition, e.g. `sdb1`

3. Use **Option 2**:

   * Select `sdb1`
   * If NTFS or empty → quick format to `ext4`
   * Choose mountpoint, e.g. `/srv/cloud_data`
   * Accept to create `/etc/fstab` entry

4. Create a folder for your project media:

   ```bash
   sudo mkdir -p /srv/cloud_data/myproject_media
   sudo chown -R myuser:mygroup /srv/cloud_data/myproject_media
   sudo chmod -R 775 /srv/cloud_data/myproject_media
   ```

5. In `settings.py` of the Django project:

   ```python
   MEDIA_URL = '/media/'
   MEDIA_ROOT = '/srv/cloud_data/myproject_media'
   ```

6. From now on, any `FileField`/`ImageField` will store files
   in the external disk, mounted at `/srv/cloud_data`.

---

## Logs

All actions are logged to:

```text
~/.xemi_logs/disk_manager.log
```

Each entry includes:

* timestamp
* user
* a short description, for example:

```text
[2025-11-27 23:40:01] USER=baker | Mounted /dev/sdb1 at /srv/cloud_data
[2025-11-27 23:41:10] USER=baker | Added fstab entry for /dev/sdb1 at /srv/cloud_data
```

Useful when you need to remember what was done on a given server.

---

## Safety notes

* The script **never** formats or relabels partitions on the system disk
  (`/` and its siblings) by design.
* For other disks, all destructive operations require explicit confirmation.
* Always double-check the target device (`sdb1`, `sdc1`, …) in the table
  before formatting or mounting.
* Keep the `/etc/fstab` backups created by the script, especially on production servers.

---

## License

MIT License – feel free to use, modify and adapt it for your own servers and workflows.

Contributions and suggestions are welcome.


