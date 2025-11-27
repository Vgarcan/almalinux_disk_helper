#!/bin/bash

# ==============================
# XEMI DISK HELPER - v3.0
# ==============================
# Helper interactivo para gestionar discos en Linux:
# - Ver particiones
# - Montar y desmontar
# - Cambiar etiquetas
# - Formatear
# - Crear entrada segura en /etc/fstab
#
# Pensado para servidores (por ejemplo, un disco de "cloud" para Django).
# ==============================

# === CONFIGURACIÓN BÁSICA ===
LOG_DIR="$HOME/.xemi_logs"
LOG_FILE="$LOG_DIR/disk_manager.log"
DATE_FORMAT="+%Y-%m-%d %H:%M:%S"
MOUNT_OPTIONS="defaults"
USE_COLORS=true

# === COLORES ===
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
CYAN=$(tput setaf 6)
RESET=$(tput sgr0)

# =========================================================
# 1. Dependencias
# =========================================================
check_dependencies() {
    local MISSING=()
    # Herramientas obligatorias para que el script funcione
    local REQUIRED_CMDS=(lsblk mount umount sudo mkfs.ext4 mkfs.vfat e2label fatlabel blkid findmnt)
    # Herramientas opcionales (solo para NTFS, no son críticas)
    local OPTIONAL_CMDS=(mkfs.ntfs ntfslabel)

    for cmd in "${REQUIRED_CMDS[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            MISSING+=("$cmd")
        fi
    done

    if (( ${#MISSING[@]} > 0 )); then
        echo -e "${YELLOW}Missing required commands:${RESET} ${MISSING[*]}"
        echo ""

        local PM=""
        if command -v apt &>/dev/null; then
            PM="apt"
        elif command -v dnf &>/dev/null; then
            PM="dnf"
        elif command -v pacman &>/dev/null; then
            PM="pacman"
        elif command -v zypper &>/dev/null; then
            PM="zypper"
        else
            echo -e "${RED}Unsupported system. Please install manually:${RESET} ${MISSING[*]}"
            exit 1
        fi

        echo "This script can attempt to install the missing tools using: $PM"
        read -rp "Proceed with installation? (y/n): " answer
        if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
            echo "Aborting, missing required tools."
            exit 1
        fi

        echo -e "${CYAN}Installing missing tools...${RESET}"
        case "$PM" in
            apt)
                sudo apt update
                sudo apt install -y "${MISSING[@]}"
                ;;
            dnf)
                sudo dnf install -y "${MISSING[@]}"
                ;;
            pacman)
                sudo pacman -Sy --noconfirm "${MISSING[@]}"
                ;;
            zypper)
                sudo zypper install -y "${MISSING[@]}"
                ;;
        esac

        for cmd in "${MISSING[@]}"; do
            if ! command -v "$cmd" &>/dev/null; then
                echo -e "${RED}Command '$cmd' could not be installed automatically.${RESET}"
                exit 1
            fi
        done

        echo -e "${GREEN}All required tools are now installed.${RESET}"
    fi

    # Aviso simplemente informativo para NTFS
    for cmd in "${OPTIONAL_CMDS[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            echo -e "${YELLOW}Note:${RESET} Optional command '$cmd' is not installed. NTFS support will be limited."
        fi
    done
}

# =========================================================
# 2. Utilidades generales (log, UI)
# =========================================================
log_action() {
    local timestamp user message
    timestamp=$(date "$DATE_FORMAT")
    user=$USER
    message="$1"

    mkdir -p "$LOG_DIR"
    echo "[$timestamp] USER=$user | $message" >> "$LOG_FILE"
}

print_header() {
    clear
    sleep 0.3
    local timestamp
    timestamp=$(date "$DATE_FORMAT")

    echo -e "${CYAN}=== XEMI Disk Helper ===${RESET}"
    echo "Disk management tool for Linux servers."
    echo "----------------------------------------"
    echo "User: $USER"
    echo "Time: $timestamp"
    echo "----------------------------------------"
    echo ""
}

