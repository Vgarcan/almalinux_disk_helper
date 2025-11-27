#!/bin/bash

# ==============================
# XEMI DISK HELPER - v1.1 (Pi-ready)
# ==============================

# === CONFIGURATION (edit here) ===
LOG_DIR="$HOME/.xemi_logs"
LOG_FILE="$LOG_DIR/disk_manager.log"
DATE_FORMAT="+%Y-%m-%d %H:%M:%S"
MOUNT_OPTIONS="defaults"
USE_COLORS=true
# ================================

# === Colours ===
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
CYAN=$(tput setaf 6)
RESET=$(tput sgr0)

# === Dependency Check with Auto-Install ===
# - REQUIRED_CMDS: script will NOT run without these.
# - OPTIONAL_CMDS: only used for NTFS support; if missing, we just warn.

check_dependencies() {
    local MISSING=()
    local REQUIRED_CMDS=(lsblk mount umount sudo mkfs.ext4 mkfs.vfat e2label fatlabel blkid findmnt)
    local OPTIONAL_CMDS=(mkfs.ntfs ntfslabel)

    # Check required commands
    for cmd in "${REQUIRED_CMDS[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            MISSING+=("$cmd")
        fi
    done

    # If all required are present, just warn about optional and exit
    if (( ${#MISSING[@]} == 0 )); then
        # Optional NTFS tools
        for cmd in "${OPTIONAL_CMDS[@]}"; do
            if ! command -v "$cmd" &>/dev/null; then
                echo -e "${YELLOW}Note:${RESET} Optional command '$cmd' is not installed. NTFS support will be limited."
            fi
        done
        return 0
    fi

    echo -e "${YELLOW}Missing required commands:${RESET} ${MISSING[*]}"
    echo ""

    # Try to detect the package manager
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
        echo -e "${RED}Unsupported system. Please install the following manually:${RESET} ${MISSING[*]}"
        exit 1
    fi

    echo "This script can attempt to install the missing tools using your system package manager: $PM"
    read -rp "Would you like to proceed with installation? (y/n): " answer

    if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
        echo "You chose not to install the missing tools. Script will now exit."
        exit 1
    fi

    echo -e "${CYAN}Installing missing tools...${RESET}"
    sleep 1

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

    # Re-check after installation
    for cmd in "${MISSING[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            echo -e "${RED}Command '$cmd' could not be installed automatically.${RESET}"
            echo "Please install it manually and re-run this script."
            exit 1
        fi
    done

    echo -e "${GREEN}All required tools are now installed.${RESET}"

    # Optional NTFS tools
    for cmd in "${OPTIONAL_CMDS[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            echo -e "${YELLOW}Note:${RESET} Optional command '$cmd' is not installed. NTFS support will be limited."
        fi
    done
}

# === log_action ===
log_action() {
    local timestamp
    local user
    local message

    timestamp=$(date "$DATE_FORMAT")
    user=$USER
    message="$1"

    mkdir -p "$LOG_DIR"
    echo "[$timestamp] USER=$user | $message" >> "$LOG_FILE"
}

# === print_header ===
print_header() {
    clear
    sleep 0.65
    local timestamp
    timestamp=$(date "$DATE_FORMAT")

    echo -e "${CYAN}=== XEMI Disk Helper ===${RESET}"
    echo "Disk management tool for Linux users."
    echo "----------------------------------------"
    echo "User: $USER"
    echo "Time: $timestamp"
    echo "----------------------------------------"
    echo ""
}

# === pause ===
pause() {
    echo ""
    read -rp "Press ENTER to return to the main menu..."
    echo ""
}

# === Core Functions ===

list_disks() {
    print_header
    echo -e "${YELLOW}Available partitions for mount or management:${RESET}"
    echo ""

    local ROOT_PART
    ROOT_PART=$(findmnt / -o SOURCE -n)
    local SYSTEM_DISK
    SYSTEM_DISK=$(lsblk -no PKNAME "$ROOT_PART")

    echo -e "${CYAN}LEGEND:${RESET}"
    echo "- ${GREEN}Mounted${RESET} partitions are currently in use."
    echo "- ${RED}[SYSTEM DISK]${RESET} means the partition is on the same physical disk as your system (/)."
    echo "- ${RED}[ROOT PARTITION]${RESET} is the partition where your OS is running."
    echo ""

    printf "${CYAN}%-12s %-8s %-8s %-12s %-22s %-20s${RESET}\n" \
        "NAME" "SIZE" "FSTYPE" "LABEL" "MOUNTPOINT" "STATUS"
    printf "%s\n" "-------------------------------------------------------------------------------"

    while IFS= read -r part_name; do
        full_path="/dev/$part_name"

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

is_valid_partition() {
    lsblk -lno NAME,TYPE | awk '$1 == "'"$1"'" && $2 == "part"' | grep -q .
}

mount_device() {
    print_header
    echo -e "${YELLOW}Mount a Device${RESET}"
    echo ""
    echo "Select a partition to mount. Do not choose entries like 'sda' or 'sdb' (whole disks)."
    echo ""

    ROOT_PART=$(findmnt / -o SOURCE -n)
    SYSTEM_DISK=$(lsblk -no PKNAME "$ROOT_PART")

    echo -e "${CYAN}LEGEND:${RESET}"
    echo "- ${GREEN}Mounted${RESET} = already in use."
    echo "- ${RED}[SYSTEM DISK]${RESET} = on the same disk as the system."
    echo "- ${RED}[ROOT PARTITION]${RESET} = the system root (/)."
    echo ""

    printf "${CYAN}%-12s %-8s %-8s %-12s %-22s %-20s${RESET}\n" \
        "NAME" "SIZE" "FSTYPE" "LABEL" "MOUNTPOINT" "STATUS"
    printf "%s\n" "-------------------------------------------------------------------------------"

    while IFS= read -r part_name; do
        full_path="/dev/$part_name"
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
        echo -e "${YELLOW}Operation cancelled by user.${RESET}"
        pause
        return
    fi

    DEVICE="/dev/$dev"

    if ! is_valid_partition "$dev"; then
        echo -e "${RED}Invalid device. Must be an existing partition.${RESET}"
        pause
        return
    fi

    PART_DISK=$(lsblk -no PKNAME "$DEVICE")
    if [[ "$PART_DISK" == "$SYSTEM_DISK" ]]; then
        echo -e "${RED}⚠️ For safety, you cannot mount partitions from the system disk (${SYSTEM_DISK}).${RESET}"
        pause
        return
    fi

    echo ""
    echo "Choose a mount location:"
    echo "1) /mnt/$dev                -> For admin use (temporary)"
    echo "2) /media/$dev              -> For external media (desktop use)"
    echo "3) /run/media/$USER/$dev    -> Auto-mount (modern desktops)"
    echo "4) Custom                   -> Enter your own folder"
    echo "5) Anywhere                 -> No validation"
    read -rp "Option [1-5]: " mount_choice

    case "$mount_choice" in
        1) MOUNT_POINT="/mnt/$dev" ;;
        2) MOUNT_POINT="/media/$dev" ;;
        3) MOUNT_POINT="/run/media/$USER/$dev" ;;
        4) read -rp "Enter custom mount path: " MOUNT_POINT ;;
        5) read -rp "Enter full mount path (no checks): " MOUNT_POINT ;;
        *) echo "Invalid. Defaulting to /mnt/$dev"; MOUNT_POINT="/mnt/$dev" ;;
    esac

    echo ""
    echo "Creating mount point if needed..."
    sudo mkdir -p "$MOUNT_POINT"

    echo "Mounting device..."
    if sudo mount -o "$MOUNT_OPTIONS" "$DEVICE" "$MOUNT_POINT"; then
        echo -e "${GREEN}✅ Mounted at $MOUNT_POINT${RESET}"
        log_action "Mounted $DEVICE at $MOUNT_POINT"
    else
        echo -e "${RED}❌ Failed to mount $DEVICE${RESET}"
    fi

    pause
}

