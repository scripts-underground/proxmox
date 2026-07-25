#!/usr/bin/env bash
# shellcheck disable=SC2034
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: thost96 (thost96) | michelroegl-brunner | MickLesk
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Docker"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-10}"
VM_URL="${VM_URL:-https://cloud.debian.org/images/cloud/trixie/latest/debian-13-nocloud-amd64.qcow2}"
VM_OSTYPE="${VM_OSTYPE:-l26}"
VM_BIOS="${VM_BIOS:-ovmf}"
VM_MACHINE="${VM_MACHINE:-q35}"
VM_CPU="${VM_CPU:-host}"

function header_info {
  clear
  cat << "EOF"
     ____                   __
    / __ \____  ___________/ /_____  _____
   / / / / __ \/ ___/ ___/ //_/ _ \/ ___/
  / /_/ / /_/ / /__/ /__/ ,< /  __/ /
 /_____/\____/\___/\___/_/|_|\___/_/

EOF
}

function select_os() {
  if OS_CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "SELECT OS" --radiolist \
    "Choose Operating System for Docker VM" 14 68 4 \
    "debian13" "Debian 13 (Trixie) - Latest" ON \
    "debian12" "Debian 12 (Bookworm) - Stable" OFF \
    "ubuntu2404" "Ubuntu 24.04 LTS (Noble)" OFF \
    "ubuntu2204" "Ubuntu 22.04 LTS (Jammy)" OFF \
    3>&1 1>&2 2>&3); then
    case $OS_CHOICE in
      debian13)
        OS_TYPE="debian"
        OS_VERSION="13"
        OS_CODENAME="trixie"
        OS_DISPLAY="Debian 13 (Trixie)"
        ;;
      debian12)
        OS_TYPE="debian"
        OS_VERSION="12"
        OS_CODENAME="bookworm"
        OS_DISPLAY="Debian 12 (Bookworm)"
        ;;
      ubuntu2404)
        OS_TYPE="ubuntu"
        OS_VERSION="24.04"
        OS_CODENAME="noble"
        OS_DISPLAY="Ubuntu 24.04 LTS"
        ;;
      ubuntu2204)
        OS_TYPE="ubuntu"
        OS_VERSION="22.04"
        OS_CODENAME="jammy"
        OS_DISPLAY="Ubuntu 22.04 LTS"
        ;;
    esac
    echo -e "${OS}${BOLD}${DGN}Operating System: ${BGN}${OS_DISPLAY}${CL}"
  else
    exit_script
  fi
}

function select_cloud_init() {
  if [ "$OS_TYPE" = "ubuntu" ]; then
    USE_CLOUD_INIT="yes"
    echo -e "${CLOUD:-${TAB}☁️${TAB}${CL}}${BOLD}${DGN}Cloud-Init: ${BGN}yes (Ubuntu requires Cloud-Init)${CL}"
    return
  fi

  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "CLOUD-INIT" \
    --yesno "Enable Cloud-Init for VM configuration?\n\nCloud-Init allows automatic configuration of:\n- User accounts and passwords\n- SSH keys\n- Network settings (DHCP/Static)\n- DNS configuration\n\nYou can also configure these settings later in Proxmox UI.\n\nNote: Debian without Cloud-Init will use nocloud image with console auto-login." 18 68); then
    USE_CLOUD_INIT="yes"
    echo -e "${CLOUD:-${TAB}☁️${TAB}${CL}}${BOLD}${DGN}Cloud-Init: ${BGN}yes${CL}"
  else
    USE_CLOUD_INIT="no"
    echo -e "${CLOUD:-${TAB}☁️${TAB}${CL}}${BOLD}${DGN}Cloud-Init: ${BGN}no${CL}"
  fi
}