pause() {
    echo ""
    read -rp "Press ENTER to return to the main menu..."
    echo ""
}

# =========================================================
# 3. Helpers de discos
# =========================================================
is_valid_partition() {
    # Comprueba que el nombre dado es una partición (tipo "part")
    lsblk -lno NAME,TYPE | awk '$1 == "'"$1"'" && $2 == "part"' | grep -q .
}

quick_format_ext4() {
    # Formateo rápido a ext4, pensado precisamente para "arreglar" un disco
    # antes de usarlo de forma estable en Linux/Django.
    local DEVICE="$1"

    echo ""
    echo -e "${RED}⚠️ You are about to FORMAT ${DEVICE} to ext4.${RESET}"
    echo "This will ERASE ALL DATA on that partition."
    echo "This is recommended when the disk comes from Windows (NTFS)"
    echo "and you want to use it permanently on a Linux server."
    echo ""
    read -rp "Type 'ext4' to confirm format, anything else to cancel: " confirm
    if [[ "$confirm" != "ext4" ]]; then
        echo -e "${YELLOW}Quick format cancelled.${RESET}"
        return 1
    fi

    read -rp "Optional label (no spaces, e.g. CLOUD_DATA) or leave empty: " label

    echo ""
    echo -e "${CYAN}Formatting ${DEVICE} as ext4...${RESET}"
    if [[ -n "$label" ]]; then
        sudo mkfs.ext4 -L "$label" "$DEVICE"
        log_action "Quick formatted $DEVICE as ext4 (label: $label)"
    else
        sudo mkfs.ext4 "$DEVICE"
        log_action "Quick formatted $DEVICE as ext4 (no label)"
    fi

    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✅ Format completed. ${DEVICE} is now ext4.${RESET}"
        return 0
    else
        echo -e "${RED}❌ Format failed.${RESET}"
        return 1
    fi
}

generate_fstab_entry() {
    # Crea una entrada en /etc/fstab con:
    # - UUID
    # - Backup automático
    # - Validación con mount -a
    local DEVICE="$1"
    local MOUNT_POINT="$2"

    local UUID FSTYPE
    UUID=$(blkid -s UUID -o value "$DEVICE")
    FSTYPE=$(lsblk -no FSTYPE "$DEVICE")

    if [[ -z "$UUID" ]]; then
        echo -e "${RED}Error: No UUID found for ${DEVICE}.${RESET}"
        return 1
    fi
    [[ -z "$FSTYPE" ]] && FSTYPE="auto"

    local ENTRY="UUID=${UUID}  ${MOUNT_POINT}  ${FSTYPE}  ${MOUNT_OPTIONS}  0  0"

    echo ""
    echo -e "${CYAN}Proposed /etc/fstab entry:${RESET}"
    echo "$ENTRY"
    echo ""

    read -rp "Add this entry automatically to /etc/fstab? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${YELLOW}fstab not modified.${RESET}"
        return 0
    fi

    local BACKUP="/etc/fstab.backup-$(date +%Y%m%d-%H%M%S)"
    echo -e "${CYAN}Backing up /etc/fstab to ${BACKUP}${RESET}"
    sudo cp /etc/fstab "$BACKUP"

    if grep -q "$UUID" /etc/fstab || grep -q " $MOUNT_POINT " /etc/fstab; then
        echo -e "${YELLOW}An entry with this UUID or mountpoint already exists. Skipping.${RESET}"
        return 0
    fi

    echo "$ENTRY" | sudo tee -a /etc/fstab > /dev/null
    echo -e "${GREEN}✅ Entry added to /etc/fstab${RESET}"
    log_action "Added fstab entry for $DEVICE at $MOUNT_POINT"

    echo -e "${CYAN}Testing 'mount -a' to validate fstab...${RESET}"
    if sudo mount -a 2>/tmp/fstab_test_err; then
        echo -e "${GREEN}✅ fstab validation successful.${RESET}"
    else
        echo -e "${RED}❌ mount -a failed! Restoring backup.${RESET}"
        sudo mv "$BACKUP" /etc/fstab
        echo -e "${YELLOW}Error details:${RESET}"
        cat /tmp/fstab_test_err
    fi
}

