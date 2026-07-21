#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ) | Co-Author: Tom Frenzel (tomfrenzel)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://openthread.io/guides/border-router

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="OpenThread Border Router"
var_tags="${var_tags:-thread;iot;border-router;matter}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-0}"
var_tun="${var_tun:-yes}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    cmake \
    ninja-build \
    pkg-config \
    git \
    iproute2 \
    libreadline-dev \
    libncurses-dev \
    rsyslog \
    dbus \
    libdbus-1-dev \
    libjsoncpp-dev \
    iptables \
    ipset \
    bind9 \
    libnetfilter-queue1 \
    libnetfilter-queue-dev \
    libprotobuf-dev \
    protobuf-compiler \
    socat
  msg_ok "Installed Dependencies"

  setup_nodejs

  RELEASE=$(get_latest_gh_tag "openthread/ot-br-posix")
  if [[ -z "$RELEASE" ]]; then
    msg_error "Failed to fetch latest release tag"
    exit 1
  fi

  msg_info "Fetching GitHub release OpenThread-BR (${RELEASE#v})"
  $STD git clone --depth 1 --branch "$RELEASE" https://github.com/openthread/ot-br-posix /opt/ot-br-posix
  cd /opt/ot-br-posix || exit
  $STD git submodule update --depth 1 --init --recursive
  echo "${RELEASE#v}" > ~/.openthread-br
  msg_ok "Deployed GitHub release OpenThread-BR (${RELEASE#v})"

  msg_info "Building OpenThread Border Router (Patience)"
  mkdir -p build && cd build || exit
  $STD cmake -GNinja \
    -DBUILD_TESTING=OFF \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DOTBR_DBUS=ON \
    -DOTBR_MDNS=openthread \
    -DOTBR_REST=ON \
    -DOTBR_WEB=ON \
    -DOTBR_BORDER_ROUTING=ON \
    -DOTBR_BACKBONE_ROUTER=ON \
    -DOTBR_SYSTEMD_UNIT_DIR=/etc/systemd/system \
    -DOT_FIREWALL=ON \
    -DOT_POSIX_NAT64_CIDR="192.168.255.0/24" \
    ..
  $STD ninja
  $STD ninja install
  msg_ok "Built OpenThread Border Router"

  msg_info "Configuring Network"
  cat << EOF > /etc/sysctl.d/99-otbr.conf
net.ipv6.conf.all.forwarding=1
net.ipv6.conf.all.accept_ra=2
net.ipv6.conf.all.accept_ra_rtr_pref=1
net.ipv6.conf.all.accept_ra_rt_info_max_plen=64
net.ipv6.conf.default.forwarding=1
net.ipv6.conf.default.accept_ra=2
net.ipv6.conf.default.accept_ra_rtr_pref=1
net.ipv6.conf.default.accept_ra_rt_info_max_plen=64
net.ipv6.conf.eth0.forwarding=1
net.ipv6.conf.eth0.accept_ra=2
net.ipv6.conf.eth0.accept_ra_rtr_pref=1
net.ipv6.conf.eth0.accept_ra_rt_info_max_plen=64
net.ipv4.ip_forward=1
EOF
  $STD sysctl -p /etc/sysctl.d/99-otbr.conf
  msg_ok "Configured Network"

  msg_info "Configuring Services"
  cat << 'EOF' > /etc/default/otbr-agent
# USB example:
#   OTBR_AGENT_OPTS="-I wpan0 -B eth0 --vendor-name OpenThread --model-name BorderRouter --rest-listen-address 0.0.0.0 --rest-listen-port 8081 spinel+hdlc+uart:///dev/ttyACM0"
# TCP via socat (for network-attached RCP like SLZB-06/SLZB-MR3):
#   OTBR_AGENT_OPTS="-I wpan0 -B eth0 --vendor-name OpenThread --model-name BorderRouter --rest-listen-address 0.0.0.0 --rest-listen-port 8081 spinel+hdlc+forkpty:///usr/bin/socat?forkpty-arg=-,rawer&forkpty-arg=tcp:IP:PORT trel://eth0"
OTBR_AGENT_OPTS="-I wpan0 -B eth0 --vendor-name OpenThread --model-name BorderRouter --rest-listen-address 0.0.0.0 --rest-listen-port 8081 spinel+hdlc+uart:///dev/ttyACM0"
EOF
  cat << 'EOF' > /etc/default/otbr-web
