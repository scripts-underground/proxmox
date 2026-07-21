#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Joerg Heinemann (heinemannj)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/smallstep/certificates

APP="step-ca"
var_tags="${var_tags:-certificate-authority;pki;acme-server}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  setup_deb822_repo \
    "smallstep" \
    "https://packages.smallstep.com/keys/apt/repo-signing-key.gpg" \
    "https://packages.smallstep.com/stable/debian" \
    "debs" \
    "main"

  msg_info "Installing step-ca and step-cli"
  $STD apt install -y step-ca step-cli

  STEPPATH="/etc/step-ca"
  STEPHOME="/etc/step"

  export STEPPATH=$STEPPATH
  echo "export STEPPATH=${STEPPATH}" >> /etc/profile
  export STEPHOME=$STEPHOME
  echo "export STEPHOME=${STEPHOME}" >> /etc/profile

  mkdir -p "$STEPHOME"

  STEPBIN="$(which step)"
  rm -f "$STEPBIN"
  cp -f "$(which step-cli)" "$STEPBIN"

  setcap CAP_NET_BIND_SERVICE=+eip "$(which step-ca)"

  $STD useradd --user-group --system --home "$(step path)" --shell /bin/false step
  msg_ok "Installed step-ca and step-cli"

  DomainName="$(hostname -d)"

  PKIName="$(prompt_input "Enter PKIName" "MyHomePKI" 30)"
  PKICountry="$(prompt_input "Enter PKICountry" "DE" 30)"
  PKIOrganizationalUnit="$(prompt_input "Enter PKIOrganizationalUnit" "MyHomeLab" 30)"
  PKIProvisioner="$(prompt_input "Enter PKIProvisioner" "pki@$DomainName" 30)"
  AcmeProvisioner="$(prompt_input "Enter AcmeProvisioner" "acme@$DomainName" 30)"
  X509MinDur="$(prompt_input "Enter X509MinDur" "48h" 30)"
  X509MaxDur="$(prompt_input "Enter X509MaxDur" "87600h" 30)"
  X509DefaultDur="$(prompt_input "Enter X509DefaultDur" "168h" 30)"

  msg_info "Initializing step-ca"

  DeploymentType="standalone"
  FQDN="$(hostname -f)"
  IP="${LOCAL_IP}"
  LISTENER=":443"
  LISTENER_INSECURE=":80"

  EncryptionPwdDir="$(step path)/encryption"
  PwdFile="$EncryptionPwdDir/ca.pwd"
  ProvisionerPwdFile="$EncryptionPwdDir/provisioner.pwd"
  mkdir -p "$EncryptionPwdDir"
  gpg -q --gen-random --armor 2 32 > "$PwdFile"
  gpg -q --gen-random --armor 2 32 > "$ProvisionerPwdFile"

  ln -s "$PwdFile" "$(step path)/password.txt"

  $STD step ca init \
    --deployment-type="$DeploymentType" \
    --ssh \
    --name="$PKIName" \
    --dns="$FQDN" \
    --dns="$IP" \
    --address="$LISTENER" \
    --provisioner="$PKIProvisioner" \
    --password-file="$PwdFile" \
    --provisioner-password-file="$ProvisionerPwdFile"

  mkdir -p "$(step path)/templates/ca"
  mkdir -p "$(step path)/templates/x509"

  CARootTemplate="$(step path)/templates/ca/root.tpl"
  CAIntermediateTemplate="$(step path)/templates/ca/intermediate.tpl"
  X509LeafTemplate="$(step path)/templates/x509/leaf.tpl"
  X509LeafTemplateData="$(step path)/templates/x509/leaf_data.tpl"

  cat << 'EOF' > "$CARootTemplate"
{
	"subject": {
		"country": {{ toJson .Insecure.User.country }},
		"organization": {{ toJson .Insecure.User.organization }},
		"organizationalUnit": {{ toJson .Insecure.User.organizationalUnit }},
		"commonName": {{ toJson .Subject.CommonName }}
	},
  "issuer": {{ toJson .Subject }},
	"keyUsage": ["certSign", "crlSign"],
	"basicConstraints": {
		"isCA": true,
		"maxPathLen": 1
	},
	"issuingCertificateURL": [{{ toJson .Insecure.User.issuingCertificateURL }}],
	"crlDistributionPoints": [{{ toJson .Insecure.User.crlDistributionPoints }}]
}
EOF

  cat << 'EOF' > "$CAIntermediateTemplate"
{
	"subject": {
		"country": {{ toJson .Insecure.User.country }},
		"organization": {{ toJson .Insecure.User.organization }},
		"organizationalUnit": {{ toJson .Insecure.User.organizationalUnit }},
		"commonName": {{ toJson .Subject.CommonName }}
	},
	"keyUsage": ["certSign", "crlSign"],
	"basicConstraints": {
		"isCA": true,
		"maxPathLen": 0
	},
	"issuingCertificateURL": [{{ toJson .Insecure.User.issuingCertificateURL }}],
	"crlDistributionPoints": [{{ toJson .Insecure.User.crlDistributionPoints }}]
}
EOF

  cat << 'EOF' > "$X509LeafTemplate"
{
	"subject": {
{{- if .Insecure.User.Country }}
		"country": {{ toJson .Insecure.User.country }},
{{- else }}
		"country": {{ toJson .country }},
{{- end }}
{{- if .Insecure.User.organization }}
		"organization": {{ toJson .Insecure.User.organization }},
{{- else }}
		"organization": {{ toJson .organization }},
{{- end }}
{{- if .Insecure.User.organizationalUnit }}
		"organizationalUnit": {{ toJson .Insecure.User.organizationalUnit }},
{{- else }}
		"organizationalUnit": {{ toJson .organizationalUnit }},
{{- end }}
		"commonName": {{ toJson .Subject.CommonName }}
	},
	"sans": {{ toJson .SANs }},
{{- if typeIs "*rsa.PublicKey" .Insecure.CR.PublicKey }}
	"keyUsage": ["keyEncipherment", "digitalSignature"],
{{- else }}
	"keyUsage": ["digitalSignature"],
{{- end }}
	"extKeyUsage": ["serverAuth", "clientAuth"],
{{- if .Insecure.User.issuingCertificateURL }}
	"issuingCertificateURL": [{{ toJson .Insecure.User.issuingCertificateURL }}],
{{- else }}
	"issuingCertificateURL": [{{ toJson .issuingCertificateURL }}],
{{- end }}
{{- if .Insecure.User.crlDistributionPoints }}
	"crlDistributionPoints": [{{ toJson .Insecure.User.crlDistributionPoints }}]
{{- else }}
	"crlDistributionPoints": [{{ toJson .crlDistributionPoints }}]
{{- end }}
}
EOF

  cat << EOF > "$X509LeafTemplateData"
{
	"country": "${PKICountry}",
	"organization": "${PKIName}",
	"organizationalUnit": "${PKIOrganizationalUnit}",
	"issuingCertificateURL": "https://${FQDN}${LISTENER}/intermediates.pem",
	"crlDistributionPoints": "https://${FQDN}${LISTENER}/crl"
}
EOF

  $STD step ca provisioner add "$AcmeProvisioner" \
    --type ACME \
    --admin-name "$AcmeProvisioner"

  $STD step ca provisioner update "$PKIProvisioner" \
    --x509-min-dur="$X509MinDur" \
    --x509-max-dur="$X509MaxDur" \
    --x509-default-dur="$X509DefaultDur" \
    --x509-template="$X509LeafTemplate" \
    --x509-template-data="$X509LeafTemplateData" \
    --allow-renewal-after-expiry

  $STD step ca provisioner update "$AcmeProvisioner" \
    --x509-min-dur="$X509MinDur" \
    --x509-max-dur="$X509MaxDur" \
    --x509-default-dur="$X509DefaultDur" \
    --x509-template="$X509LeafTemplate" \
    --x509-template-data="$X509LeafTemplateData" \
    --allow-renewal-after-expiry

  CAConfig="$(step path)/config/ca.json"
  jq --arg a "${PKICountry}" '.country = $a' "${CAConfig}" > "${CAConfig}_tmp" && mv "${CAConfig}_tmp" "${CAConfig}"
  jq --arg a "${PKIName}" '.organization = $a' "${CAConfig}" > "${CAConfig}_tmp" && mv "${CAConfig}_tmp" "${CAConfig}"
  jq --arg a "${PKIOrganizationalUnit}" '.organizationalUnit = $a' "${CAConfig}" > "${CAConfig}_tmp" && mv "${CAConfig}_tmp" "${CAConfig}"
  jq --arg a "${PKIName} Online CA" '.commonName = $a' "${CAConfig}" > "${CAConfig}_tmp" && mv "${CAConfig}_tmp" "${CAConfig}"
  jq '.db.badgerFileLoadingMode = "FileIO"' "${CAConfig}" > "${CAConfig}_tmp" && mv "${CAConfig}_tmp" "${CAConfig}"
  jq '.crl.enabled = true' "${CAConfig}" > "${CAConfig}_tmp" && mv "${CAConfig}_tmp" "${CAConfig}"
  jq '.crl.generateOnRevoke = true' "${CAConfig}" > "${CAConfig}_tmp" && mv "${CAConfig}_tmp" "${CAConfig}"
  jq '.crl.cacheDuration = "24h0m0s"' "${CAConfig}" > "${CAConfig}_tmp" && mv "${CAConfig}_tmp" "${CAConfig}"
  jq '.crl.renewPeriod = "16h0m0s"' "${CAConfig}" > "${CAConfig}_tmp" && mv "${CAConfig}_tmp" "${CAConfig}"
  jq --arg a "https://${FQDN}${LISTENER}/crl" '.crl.idpURL = $a' "${CAConfig}" > "${CAConfig}_tmp" && mv "${CAConfig}_tmp" "${CAConfig}"
  jq --arg a "$LISTENER_INSECURE" '.insecureAddress = $a' "${CAConfig}" > "${CAConfig}_tmp" && mv "${CAConfig}_tmp" "${CAConfig}"

  FLAGS=(--force
    --template="${CARootTemplate}"
    --not-after="219168h"
    --password-file="${PwdFile}"
    --set country="${PKICountry}"
    --set organization="${PKIName}"
    --set organizationalUnit="${PKIOrganizationalUnit}"
    --set issuingCertificateURL="https://${FQDN}${LISTENER}/roots.pem"
    --set crlDistributionPoints="https://${FQDN}${LISTENER}/crl")

  $STD step certificate create "${PKIName} Root CA" \
    "$(step path)/certs/root_ca.crt" \
    "$(step path)/secrets/root_ca_key" \
    "${FLAGS[@]}"

  FLAGS=(--force
    --template="${CAIntermediateTemplate}"
    --ca="$(step path)/certs/root_ca.crt"
    --ca-key="$(step path)/secrets/root_ca_key"
    --not-after="175368h"
    --ca-password-file="${PwdFile}"
    --password-file="${PwdFile}"
    --bundle
    --set country="${PKICountry}"
    --set organization="${PKIName}"
    --set organizationalUnit="${PKIOrganizationalUnit}"
    --set issuingCertificateURL="https://${FQDN}${LISTENER}/roots.pem"
    --set crlDistributionPoints="https://${FQDN}${LISTENER}/crl")

  $STD step certificate create "${PKIName} Intermediate CA" \
    "$(step path)/certs/intermediate_ca.crt" \
    "$(step path)/secrets/intermediate_ca_key" \
    "${FLAGS[@]}"

  $STD step certificate install --all "$(step path)/certs/root_ca.crt"
  $STD update-ca-certificates

  chown -R step:step "$(step path)"
  chmod -R 700 "$(step path)"
  msg_ok "Initialized step-ca"

  msg_info "Creating Service"
  cat << 'EOF' > /etc/systemd/system/step-ca.service