function get_image_url() {
  local arch
  arch=$(dpkg --print-architecture)
  case $OS_TYPE in
    debian)
      if [ "$USE_CLOUD_INIT" = "yes" ]; then
        echo "https://cloud.debian.org/images/cloud/${OS_CODENAME}/latest/debian-${OS_VERSION}-generic-${arch}.qcow2"
      else
        echo "https://cloud.debian.org/images/cloud/${OS_CODENAME}/latest/debian-${OS_VERSION}-nocloud-${arch}.qcow2"
      fi
      ;;
    ubuntu)
      echo "https://cloud-images.ubuntu.com/${OS_CODENAME}/current/${OS_CODENAME}-server-cloudimg-${arch}.img"
      ;;
  esac
}

function default_settings() {
  select_os
  select_cloud_init

  VM_VMID=$(get_valid_nextid)
  VM_DISK_FORMAT=""
  VM_MACHINE=" -machine q35"
  VM_DISK_CACHE=""
  VM_DISK_SIZE="${var_disk:-10}G"
  VM_HN="docker"
  VM_CPU=" -cpu host"
  VM_CORE_COUNT="${var_cpu:-2}"
  VM_RAM_SIZE="${var_ram:-4096}"
  VM_BRG="vmbr0"
  VM_MAC=""
  VM_VLAN=""
  VM_MTU=""
  VM_START="yes"

  echo -e "${CONTAINERID}${BOLD}${DGN}Virtual Machine ID: ${BGN}${VM_VMID}${CL}"
  echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}Q35 (Modern)${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}${VM_DISK_SIZE}${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${BGN}None${CL}"
  echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}${VM_HN}${CL}"
  echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}Host${CL}"
  echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}${VM_CORE_COUNT}${CL}"
  echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}${VM_RAM_SIZE}${CL}"
  echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}${VM_BRG}${CL}"
  echo -e "${MACADDRESS}${BOLD}${DGN}VM_MAC Address: ${BGN}Auto-generated${CL}"
  echo -e "${VLANTAG}${BOLD}${DGN}VM_VLAN: ${BGN}Default${CL}"
  echo -e "${DEFAULT}${BOLD}${DGN}Interface VM_MTU Size: ${BGN}Default${CL}"
  echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}yes${CL}"
  echo -e "${CREATING}${BOLD}${DGN}Creating a Docker VM using the above settings${CL}"
}