unmount_device() {
    print_header
    echo -e "${YELLOW}Unmount a Device${RESET}"
    echo ""
    echo "Below are the currently mounted partitions in /mnt, /media, or /run/media:"
    echo ""

    ROOT_PART=$(findmnt / -o SOURCE -n)
    SYSTEM_DISK=$(lsblk -no PKNAME "$ROOT_PART")

    printf "${CYAN}%-12s %-8s %-22s %-20s${RESET}\n" "NAME" "SIZE" "MOUNTPOINT" "STATUS"
    printf "%s\n" "---------------------------------------------------------------"

    while IFS= read -r line; do
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
    echo "To cancel, press ENTER without typing anything or type 'c' and press ENTER."
    read -rp "Enter the device name to unmount (e.g., sdb1): " dev
    dev=$(echo "$dev" | xargs)

    if [[ -z "$dev" || "$dev" == "c" || "$dev" == "cancel" ]]; then
        echo -e "${YELLOW}Operation cancelled by user.${RESET}"
        pause
        return
    fi

    DEVICE="/dev/$dev"

    if ! mount | grep -q "$DEVICE"; then
        echo -e "${RED}The device $DEVICE is not currently mounted.${RESET}"
        pause
        return
    fi

    PART_DISK=$(lsblk -no PKNAME "$DEVICE")
    if [[ "$PART_DISK" == "$SYSTEM_DISK" ]]; then
        echo -e "${RED}⚠️ WARNING:${RESET} $DEVICE belongs to the system disk (${SYSTEM_DISK})."
        echo -e "${RED}For safety reasons, you cannot unmount system partitions using this tool.${RESET}"
        pause
        return
    fi

    echo ""
    read -rp "Are you sure you want to unmount $DEVICE? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Operation cancelled."
        pause
        return
    fi

    echo "Unmounting device..."
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
    echo -e "${YELLOW}Change Device Label${RESET}"
    echo ""

    ROOT_PART=$(findmnt / -o SOURCE -n)
    SYSTEM_DISK=$(lsblk -no PKNAME "$ROOT_PART")

    echo -e "${CYAN}NOTE:${RESET}"
    echo "- ${GREEN}Mounted${RESET} = currently in use."
    echo "- ${RED}[SYSTEM DISK]${RESET} = same physical disk as the OS."
    echo "- ${RED}[ROOT PARTITION]${RESET} = the partition where / is mounted."
    echo ""

    printf "${CYAN}%-12s %-8s %-8s %-12s %-22s %-20s${RESET}\n" \
        "NAME" "SIZE" "FSTYPE" "LABEL" "MOUNTPOINT" "STATUS"
    printf "%s\n" "-------------------------------------------------------------------------------"

    while IFS= read -r part_name; do
        full_path="/dev/$part_name"
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
        echo -e "${YELLOW}Operation cancelled by user.${RESET}"
        pause
        return
    fi

    DEVICE="/dev/$dev"

    if ! lsblk -no NAME,TYPE | grep -q "^$dev part$"; then
        echo -e "${RED}Invalid or non-existent partition.${RESET}"
        pause
        return
    fi

    PART_DISK=$(lsblk -no PKNAME "$DEVICE")
    if [[ "$PART_DISK" == "$SYSTEM_DISK" ]]; then
        echo -e "${RED}❌ For safety reasons, you cannot relabel partitions from the system disk (${SYSTEM_DISK}).${RESET}"
        pause
        return
    fi

    FSTYPE=$(lsblk -no FSTYPE "$DEVICE")
    echo -e "${CYAN}Detected filesystem: $FSTYPE${RESET}"

    if mount | grep -q "$DEVICE"; then
        echo -e "${YELLOW}WARNING:${RESET} The device appears to be mounted."
        read -rp "Do you still want to continue? (not recommended) (y/n): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo "Operation cancelled."
            pause
            return
        fi
    fi

    echo ""
    read -rp "Enter new label (no spaces or special characters): " newlabel

    echo "Changing label..."
    case "$FSTYPE" in
        ext2|ext3|ext4)
            sudo e2label "$DEVICE" "$newlabel"
            ;;
        vfat|fat32)
            sudo fatlabel "$DEVICE" "$newlabel"
            ;;
        ntfs)
            if command -v ntfslabel &>/dev/null; then
                sudo ntfslabel "$DEVICE" "$newlabel"
            else
                echo -e "${RED}ntfslabel is not installed. Cannot change NTFS label.${RESET}"
                pause
                return
            fi
            ;;
        *)
            echo -e "${RED}❌ Unsupported filesystem: $FSTYPE${RESET}"
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
    echo -e "${RED}⚠️ WARNING:${RESET} This will permanently ERASE ALL DATA on the selected device!"
    echo "Only use this if you're absolutely sure."
    echo ""

    ROOT_PART=$(findmnt / -o SOURCE -n)
    SYSTEM_DISK=$(lsblk -no PKNAME "$ROOT_PART")

    echo -e "${CYAN}NOTE:${RESET}"
    echo "- ${GREEN}Mounted${RESET} = currently in use."
    echo "- ${RED}[SYSTEM DISK]${RESET} = on same disk as system (${SYSTEM_DISK})."
    echo "- ${RED}[ROOT PARTITION]${RESET} = where your OS is running (/)."
    echo ""

    printf "${CYAN}%-12s %-8s %-8s %-12s %-22s %-20s${RESET}\n" \
        "NAME" "SIZE" "FSTYPE" "LABEL" "MOUNTPOINT" "STATUS"
    printf "%s\n" "-------------------------------------------------------------------------------"

    while IFS= read -r part_name; do
        full_path="/dev/$part_name"
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
        echo -e "${YELLOW}Operation cancelled by user.${RESET}"
        pause
        return
    fi

    DEVICE="/dev/$dev"

    if ! lsblk -no NAME,TYPE | grep -q "^$dev part$"; then
        echo -e "${RED}Invalid or non-existent partition.${RESET}"
        pause
        return
    fi

    PART_DISK=$(lsblk -no PKNAME "$DEVICE")
    if [[ "$PART_DISK" == "$SYSTEM_DISK" ]]; then
        echo -e "${RED}⚠️ DANGER:${RESET} $DEVICE belongs to the system disk (${SYSTEM_DISK})."
        echo -e "${RED}You are not allowed to format system partitions using this tool.${RESET}"
        pause
        return
    fi

    echo ""
    echo -e "${YELLOW}Are you sure you want to format $DEVICE?${RESET}"
    read -rp "Type 'yes' to continue: " confirm1
    if [[ "$confirm1" != "yes" ]]; then
        echo "Operation cancelled."
        pause
        return
    fi

    read -rp "Type 'FORMAT' in ALL CAPS to confirm: " confirm2
    if [[ "$confirm2" != "FORMAT" ]]; then
        echo "Operation cancelled."
        pause
        return
    fi

    echo ""
    echo "Choose filesystem type:"
    echo "1) ext4  - Linux systems"
    echo "2) vfat  - FAT32 (USB drives, cross-platform)"

    local NTFS_AVAILABLE=false
    if command -v mkfs.ntfs &>/dev/null; then
        NTFS_AVAILABLE=true
        echo "3) ntfs  - Windows-compatible"
    fi

    read -rp "Option [1-3]: " fs_opt

    case "$fs_opt" in
        1) FSTYPE="ext4" ;;
        2) FSTYPE="vfat" ;;
        3)
            if [[ "$NTFS_AVAILABLE" == true ]]; then
                FSTYPE="ntfs"
            else
                echo -e "${RED}mkfs.ntfs is not installed. Cannot format as NTFS.${RESET}"
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

    read -rp "Do you want to assign a label? (y/n): " label_opt
    if [[ "$label_opt" =~ ^[yY]$ ]]; then
        read -rp "Enter label (no spaces or special characters): " newlabel
    else
        newlabel=""
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

main_menu() {
    check_dependencies

    while true; do
        print_header

        echo "Select an option from the list below:"
        echo ""
        echo " 1) List available disks         - View connected partitions and their status"
        echo " 2) Mount a device               - Mount a specific partition to a directory"
        echo " 3) Unmount a device             - Safely unmount a previously mounted device"
        echo " 4) Change device label          - Rename a partition label (ext4, FAT32, NTFS)"
        echo " 5) Format a device              - Format a partition (DANGEROUS!)"
        echo " 6) Exit                         - Quit the program"
        echo "----------------------------------------"

        read -rp "Choose an option [1-6]: " choice

        case "$choice" in
            1) list_disks ;;
            2) mount_device ;;
            3) unmount_device ;;
            4) change_label ;;
            5) format_device ;;
            6)
                echo -e "${CYAN}Thank you for using XEMI Disk Helper. Goodbye!${RESET}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option. Please choose a number from 1 to 6.${RESET}"
                sleep 1
                ;;
        esac
    done
}

# === Entry Point ===
main_menu
