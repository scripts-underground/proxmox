#!/usr/bin/env bash
# shellcheck disable=SC2034
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="TurnKey VM"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
VM_URL="${VM_URL:-}"
VM_OSTYPE="${VM_OSTYPE:-l26}"
VM_BIOS="${VM_BIOS:-seabios}"
VM_CLOUD_INIT="${VM_CLOUD_INIT:-no}"

function header_info {
  clear
  cat << "EOF"
 ______              __ __           __   _  _______
/_  __/_ _________  / //_/__ __ __  / /  | |/_/ ___/
 / / / // / __/ _ \/ ,< / -_) // / / /___>  </ /__
/_/  \_,_/_/ /_//_/_/|_|\__/\_, / /____/_/|_|\___/
                           /___/
EOF
}

function default_settings() {
  VM_VMID=$(get_valid_nextid)
  VM_DISK_FORMAT=",efitype=4m"
  VM_MACHINE=""
  VM_DISK_SIZE="${var_disk:-8}G"
  VM_DISK_CACHE=""
  VM_HN="turnkey"
  VM_CPU=""
  VM_CORE_COUNT="${var_cpu:-2}"
  VM_RAM_SIZE="${var_ram:-2048}"
  VM_BRG="vmbr0"
  VM_MAC=""
  VM_VLAN=""
  VM_MTU=""
  VM_START="no"
  echo -e "${CONTAINERID}${BOLD}${DGN}Virtual Machine ID: ${BGN}${VM_VMID}${CL}"
  echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}i440fx${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}${VM_DISK_SIZE}${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${BGN}None${CL}"
  echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}${VM_HN}${CL}"
  echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}KVM64${CL}"
  echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}${VM_CORE_COUNT}${CL}"
  echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}${VM_RAM_SIZE}${CL}"
  echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}${VM_BRG}${CL}"
  echo -e "${MACADDRESS}${BOLD}${DGN}VM_MAC Address: ${BGN}Auto-generated${CL}"
  echo -e "${VLANTAG}${BOLD}${DGN}VM_VLAN: ${BGN}Default${CL}"
  echo -e "${DEFAULT}${BOLD}${DGN}Interface VM_MTU Size: ${BGN}Default${CL}"
  echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}no${CL}"
  echo -e "${CREATING}${BOLD}${DGN}Creating a TurnKey VM using the above default settings${CL}"
}