OTBR_WEB_OPTS="-I wpan0 -a 0.0.0.0 -p 80"
EOF
  systemctl enable -q dbus rsyslog otbr-agent otbr-web
  systemctl enable -q bind9 2> /dev/null || systemctl enable -q named 2> /dev/null || true
  systemctl start -q dbus rsyslog bind9
  msg_ok "Configured Services"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/ot-br-posix ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "openthread-br" "openthread/ot-br-posix"; then
    msg_info "Stopping Services"
    systemctl stop otbr-web
    systemctl stop otbr-agent
    msg_ok "Stopped Services"

    if [[ -f /etc/init.d/otbr-agent ]] || [[ -f /etc/init.d/otbr-web ]]; then
      msg_info "Removing legacy services"
      rm -f /etc/init.d/otbr-agent /etc/init.d/otbr-web
      systemctl daemon-reload
      msg_ok "Removed legacy services"
    fi

    msg_info "Backing up Configuration"
    cp /etc/default/otbr-agent /etc/default/otbr-agent.bak
    msg_ok "Backed up Configuration"

    msg_info "Fetching GitHub release OpenThread-BR (${CHECK_UPDATE_RELEASE#v})"
    cd /opt/ot-br-posix || exit
    $STD git fetch --depth 1 origin tag "$CHECK_UPDATE_RELEASE"
    $STD git checkout -f "$CHECK_UPDATE_RELEASE"
    $STD git submodule update --depth 1 --init --recursive
    echo "${CHECK_UPDATE_RELEASE#v}" > ~/.openthread-br
    msg_ok "Deployed GitHub release OpenThread-BR (${CHECK_UPDATE_RELEASE#v})"

    msg_info "Rebuilding OpenThread Border Router (Patience)"
    cd /opt/ot-br-posix/build || exit
    $STD cmake -GNinja \
      -DBUILD_TESTING=OFF \
      -DCMAKE_INSTALL_PREFIX=/usr \
      -DOTBR_DBUS=ON \
      -DOTBR_MDNS=openthread \
      -DOTBR_REST=ON \
      -DOTBR_WEB=ON \
      -DOTBR_BORDER_ROUTING=ON \
      -DOTBR_BACKBONE_ROUTER=ON \
      -DOTBR_SYSTEMD_UNIT_DIR=/etc/systemd/system \
      -DOT_FIREWALL=ON \
      -DOT_POSIX_NAT64_CIDR="192.168.255.0/24" \
      ..
    $STD ninja
    $STD ninja install
    msg_ok "Rebuilt OpenThread Border Router"

    if ! grep -q "net.ipv6.conf.all.accept_ra=2" /etc/sysctl.d/99-otbr.conf; then
      msg_info "Configuring Network"
      cat << EOF > /etc/sysctl.d/99-otbr.conf
net.ipv6.conf.all.forwarding=1
net.ipv6.conf.all.accept_ra=2
net.ipv6.conf.all.accept_ra_rtr_pref=1
net.ipv6.conf.all.accept_ra_rt_info_max_plen=64
net.ipv6.conf.default.forwarding=1
net.ipv6.conf.default.accept_ra=2
net.ipv6.conf.default.accept_ra_rtr_pref=1
net.ipv6.conf.default.accept_ra_rt_info_max_plen=64
net.ipv6.conf.eth0.forwarding=1
net.ipv6.conf.eth0.accept_ra=2
net.ipv6.conf.eth0.accept_ra_rtr_pref=1
net.ipv6.conf.eth0.accept_ra_rt_info_max_plen=64
net.ipv4.ip_forward=1
EOF
      $STD sysctl -p /etc/sysctl.d/99-otbr.conf
      msg_ok "Configured Network"
    fi

    msg_info "Restoring Configuration"
    mv /etc/default/otbr-agent.bak /etc/default/otbr-agent
    msg_ok "Restored Configuration"

    msg_info "Starting Services"
    systemctl start otbr-agent
    systemctl start otbr-web
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