# =========================================================
# 4. Funciones principales
# =========================================================
list_disks() {
    print_header
    echo -e "${YELLOW}Available partitions:${RESET}"
    echo ""

    local ROOT_PART SYSTEM_DISK
    ROOT_PART=$(findmnt / -o SOURCE -n)
    SYSTEM_DISK=$(lsblk -no PKNAME "$ROOT_PART")

    echo -e "${CYAN}LEGEND:${RESET}"
    echo "- ${GREEN}Mounted${RESET} = currently in use."
    echo "- ${RED}[SYSTEM DISK]${RESET} = same physical disk as your OS."
    echo "- ${RED}[ROOT PARTITION]${RESET} = partition where / is mounted."
    echo ""

    printf "${CYAN}%-12s %-8s %-8s %-12s %-22s %-20s${RESET}\n" \
        "NAME" "SIZE" "FSTYPE" "LABEL" "MOUNTPOINT" "STATUS"
    printf "%s\n" "-------------------------------------------------------------------------------"

    while IFS= read -r part_name; do
        local full_path="/dev/$part_name"
        local size fstype label mountpoint parent_disk status

        size=$(lsblk -no SIZE "$full_path")
        fstype=$(lsblk -no FSTYPE "$full_path")
        label=$(lsblk -no LABEL "$full_path")
        mountpoint=$(lsblk -no MOUNTPOINT "$full_path")
        parent_disk=$(lsblk -no PKNAME "$full_path" 2>/dev/null)

        if [[ "$full_path" == "$ROOT_PART" ]]; then
            status="${RED}[ROOT PARTITION]${RESET}"
        elif [[ "$parent_disk" == "$SYSTEM_DISK" ]]; then
            status="${RED}[SYSTEM DISK]${RESET}"
        elif [[ -n "$mountpoint" ]]; then
            status="${GREEN}Mounted${RESET}"
        else
            status="${YELLOW}Not Mounted${RESET}"
        fi

        printf "%-12s %-8s %-8s %-12s %-22s %-20s\n" \
            "$part_name" "$size" "$fstype" "$label" "$mountpoint" "$status"

    done < <(lsblk -ln -o NAME,TYPE | awk '$2 == "part" {print $1}')

    echo ""
    pause
}