function advanced_settings() {
  select_os
  select_cloud_init

  [ -z "${VM_VMID:-}" ] && VM_VMID=$(get_valid_nextid)

  while true; do
    if VM_VMID=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Virtual Machine ID" 8 58 $VM_VMID --title "VIRTUAL VM_MACHINE ID" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [ -z "$VM_VMID" ]; then
        VM_VMID=$(get_valid_nextid)
      fi
      if pct status "$VM_VMID" &> /dev/null || qm status "$VM_VMID" &> /dev/null; then
        echo -e "${CROSS}${RD} ID $VM_VMID is already in use${CL}"
        sleep 2
        continue
      fi
      echo -e "${CONTAINERID}${BOLD}${DGN}Virtual Machine ID: ${BGN}$VM_VMID${CL}"
      break
    else
      exit_script
    fi
  done

  if MACH=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "VM_MACHINE TYPE" --radiolist --cancel-button Exit-Script "Choose Type" 10 58 2 \
    "q35" "Q35 (Modern, PCIe)" ON \
    "i440fx" "i440fx (Legacy, PCI)" OFF \
    3>&1 1>&2 2>&3); then
    if [ $MACH = q35 ]; then
      echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}Q35 (Modern)${CL}"
      VM_DISK_FORMAT=""
      VM_MACHINE=" -machine q35"
    else
      echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}i440fx (Legacy)${CL}"
      VM_DISK_FORMAT=",efitype=4m"
      VM_MACHINE=""
    fi
  else
    exit_script
  fi

  if VM_DISK_SIZE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Disk Size in GiB (e.g., 10, 20)" 8 58 "$VM_DISK_SIZE" --title "DISK SIZE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    VM_DISK_SIZE=$(echo "$VM_DISK_SIZE" | tr -d ' ')
    if [[ "$VM_DISK_SIZE" =~ ^[0-9]+$ ]]; then
      VM_DISK_SIZE="${VM_DISK_SIZE}G"
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}$VM_DISK_SIZE${CL}"
    elif [[ "$VM_DISK_SIZE" =~ ^[0-9]+G$ ]]; then
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}$VM_DISK_SIZE${CL}"
    else
      echo -e "${DISKSIZE}${BOLD}${RD}Invalid Disk Size. Please use a number (e.g., 10 or 10G).${CL}"
      exit_script
    fi
  else
    exit_script
  fi

  if VM_DISK_CACHE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "DISK CACHE" --radiolist "Choose" --cancel-button Exit-Script 10 58 2 \
    "0" "None (Default)" ON \
    "1" "Write Through" OFF \
    3>&1 1>&2 2>&3); then
    if [ $VM_DISK_CACHE = "1" ]; then
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${BGN}Write Through${CL}"
      VM_DISK_CACHE="cache=writethrough,"
    else
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${BGN}None${CL}"
      VM_DISK_CACHE=""
    fi
  else
    exit_script
  fi

  if VM_NAME=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Hostname" 8 58 docker --title "HOSTNAME" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $VM_NAME ]; then
      VM_HN="docker"
    else
      VM_HN=$(echo "${VM_NAME,,}" | tr -cs 'a-z0-9-' '-' | sed 's/^-//;s/-$//')
      if [ "$VM_HN" != "${VM_NAME,,}" ]; then
        whiptail --backtitle "Proxmox VE Helper Scripts" --title "HOSTNAME ADJUSTED" --msgbox "Invalid characters detected. Hostname has been adjusted to:\n\n  $VM_HN" 10 58
      fi
    fi
    echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}$VM_HN${CL}"
  else
    exit_script
  fi

  if CPU_TYPE1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "CPU MODEL" --radiolist "Choose" --cancel-button Exit-Script 10 58 2 \
    "1" "Host (Recommended)" ON \
    "0" "KVM64" OFF \
    3>&1 1>&2 2>&3); then
    if [ $CPU_TYPE1 = "1" ]; then
      echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}Host${CL}"
      VM_CPU=" -cpu host"
    else
      echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}KVM64${CL}"
      VM_CPU=""
    fi
  else
    exit_script
  fi

  while true; do
    if VM_CORE_COUNT=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate CPU Cores" 8 58 2 --title "CORE COUNT" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [ -z "$VM_CORE_COUNT" ]; then VM_CORE_COUNT="2"; fi
      if [[ "$VM_CORE_COUNT" =~ ^[1-9][0-9]*$ ]]; then
        echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}$VM_CORE_COUNT${CL}"
        break
      fi
      whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID INPUT" --msgbox "CPU Cores must be a positive integer (e.g., 2)." 8 58
    else
      exit_script
    fi
  done

  while true; do
    if VM_RAM_SIZE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate RAM in MiB" 8 58 4096 --title "RAM" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [ -z "$VM_RAM_SIZE" ]; then VM_RAM_SIZE="4096"; fi
      if [[ "$VM_RAM_SIZE" =~ ^[1-9][0-9]*$ ]]; then
        echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}$VM_RAM_SIZE${CL}"
        break
      fi
      whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID INPUT" --msgbox "RAM Size must be a positive integer in MiB (e.g., 4096)." 8 58
    else
      exit_script
    fi
  done

  if VM_BRG=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a Bridge" 8 58 vmbr0 --title "BRIDGE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $VM_BRG ]; then
      VM_BRG="vmbr0"
    fi
    echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}$VM_BRG${CL}"
  else
    exit_script
  fi

  while true; do
    if MAC1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a VM_MAC Address" 8 58 --title "VM_MAC ADDRESS" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [ -z "$MAC1" ]; then
        VM_MAC=""
        echo -e "${MACADDRESS}${BOLD}${DGN}VM_MAC Address: ${BGN}Auto-generated${CL}"
        break
      fi
      if [[ "$MAC1" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
        VM_MAC="$MAC1"
        echo -e "${MACADDRESS}${BOLD}${DGN}VM_MAC Address: ${BGN}$VM_MAC${CL}"
        break
      fi
      whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID INPUT" --msgbox "Invalid VM_MAC address format. Use XX:XX:XX:XX:XX:XX (e.g., AA:BB:CC:DD:EE:FF)." 8 58
    else
      exit_script
    fi
  done

  while true; do
    if VLAN1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a Vlan (leave blank for default)" 8 58 --title "VM_VLAN" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [ -z "$VLAN1" ]; then
        VLAN1="Default"
        VM_VLAN=""
        echo -e "${VLANTAG}${BOLD}${DGN}VM_VLAN: ${BGN}$VLAN1${CL}"
        break
      fi
      if [[ "$VLAN1" =~ ^[0-9]+$ ]] && [ "$VLAN1" -ge 1 ] && [ "$VLAN1" -le 4094 ]; then
        VM_VLAN=",tag=$VLAN1"
        echo -e "${VLANTAG}${BOLD}${DGN}VM_VLAN: ${BGN}$VLAN1${CL}"
        break
      fi
      whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID INPUT" --msgbox "VM_VLAN must be a number between 1 and 4094, or leave blank for default." 8 58
    else
      exit_script
    fi
  done

  while true; do
    if MTU1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Interface VM_MTU Size (leave blank for default)" 8 58 --title "VM_MTU SIZE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [ -z "$MTU1" ]; then
        MTU1="Default"
        VM_MTU=""
        echo -e "${DEFAULT}${BOLD}${DGN}Interface VM_MTU Size: ${BGN}$MTU1${CL}"
        break
      fi
      if [[ "$MTU1" =~ ^[0-9]+$ ]] && [ "$MTU1" -ge 576 ] && [ "$MTU1" -le 65520 ]; then
        VM_MTU=",mtu=$MTU1"
        echo -e "${DEFAULT}${BOLD}${DGN}Interface VM_MTU Size: ${BGN}$MTU1${CL}"
        break
      fi
      whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID INPUT" --msgbox "VM_MTU Size must be a number between 576 and 65520, or leave blank for default." 8 58
    else
      exit_script
    fi
  done

  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "START VIRTUAL VM_MACHINE" --yesno "Start VM when completed?" 10 58); then
    echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}yes${CL}"
    VM_START="yes"
  else
    echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}no${CL}"
    VM_START="no"
  fi

  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "ADVANCED SETTINGS COMPLETE" --yesno "Ready to create a Docker VM?" --no-button Do-Over 10 58); then
    echo -e "${CREATING}${BOLD}${DGN}Creating a Docker VM using the above advanced settings${CL}"
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