function advanced_settings() {
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
    "i440fx" "Machine i440fx" ON \
    "q35" "Machine q35" OFF \
    3>&1 1>&2 2>&3); then
    if [ $MACH = q35 ]; then
      echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}$MACH${CL}"
      VM_DISK_FORMAT=""
      VM_MACHINE=" -machine q35"
    else
      echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}$MACH${CL}"
      VM_DISK_FORMAT=",efitype=4m"
      VM_MACHINE=""
    fi
  else
    exit_script
  fi

  if VM_DISK_SIZE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Disk Size in GiB" 8 58 "$VM_DISK_SIZE" --title "DISK SIZE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    VM_DISK_SIZE=$(echo "$VM_DISK_SIZE" | tr -d ' ')
    if [[ "$VM_DISK_SIZE" =~ ^[0-9]+$ ]]; then
      VM_DISK_SIZE="${VM_DISK_SIZE}G"
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}$VM_DISK_SIZE${CL}"
    elif [[ "$VM_DISK_SIZE" =~ ^[0-9]+G$ ]]; then
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}$VM_DISK_SIZE${CL}"
    else
      echo -e "${DISKSIZE}${BOLD}${RD}Invalid Disk Size.${CL}"
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

  if VM_NAME=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Hostname" 8 58 turnkey --title "HOSTNAME" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $VM_NAME ]; then
      VM_HN="turnkey"
      echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}$VM_HN${CL}"
    else
      VM_HN=$(echo ${VM_NAME,,} | tr -d ' ')
      echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}$VM_HN${CL}"
    fi
  else
    exit_script
  fi

  if CPU_TYPE1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "CPU MODEL" --radiolist "Choose" --cancel-button Exit-Script 10 58 2 \
    "0" "KVM64 (Default)" ON \
    "1" "Host" OFF \
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

  if VM_CORE_COUNT=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate CPU Cores" 8 58 2 --title "CORE COUNT" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $VM_CORE_COUNT ]; then
      VM_CORE_COUNT="2"
      echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}$VM_CORE_COUNT${CL}"
    else
      echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}$VM_CORE_COUNT${CL}"
    fi
  else
    exit_script
  fi

  if VM_RAM_SIZE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate RAM in MiB" 8 58 2048 --title "RAM" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $VM_RAM_SIZE ]; then
      VM_RAM_SIZE="2048"
      echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}$VM_RAM_SIZE${CL}"
    else
      echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}$VM_RAM_SIZE${CL}"
    fi
  else
    exit_script
  fi

  if VM_BRG=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a Bridge" 8 58 vmbr0 --title "BRIDGE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $VM_BRG ]; then
      VM_BRG="vmbr0"
      echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}$VM_BRG${CL}"
    else
      echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}$VM_BRG${CL}"
    fi
  else
    exit_script
  fi

  if MAC1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a VM_MAC Address" 8 58 --title "VM_MAC ADDRESS" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $MAC1 ]; then
      VM_MAC=""
      echo -e "${MACADDRESS}${BOLD}${DGN}VM_MAC Address: ${BGN}Auto-generated${CL}"
    else
      VM_MAC="$MAC1"
      echo -e "${MACADDRESS}${BOLD}${DGN}VM_MAC Address: ${BGN}$MAC1${CL}"
    fi
  else
    exit_script
  fi

  if VLAN1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a Vlan(leave blank for default)" 8 58 --title "VM_VLAN" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $VLAN1 ]; then
      VLAN1="Default"
      VM_VLAN=""
      echo -e "${VLANTAG}${BOLD}${DGN}VM_VLAN: ${BGN}$VLAN1${CL}"
    else
      VM_VLAN=",tag=$VLAN1"
      echo -e "${VLANTAG}${BOLD}${DGN}VM_VLAN: ${BGN}$VLAN1${CL}"
    fi
  else
    exit_script
  fi

  if MTU1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Interface VM_MTU Size (leave blank for default)" 8 58 --title "VM_MTU SIZE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $MTU1 ]; then
      MTU1="Default"
      VM_MTU=""
      echo -e "${DEFAULT}${BOLD}${DGN}Interface VM_MTU Size: ${BGN}$MTU1${CL}"
    else
      VM_MTU=",mtu=$MTU1"
      echo -e "${DEFAULT}${BOLD}${DGN}Interface VM_MTU Size: ${BGN}$MTU1${CL}"
    fi
  else
    exit_script
  fi

  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "START VIRTUAL VM_MACHINE" --yesno "Start VM when completed?" 10 58); then
    echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}yes${CL}"
    VM_START="yes"
  else
    echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}no${CL}"
    VM_START="no"
  fi

  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "ADVANCED SETTINGS COMPLETE" --yesno "Ready to create a TurnKey VM?" --no-button Do-Over 10 58); then
    echo -e "${CREATING}${BOLD}${DGN}Creating a TurnKey VM using the above advanced settings${CL}"
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

  if whiptail --backtitle "Proxmox VE Helper Scripts" --title "TurnKey VM" --yesno "This will create a New TurnKey VM. Proceed?" 10 58; then
    :
  else
    header_info && exit_script
  fi

  start_script

  VM_CLOUD_INIT="${VM_CLOUD_INIT:-no}"
}

function post_install_script() {
  msg_ok "Created a TurnKey VM ${CL}${BL}(${VM_HN})"
  msg_ok "Completed successfully!\n"
}

# framework bootstrap
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/vm")