mount_device() {
    print_header
    echo -e "${YELLOW}Mount a device${RESET}"
    echo ""
    echo "Do not choose whole disks like 'sda' or 'sdb'. Use partitions like 'sdb1'."
    echo ""

    local ROOT_PART SYSTEM_DISK
    ROOT_PART=$(findmnt / -o SOURCE -n)
    SYSTEM_DISK=$(lsblk -no PKNAME "$ROOT_PART")

    printf "${CYAN}%-12s %-8s %-8s %-12s %-22s %-20s${RESET}\n" \
        "NAME" "SIZE" "FSTYPE" "LABEL" "MOUNTPOINT" "STATUS"
    printf "%s\n" "-------------------------------------------------------------------------------"

    while IFS= read -r part_name; do
        local full_path="/dev/$part_name"
        local size fstype label mountpoint parent_disk status

        size=$(lsblk -no SIZE "$full_path")
        fstype=$(lsblk -no FSTYPE "$full_path")
        label=$(lsblk -no LABEL "$full_path")
        mountpoint=$(lsblk -no MOUNTPOINT "$full_path")
        parent_disk=$(lsblk -no PKNAME "$full_path" 2>/dev/null)

        if [[ "$full_path" == "$ROOT_PART" ]]; then
            status="${RED}[ROOT PARTITION]${RESET}"
        elif [[ "$parent_disk" == "$SYSTEM_DISK" ]]; then
            status="${RED}[SYSTEM DISK]${RESET}"
        elif [[ -n "$mountpoint" ]]; then
            status="${GREEN}Mounted${RESET}"
        else
            status="${YELLOW}Not Mounted${RESET}"
        fi

        printf "%-12s %-8s %-8s %-12s %-22s %-20s\n" \
            "$part_name" "$size" "$fstype" "$label" "$mountpoint" "$status"
    done < <(lsblk -ln -o NAME,TYPE | awk '$2 == "part" {print $1}')

    echo ""
    echo "To cancel, press ENTER or type 'c' and press ENTER."
    read -rp "Enter the device name to mount (e.g., sdb1): " dev
    dev=$(echo "$dev" | xargs)

    if [[ -z "$dev" || "$dev" == "c" || "$dev" == "cancel" ]]; then
        echo -e "${YELLOW}Operation cancelled.${RESET}"
        pause
        return
    fi

    if ! is_valid_partition "$dev"; then
        echo -e "${RED}Invalid or non-existent partition.${RESET}"
        pause
        return
    fi

    local DEVICE="/dev/$dev"
    local PART_DISK
    PART_DISK=$(lsblk -no PKNAME "$DEVICE")

    if [[ "$PART_DISK" == "$SYSTEM_DISK" ]]; then
        echo -e "${RED}For safety, you cannot mount partitions from the system disk (${SYSTEM_DISK}).${RESET}"
        pause
        return
    fi

    # --- Aquí comprobamos el tipo de filesystem y ofrecemos arreglarlo ---
    local FSTYPE
    FSTYPE=$(lsblk -no FSTYPE "$DEVICE")
    echo ""
    echo -e "${CYAN}Detected filesystem on ${DEVICE}: ${FSTYPE:-<none>}${RESET}"

    if [[ -z "$FSTYPE" ]]; then
        echo -e "${YELLOW}This partition does not seem to have a filesystem.${RESET}"
        echo "On Linux servers the typical choice is ext4."
        read -rp "Create an ext4 filesystem on ${DEVICE} now? (y/n): " ans
        if [[ "$ans" == "y" || "$ans" == "Y" ]]; then
            if ! quick_format_ext4 "$DEVICE"; then
                pause
                return
            fi
            FSTYPE="ext4"
        else
            echo -e "${YELLOW}No filesystem created. Cannot mount this partition yet.${RESET}"
            pause
            return
        fi
    elif [[ "$FSTYPE" == "ntfs" ]]; then
        echo ""
        echo -e "${YELLOW}NOTE:${RESET} This partition is NTFS (Windows style)."
        echo "On a Linux/Django server this is not ideal:"
        echo " - Needs ntfs-3g to work properly."
        echo " - Slower and less integrated than ext4."
        echo ""
        echo "What do you want to do?"
        echo " 1) Reformat to ext4 (recommended for server; data will be ERASED)."
        echo " 2) Try to mount NTFS as is."
        echo " 3) Cancel."
        read -rp "Option [1-3]: " opt_ntfs
        case "$opt_ntfs" in
            1)
                if ! quick_format_ext4 "$DEVICE"; then
                    pause
                    return
                fi
                FSTYPE="ext4"
                ;;
            2)
                echo -e "${YELLOW}Will try to mount NTFS. If ntfs-3g is missing, it may fail.${RESET}"
                ;;
            3)
                echo -e "${YELLOW}Operation cancelled.${RESET}"
                pause
                return
                ;;
            *)
                echo -e "${RED}Invalid option. Cancelling.${RESET}"
                pause
                return
                ;;
        esac
    fi

    echo ""
    echo "Choose a mount location:"
    echo "1) /mnt/$dev                -> Admin / server use"
    echo "2) /media/$dev              -> External / desktop style"
    echo "3) /run/media/$USER/$dev    -> Desktop auto-style"
    echo "4) Custom                   -> Enter your own folder"
    echo "5) Anywhere                 -> No validation"
    read -rp "Option [1-5]: " mount_choice

    local MOUNT_POINT
    case "$mount_choice" in
        1) MOUNT_POINT="/mnt/$dev" ;;
        2) MOUNT_POINT="/media/$dev" ;;
        3) MOUNT_POINT="/run/media/$USER/$dev" ;;
        4) read -rp "Enter custom mount path: " MOUNT_POINT ;;
        5) read -rp "Enter full mount path (no checks): " MOUNT_POINT ;;
        *) MOUNT_POINT="/mnt/$dev" ;;
    esac

    echo ""
    echo "Creating mount point if needed..."
    sudo mkdir -p "$MOUNT_POINT"

    echo "Mounting device..."
    if sudo mount -o "$MOUNT_OPTIONS" "$DEVICE" "$MOUNT_POINT"; then
        echo -e "${GREEN}✅ Mounted at $MOUNT_POINT${RESET}"
        log_action "Mounted $DEVICE at $MOUNT_POINT"

        echo ""
        read -rp "Add persistent /etc/fstab entry for this mount? (y/n): " ans_fstab
        if [[ "$ans_fstab" == "y" || "$ans_fstab" == "Y" ]]; then
            generate_fstab_entry "$DEVICE" "$MOUNT_POINT"
        fi
    else
        echo -e "${RED}❌ Failed to mount $DEVICE.${RESET}"
        echo ""
        echo "This often happens when the filesystem type is not supported."
        read -rp "Do you want to FORMAT this partition to ext4 and retry the mount? (y/n): " fix_ans
        if [[ "$fix_ans" == "y" || "$fix_ans" == "Y" ]]; then
            if quick_format_ext4 "$DEVICE"; then
                echo ""
                echo "Retrying mount on $MOUNT_POINT..."
                if sudo mount -o "$MOUNT_OPTIONS" "$DEVICE" "$MOUNT_POINT"; then
                    echo -e "${GREEN}✅ Mounted at $MOUNT_POINT after format.${RESET}"
                    log_action "Mounted $DEVICE at $MOUNT_POINT after fixing filesystem"

                    read -rp "Add persistent /etc/fstab entry for this mount? (y/n): " ans_fstab2
                    if [[ "$ans_fstab2" == "y" || "$ans_fstab2" == "Y" ]]; then
                        generate_fstab_entry "$DEVICE" "$MOUNT_POINT"
                    fi
                else
                    echo -e "${RED}Still failed to mount after formatting.${RESET}"
                fi
            fi
        fi
    fi

    pause
}