[Unit]
Description=step-ca service
Documentation=https://smallstep.com/docs/step-ca
Documentation=https://smallstep.com/docs/step-ca/certificate-authority-server-production
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=30
StartLimitBurst=3
ConditionFileNotEmpty=/etc/step-ca/config/ca.json
ConditionFileNotEmpty=/etc/step-ca/password.txt

[Service]
Type=simple
User=step
Group=step
Environment=STEPPATH=/etc/step-ca
WorkingDirectory=/etc/step-ca
ExecStart=/usr/bin/step-ca config/ca.json --password-file password.txt
ExecReload=/bin/kill -USR1 $MAINPID
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
StartLimitAction=reboot

; Process capabilities & privileges
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
SecureBits=keep-caps
NoNewPrivileges=yes

; Sandboxing
SystemCallArchitectures=native
SystemCallFilter=@system-service
SystemCallFilter=~@resources @privileged
RestrictNamespaces=yes
LockPersonality=yes
MemoryDenyWriteExecute=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
PrivateMounts=yes
ProtectControlGroups=yes
ProtectKernelModules=yes
ProtectKernelTunables=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/etc/step-ca/db

; Read only paths
ReadOnlyPaths=/etc/step-ca

[Install]
WantedBy=multi-user.target
EOF
  $STD systemctl enable -q --now step-ca
  msg_ok "Created Service"

  ARCH=$(uname -m)
  [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"
  fetch_and_deploy_gh_release "step-badger" "lukasz-lobocki/step-badger" "prebuild" "latest" "/opt/step-badger" "step-badger_Linux_${ARCH}.tar.gz"
  ln -s /opt/step-badger/step-badger /usr/local/bin/step-badger
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}https://${IP}/provisioners${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/apt/sources.list.d/smallstep.sources ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating step-ca and step-cli"
  $STD apt update
  $STD apt upgrade -y step-ca step-cli

  STEPBIN="$(which step)"
  rm -f "$STEPBIN"
  cp -f "$(which step-cli)" "$STEPBIN"

  sed -i \
    -e 's/\[//' \
    -e 's/\]//' \
    "$STEPPATH/templates/x509/leaf_data.tpl"

  step ca provisioner list | jq -c '.[] | select(.options.x509.templateData != null) | .name' > /tmp/provisioner_names.json
  for i in $(cat /tmp/provisioner_names.json); do
    prov=$(echo $i | tr -d '"')
    echo
    echo "Updating provisioner $prov ..."
    $STD step ca provisioner update "$prov" --x509-template-data="$STEPPATH/templates/x509/leaf_data.tpl"
  done
  rm /tmp/provisioner_names.json

  $STD systemctl restart step-ca
  msg_ok "Updated step-ca and step-cli"

  if check_for_gh_release "step-badger" "lukasz-lobocki/step-badger"; then
    ARCH=$(uname -m)
    [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"
    fetch_and_deploy_gh_release "step-badger" "lukasz-lobocki/step-badger" "prebuild" "latest" "/opt/step-badger" "step-badger_Linux_${ARCH}.tar.gz"
    msg_ok "Updated step-badger"
  fi
  exit
}

# shellcheck disable=SC1090
# Dynamic URL resolved at runtime
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