function start_script() {
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "SETTINGS" --yesno "Use Default Settings?" --no-button Advanced 10 58); then
    header_info
    echo -e "${DEFAULT}${BOLD}${BL}Using Default Settings${CL}"
    default_settings
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

function pre_build_script() {
  header_info
  echo -e "\n Loading..."

  if whiptail --backtitle "Proxmox VE Helper Scripts" --title "Docker VM" --yesno "This will create a New Docker VM. Proceed?" 10 58; then
    :
  else
    header_info && exit_script
  fi

  start_script

  VM_URL="$(get_image_url)"
  VM_CLOUD_INIT="${USE_CLOUD_INIT:-no}"
  VM_DISK_SIZE="${VM_DISK_SIZE:-10G}"
}

function post_install_script() {
  msg_ok "Created a Docker VM ${CL}${BL}(${VM_HN})"
  msg_ok "OS: ${OS_DISPLAY:-Debian 13}"
  if [ "${USE_CLOUD_INIT:-no}" = "yes" ]; then
    msg_ok "Cloud-Init: enabled"
  else
    msg_ok "Cloud-Init: disabled (console auto-login)"
  fi
  msg_ok "Completed successfully!\n"
  msg_info "Docker must be installed manually after first boot:"
  msg_info "  curl -fsSL https://get.docker.com | sh"
}

# framework bootstrap
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/vm")