unmount_device() {
    print_header
    echo -e "${YELLOW}Unmount a device${RESET}"
    echo ""

    local ROOT_PART SYSTEM_DISK
    ROOT_PART=$(findmnt / -o SOURCE -n)
    SYSTEM_DISK=$(lsblk -no PKNAME "$ROOT_PART")

    printf "${CYAN}%-12s %-8s %-22s %-20s${RESET}\n" "NAME" "SIZE" "MOUNTPOINT" "STATUS"
    printf "%s\n" "---------------------------------------------------------------"

    while IFS= read -r line; do
        local part_name size mountpoint type full_path parent_disk status
        part_name=$(echo "$line" | awk '{print $1}')
        size=$(echo "$line" | awk '{print $2}')
        mountpoint=$(echo "$line" | awk '{print $3}')
        type=$(echo "$line" | awk '{print $4}')

        full_path="/dev/$part_name"
        parent_disk=$(lsblk -no PKNAME "$full_path" 2>/dev/null)

        if [[ "$mountpoint" =~ ^/mnt|^/media|^/run/media ]]; then
            if [[ "/dev/$part_name" == "$ROOT_PART" ]]; then
                status="${RED}[ROOT PARTITION]${RESET}"
            elif [[ "$parent_disk" == "$SYSTEM_DISK" ]]; then
                status="${RED}[SYSTEM DISK]${RESET}"
            else
                status="${GREEN}Mounted${RESET}"
            fi
            printf "%-12s %-8s %-22s %-20s\n" "$part_name" "$size" "$mountpoint" "$status"
        fi
    done < <(lsblk -ln -o NAME,SIZE,MOUNTPOINT,TYPE | grep "part")

    echo ""
    echo "To cancel, press ENTER or type 'c' and press ENTER."
    read -rp "Enter the device name to unmount (e.g., sdb1): " dev
    dev=$(echo "$dev" | xargs)

    if [[ -z "$dev" || "$dev" == "c" || "$dev" == "cancel" ]]; then
        echo -e "${YELLOW}Operation cancelled.${RESET}"
        pause
        return
    fi

    local DEVICE="/dev/$dev"
    if ! mount | grep -q "$DEVICE"; then
        echo -e "${RED}The device $DEVICE is not currently mounted.${RESET}"
        pause
        return
    fi

    local PART_DISK
    PART_DISK=$(lsblk -no PKNAME "$DEVICE")
    if [[ "$PART_DISK" == "$SYSTEM_DISK" ]]; then
        echo -e "${RED}Cannot unmount system disk partitions using this tool.${RESET}"
        pause
        return
    fi

    read -rp "Are you sure you want to unmount $DEVICE? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Operation cancelled."
        pause
        return
    fi

    echo "Unmounting..."
    if sudo umount "$DEVICE"; then
        echo -e "${GREEN}✅ Device $DEVICE unmounted.${RESET}"
        log_action "Unmounted $DEVICE"
    else
        echo -e "${RED}❌ Failed to unmount $DEVICE${RESET}"
    fi

    pause
}

change_label() {
    print_header
    echo -e "${YELLOW}Change device label${RESET}"
    echo ""

    local ROOT_PART SYSTEM_DISK
    ROOT_PART=$(findmnt / -o SOURCE -n)
    SYSTEM_DISK=$(lsblk -no PKNAME "$ROOT_PART")

    printf "${CYAN}%-12s %-8s %-8s %-12s %-22s %-20s${RESET}\n" \
        "NAME" "SIZE" "FSTYPE" "LABEL" "MOUNTPOINT" "STATUS"
    printf "%s\n" "-------------------------------------------------------------------------------"

    while IFS= read -r part_name; do
        local full_path="/dev/$part_name"
        local size fstype label mountpoint part_disk status

        size=$(lsblk -no SIZE "$full_path")
        fstype=$(lsblk -no FSTYPE "$full_path")
        label=$(lsblk -no LABEL "$full_path")
        mountpoint=$(lsblk -no MOUNTPOINT "$full_path")
        part_disk=$(lsblk -no PKNAME "$full_path" 2>/dev/null)

        if [[ "$full_path" == "$ROOT_PART" ]]; then
            status="${RED}[ROOT PARTITION]${RESET}"
        elif [[ "$part_disk" == "$SYSTEM_DISK" ]]; then
            status="${RED}[SYSTEM DISK]${RESET}"
        elif [[ -n "$mountpoint" ]]; then
            status="${GREEN}Mounted${RESET}"
        else
            status="${YELLOW}Not Mounted${RESET}"
        fi

        printf "%-12s %-8s %-8s %-12s %-22s %-20s\n" \
            "$part_name" "$size" "$fstype" "$label" "$mountpoint" "$status"
    done < <(lsblk -ln -o NAME,TYPE | awk '$2 == "part" {print $1}')

    echo ""
    echo "To cancel, press ENTER or type 'c' and press ENTER."
    read -rp "Enter the device name to relabel (e.g., sdb1): " dev
    dev=$(echo "$dev" | xargs)

    if [[ -z "$dev" || "$dev" == "c" || "$dev" == "cancel" ]]; then
        echo -e "${YELLOW}Operation cancelled.${RESET}"
        pause
        return
    fi

    if ! is_valid_partition "$dev"; then
        echo -e "${RED}Invalid or non-existent partition.${RESET}"
        pause
        return
    fi

    local DEVICE="/dev/$dev"
    local PART_DISK
    PART_DISK=$(lsblk -no PKNAME "$DEVICE")
    if [[ "$PART_DISK" == "$SYSTEM_DISK" ]]; then
        echo -e "${RED}Cannot relabel system disk partitions.${RESET}"
        pause
        return
    fi

    local FSTYPE
    FSTYPE=$(lsblk -no FSTYPE "$DEVICE")
    echo -e "${CYAN}Detected filesystem: ${FSTYPE}${RESET}"

    if mount | grep -q "$DEVICE"; then
        echo -e "${YELLOW}WARNING:${RESET} Device appears to be mounted."
        read -rp "Continue anyway? (not recommended) (y/n): " cont
        if [[ "$cont" != "y" && "$cont" != "Y" ]]; then
            echo "Operation cancelled."
            pause
            return
        fi
    fi

    read -rp "Enter new label (no spaces or special characters): " newlabel

    echo "Changing label..."
    case "$FSTYPE" in
        ext2|ext3|ext4) sudo e2label "$DEVICE" "$newlabel" ;;
        vfat|fat32)     sudo fatlabel "$DEVICE" "$newlabel" ;;
        ntfs)
            if command -v ntfslabel &>/dev/null; then
                sudo ntfslabel "$DEVICE" "$newlabel"
            else
                echo -e "${RED}ntfslabel not available. Cannot change NTFS label.${RESET}"
                pause
                return
            fi
            ;;
        *)
            echo -e "${RED}Unsupported filesystem: $FSTYPE${RESET}"
            pause
            return
            ;;
    esac

    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✅ Label successfully changed to: $newlabel${RESET}"
        log_action "Changed label of $DEVICE to $newlabel"
    else
        echo -e "${RED}❌ Failed to change label.${RESET}"
    fi

    pause
}

format_device() {
    print_header
    echo -e "${YELLOW}FORMAT A DEVICE${RESET}"
    echo ""
    echo -e "${RED}⚠️ WARNING:${RESET} This will ERASE ALL DATA on the selected device!"
    echo ""

    local ROOT_PART SYSTEM_DISK
    ROOT_PART=$(findmnt / -o SOURCE -n)
    SYSTEM_DISK=$(lsblk -no PKNAME "$ROOT_PART")

    printf "${CYAN}%-12s %-8s %-8s %-12s %-22s %-20s${RESET}\n" \
        "NAME" "SIZE" "FSTYPE" "LABEL" "MOUNTPOINT" "STATUS"
    printf "%s\n" "-------------------------------------------------------------------------------"

    while IFS= read -r part_name; do
        local full_path="/dev/$part_name"
        local size fstype label mountpoint part_disk status

        size=$(lsblk -no SIZE "$full_path")
        fstype=$(lsblk -no FSTYPE "$full_path")
        label=$(lsblk -no LABEL "$full_path")
        mountpoint=$(lsblk -no MOUNTPOINT "$full_path")
        part_disk=$(lsblk -no PKNAME "$full_path" 2>/dev/null)

        if [[ "$full_path" == "$ROOT_PART" ]]; then
            status="${RED}[ROOT PARTITION]${RESET}"
        elif [[ "$part_disk" == "$SYSTEM_DISK" ]]; then
            status="${RED}[SYSTEM DISK]${RESET}"
        elif [[ -n "$mountpoint" ]]; then
            status="${GREEN}Mounted${RESET}"
        else
            status="${YELLOW}Not Mounted${RESET}"
        fi

        printf "%-12s %-8s %-8s %-12s %-22s %-20s\n" \
            "$part_name" "$size" "$fstype" "$label" "$mountpoint" "$status"
    done < <(lsblk -ln -o NAME,TYPE | awk '$2 == "part" {print $1}')

    echo ""
    echo "To cancel, press ENTER or type 'c' and press ENTER."
    read -rp "Enter the partition to format (e.g., sdb1): " dev
    dev=$(echo "$dev" | xargs)

    if [[ -z "$dev" || "$dev" == "c" || "$dev" == "cancel" ]]; then
        echo -e "${YELLOW}Operation cancelled.${RESET}"
        pause
        return
    fi

    if ! is_valid_partition "$dev"; then
        echo -e "${RED}Invalid or non-existent partition.${RESET}"
        pause
        return
    fi

    local DEVICE="/dev/$dev"
    local PART_DISK
    PART_DISK=$(lsblk -no PKNAME "$DEVICE")
    if [[ "$PART_DISK" == "$SYSTEM_DISK" ]]; then
        echo -e "${RED}You are not allowed to format system disk partitions.${RESET}"
        pause
        return
    fi

    echo -e "${YELLOW}Are you sure you want to format $DEVICE?${RESET}"
    read -rp "Type 'yes' to continue: " c1
    if [[ "$c1" != "yes" ]]; then
        echo "Operation cancelled."
        pause
        return
    fi

    read -rp "Type 'FORMAT' in ALL CAPS to confirm: " c2
    if [[ "$c2" != "FORMAT" ]]; then
        echo "Operation cancelled."
        pause
        return
    fi

    echo ""
    echo "Choose filesystem type:"
    echo "1) ext4  - Linux servers (recommended)"
    echo "2) vfat  - FAT32 (USB, cross-platform)"
    local NTFS_AVAILABLE=false
    if command -v mkfs.ntfs &>/dev/null; then
        NTFS_AVAILABLE=true
        echo "3) ntfs  - Windows-friendly"
    fi

    read -rp "Option [1-3]: " fs_opt
    local FSTYPE
    case "$fs_opt" in
        1) FSTYPE="ext4" ;;
        2) FSTYPE="vfat" ;;
        3)
            if [[ "$NTFS_AVAILABLE" == true ]]; then
                FSTYPE="ntfs"
            else
                echo -e "${RED}NTFS tools not installed. Cannot format as NTFS.${RESET}"
                pause
                return
            fi
            ;;
        *)
            echo -e "${RED}Invalid filesystem option.${RESET}"
            pause
            return
            ;;
    esac

    read -rp "Assign a label? (y/n): " label_opt
    local newlabel=""
    if [[ "$label_opt" =~ ^[yY]$ ]]; then
        read -rp "Enter label (no spaces): " newlabel
    fi

    echo ""
    echo -e "${YELLOW}Formatting $DEVICE as $FSTYPE...${RESET}"
    sleep 1

    case "$FSTYPE" in
        ext4)
            [[ -n "$newlabel" ]] && sudo mkfs.ext4 -L "$newlabel" "$DEVICE" || sudo mkfs.ext4 "$DEVICE"
            ;;
        vfat)
            [[ -n "$newlabel" ]] && sudo mkfs.vfat -n "$newlabel" "$DEVICE" || sudo mkfs.vfat "$DEVICE"
            ;;
        ntfs)
            [[ -n "$newlabel" ]] && sudo mkfs.ntfs -f -L "$newlabel" "$DEVICE" || sudo mkfs.ntfs -f "$DEVICE"
            ;;
    esac

    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✅ Device formatted successfully.${RESET}"
        log_action "Formatted $DEVICE as $FSTYPE with label '$newlabel'"
    else
        echo -e "${RED}❌ Formatting failed.${RESET}"
    fi

    pause
}

# =========================================================
# 5. Menú principal
# =========================================================
main_menu() {
    check_dependencies

    while true; do
        print_header
        echo "Choose an option:"
        echo ""
        echo " 1) List available disks"
        echo " 2) Mount a device"
        echo " 3) Unmount a device"
        echo " 4) Change device label"
        echo " 5) Format a device (DANGEROUS)"
        echo " 6) Exit"
        echo "----------------------------------------"
        read -rp "Option [1-6]: " choice

        case "$choice" in
            1) list_disks ;;
            2) mount_device ;;
            3) unmount_device ;;
            4) change_label ;;
            5) format_device ;;
            6)
                echo -e "${CYAN}Thank you for using XEMI Disk Helper. Bye!${RESET}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option.${RESET}"
                sleep 1
                ;;
        esac
    done
}

# Punto de entrada
main_menu
