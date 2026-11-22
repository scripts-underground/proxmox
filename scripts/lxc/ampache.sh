#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/ampache/ampache

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Ampache"
var_tags="${var_tags:-music}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-5}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  # Installation owns a fresh root. Operator aliases/data belong to update only.
  local ampache_root=/opt/ampache
  if [[ -e "$ampache_root" || -L "$ampache_root" ]]; then
    msg_error "Ampache installation requires an absent /opt/ampache; existing data was not changed"
    return 65
  fi
  mkdir -- "$ampache_root"
  # The release owns code, not an existing library or descendant mounted data.
  local -a CLEAN_INSTALL_KEEP_PATHS=("${CLEAN_INSTALL_KEEP_PATHS[@]}" music)
  # Follow upstream's recommended Ampache 7 line on PHP 8.4. A 7 -> 8
  # migration (and PHP 8.5) requires a separate explicit decision.
  UPDATE_FORCE=1 check_for_gh_release "Ampache" "ampache/ampache" "latest" "" "7." || return $?
  local release="$CHECK_UPDATE_RELEASE"
  if [[ "$release" != 7.* ]]; then
    msg_error "Ampache requires a 7.x release on PHP 8.4; refusing ${release}"
    return 65
  fi

  msg_info "Installing Dependencies"
  $STD apt install -y \
    flac \
    vorbis-tools \
    lame \
    ffmpeg \
    inotify-tools \
    libavcodec-extra \
    libmp3lame-dev \
    libtheora-dev \
    libvorbis-dev \
    libvpx-dev
  msg_ok "Installed Dependencies"

  PHP_VERSION="8.4" PHP_APACHE="YES" setup_php
  setup_mariadb
  MARIADB_DB_USER="ampache" MARIADB_DB_NAME="ampache" setup_mariadb_db

  # Deploy the selected tag exactly: a missing asset must not select an older release.
  fetch_and_deploy_gh_release "ampache" "ampache/ampache" "prebuild" "$release" "$ampache_root" "ampache-*_all_php8.4.zip" "7."

  msg_info "Setting Up Ampache"
  rm -rf /var/www/html
  ln -s "$ampache_root/public" /var/www/html
  mv "$ampache_root/public/rest/.htaccess.dist" "$ampache_root/public/rest/.htaccess"
  mv "$ampache_root/public/play/.htaccess.dist" "$ampache_root/public/play/.htaccess"
  cp "$ampache_root/config/ampache.cfg.php.dist" "$ampache_root/config/ampache.cfg.php"
  chmod 664 "$ampache_root/public/rest/.htaccess" "$ampache_root/public/play/.htaccess"
  msg_ok "Set Up Ampache"

  msg_info "Configuring Database Connection"
  sed -i \
    -e 's|^database_hostname = .*|database_hostname = "localhost"|' \
    -e 's|^database_name = .*|database_name = "ampache"|' \
    -e 's|^database_username = .*|database_username = "ampache"|' \
    -e "s|^database_password = .*|database_password = \"${MARIADB_DB_PASS}\"|" \
    "$ampache_root/config/ampache.cfg.php"
  # Only freshly deployed code exists under our newly created root. Do not
  # dereference release symlinks while assigning its initial ownership.
  chown -h www-data:www-data "$ampache_root"
  find "$ampache_root/" -mindepth 1 -exec chown -h www-data:www-data -- {} +
  msg_ok "Configured Database Connection"

  msg_info "Importing Database Schema"
  mariadb -u ampache -p"${MARIADB_DB_PASS}" ampache < "$ampache_root/resources/sql/ampache.sql"
  msg_ok "Imported Database Schema"

  msg_info "Configuring PHP"
  sed -i \
    -e 's/upload_max_filesize = .*/upload_max_filesize = 100M/' \
    -e 's/post_max_size = .*/post_max_size = 100M/' \
    -e 's/max_execution_time = .*/max_execution_time = 600/' \
    -e 's/memory_limit = .*/memory_limit = 512M/' \
    /etc/php/8.4/apache2/php.ini
  $STD a2enmod rewrite
  $STD systemctl restart apache2
  msg_ok "Configured PHP"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}/install.php${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  local ampache_root
  # This owner is deliberately nested: cold bundles contain only this hook.
  # Resolve the root once; all update consumers receive the owner's entries.
  function ampache_identity_root() {
    ampache_root=$(cd -- /opt/ampache && pwd -P)
  }
  if [[ ! -d /opt/ampache ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  ampache_identity_root || return $?
  local -a CLEAN_INSTALL_KEEP_PATHS=("${CLEAN_INSTALL_KEEP_PATHS[@]}" music)

  # Keep existing installations on Ampache 7 / PHP 8.4, just like fresh installs.
  # Ampache 8 / PHP 8.5 migration is a separate explicit decision.
  if check_for_gh_release "Ampache" "ampache/ampache" "latest" "" "7."; then
    local release="$CHECK_UPDATE_RELEASE"
    if [[ "$release" != 7.* ]]; then
      msg_error "Ampache requires a 7.x release on PHP 8.4; refusing ${release}"
      return 65
    fi
    # Keep required helpers in a plain strict subshell: a conditional call would
    # suppress their internal errexit. Its EXIT owner cannot replace the runner's
    # pending/cleanup owner and preserves the original failure even if recovery fails.
    (
      local prior before after stop_attempted=0 write_phase=deployment
      local identity_path identity_inode
      local -a identity_mounts=() identity_roots=() identity_devices=() identity_rows=() identity_entries=()
      # Mountinfo is also the authority for bind aliases, including a missing
      # leaf after a failed restore. realpath alone cannot identify a bind alias.
      function ampache_identity_mounts() {
        local device root mount row
        identity_mounts=() identity_roots=() identity_devices=() identity_rows=()
        [[ -r /proc/self/mountinfo ]] || return 69
        while IFS= read -r row; do
          read -r _ _ device root mount _ <<< "$row"
          root=${root//\\040/ } root=${root//\\011/$'\t'} root=${root//\\012/$'\n'} root=${root//\\134/$'\\'}
          mount=${mount//\\040/ } mount=${mount//\\011/$'\t'} mount=${mount//\\012/$'\n'} mount=${mount//\\134/$'\\'}
          identity_mounts+=("$mount") identity_roots+=("$root") identity_devices+=("$device") identity_rows+=("$row")
        done < /proc/self/mountinfo
      }
      function ampache_identity_entry() {
        local input="$1" parent leaf i selected=-1 length=0 fs_path candidate best original=''
        # Preserve the final link as an object (cp -a/chown -h), never its target.
        parent=$(realpath -m -- "${input%/*}") || return $?
        leaf=${input##*/}
        identity_path="${parent%/}/$leaf" identity_inode=''
        if [[ -e "$identity_path" || -L "$identity_path" ]]; then original=$(stat -c '%d:%i' -- "$identity_path") || return $?; fi
        for i in "${!identity_mounts[@]}"; do
          candidate=${identity_mounts[$i]}
          if [[ "$candidate" == / || "$identity_path" == "$candidate" || "$identity_path" == "$candidate/"* ]]; then
            if ((${#candidate} > length)); then selected=$i length=${#candidate}; fi
          fi
        done
        ((selected >= 0)) || return 69
        candidate=${identity_mounts[$selected]}
        fs_path="${identity_roots[$selected]%/}/${identity_path#"${candidate%/}/"}"
        [[ "$identity_path" != "$candidate" ]] || fs_path=${identity_roots[$selected]}
        best=$identity_path
        for i in "${!identity_mounts[@]}"; do
          [[ "${identity_devices[$i]}" == "${identity_devices[$selected]}" ]] || continue
          candidate=${identity_roots[$i]}
          if [[ "$candidate" == / || "$fs_path" == "$candidate" || "$fs_path" == "$candidate/"* ]]; then
            candidate="${identity_mounts[$i]%/}/${fs_path#"${candidate%/}/"}"
            [[ "$fs_path" != "${identity_roots[$i]}" ]] || candidate=${identity_mounts[$i]}
            # The least-mounted spelling is stable even after a live leaf removal.
            if ((${#identity_mounts[$i]} < length)); then best=$candidate length=${#identity_mounts[$i]}; fi
          fi
        done
        identity_path=$best
        if [[ -e "$identity_path" || -L "$identity_path" ]]; then
          identity_inode=$(stat -c '%d:%i' -- "$identity_path") || return $?
        fi
        [[ -z "$original" || "$original" == "$identity_inode" ]] || return 65
      }
      function ampache_identity_list() {
        local listing status
        listing=$(mktemp) || return $?
        if find "$1" -print0 > "$listing"; then
          mapfile -d '' -t identity_entries < "$listing"
          rm -f -- "$listing"
        else
          status=$?
          rm -f -- "$listing"
          return "$status"
        fi
      }
      function ampache_identity_digest() (
        set -o pipefail
        local path="$1"
        {
          stat -c '%f:%u:%g' -- "$path" || exit $?
          if [[ -L "$path" ]]; then
            readlink -- "$path" || exit $?
          elif [[ -f "$path" ]]; then
            sha256sum < "$path" || exit $?
          elif [[ ! -d "$path" ]]; then exit 65; fi
        } | sha256sum
      )
      function ampache_identity_contents() (
        set -o pipefail
        local path="$1"
        {
          if [[ -L "$path" ]]; then
            printf 'link\n'
            readlink -- "$path" || exit $?
          elif [[ -f "$path" ]]; then
            printf 'file\n'
            sha256sum < "$path" || exit $?
          elif [[ -d "$path" ]]; then
            printf 'directory\n'
          else exit 65; fi
        } | sha256sum
      )
      # One deployment footprint drives both integrity and live ownership writes.
      # Restore/configuration has a wider footprint and is never auto-recoverable.
      function ampache_footprint() (
        set -o pipefail
        local operation="$1"
        case "$operation" in fingerprint | ownership) ;; *) exit 65 ;; esac
        {
          local path mount pattern entry rest part i snapshot physical_root inode metadata target
          local -a prune=(-false) persistent=() paths=() batch=()
          local -A visited=() entry_inodes=() entry_metadata=() entry_targets=()
          # Consume the same persistence declarations as checked replacement,
          # including a kept path's first live symlink ancestor.
          case "${CLEAN_INSTALL_KEEP:-}" in *$'\n'* | *$'\r'* | *$'\t'*) exit 65 ;; esac
          read -r -a persistent <<< "${CLEAN_INSTALL_KEEP:-}"
          persistent+=("${CLEAN_INSTALL_KEEP_PATHS[@]}")
          for entry in "${persistent[@]}"; do
            [[ -n "$entry" ]] || exit 65
            case "/$entry/" in //* | *//* | */./* | */../* | *'*'* | *'?'* | *'['* | *']'*) exit 65 ;; esac
            path="$ampache_root" rest="$entry"
            while [[ -n "$rest" ]]; do
              part=${rest%%/*}
              path+="/$part"
              [[ ! -L "$path" && "$rest" == */* ]] || break
              rest=${rest#*/}
            done
            pattern=${path//\\/\\\\}
            pattern=${pattern//\*/\\*}
            pattern=${pattern//\?/\\?}
            pattern=${pattern//\[/\\[}
            prune+=(-o -path "$pattern")
          done
          ampache_identity_mounts || exit $?
          # Media is persistent data, not deployment-owned code. Mountinfo also
          # identifies same-device bind mounts that find -xdev cannot exclude.
          # Record each mounted boundary without visiting or reading its contents.
          for i in "${!identity_mounts[@]}"; do
            mount=${identity_mounts[$i]}
            [[ "$mount" == "$ampache_root/"* ]] || continue
            if [[ "$operation" == fingerprint ]]; then
              printf 'mount:%s\0' "${identity_rows[$i]}" || exit $?
              stat -c '%f:%u:%g:%d:%i' -- "$mount" || exit $?
            fi
            # find -path takes a pattern; preserve literal operator mount names.
            pattern=${mount//\\/\\\\}
            pattern=${pattern//\*/\\*}
            pattern=${pattern//\?/\\?}
            pattern=${pattern//\[/\\[}
            prune+=(-o -path "$pattern")
          done
          # find never follows child links and prunes every mount boundary. Its
          # remaining paths therefore share the root's already resolved physical
          # namespace. Capture path/inode/metadata together in one native walk,
          # not realpath + two stat children for every code file.
          ampache_identity_entry "$ampache_root" || exit $?
          physical_root=$identity_path
          snapshot=$(mktemp) || exit $?
          trap 'rm -f -- "$snapshot"' EXIT
          find "$ampache_root" \( "${prune[@]}" \) -prune -o -printf '%p\0%D:%i\0%y:%m:%U:%G\0%l\0' > "$snapshot" || exit $?
          while IFS= read -r -d '' path; do
            IFS= read -r -d '' inode && IFS= read -r -d '' metadata && IFS= read -r -d '' target || exit 65
            identity_path="$physical_root${path#"$ampache_root"}"
            paths+=("$identity_path")
            entry_inodes["$identity_path"]=$inode entry_metadata["$identity_path"]=$metadata entry_targets["$identity_path"]=$target
          done < "$snapshot"
          printf '%s\0' "${paths[@]}" | LC_ALL=C sort -zu | {
            while IFS= read -r -d '' identity_path; do
              local key=${entry_inodes["$identity_path"]}
              if [[ "$operation" == fingerprint ]]; then printf '%s\0' "$identity_path" || exit $?; fi
              [[ ! -v visited["$key"] ]] || continue
              visited["$key"]=1
              if [[ "$operation" == ownership ]]; then
                batch+=("$identity_path")
                if ((${#batch[@]} >= 128)); then
                  chown -h www-data:www-data -- "${batch[@]}" || exit $?
                  batch=()
                fi
                continue
              fi
              metadata=${entry_metadata["$identity_path"]}
              printf '%s\0' "$metadata" || exit $?
              case "${metadata%%:*}" in
                f) sha256sum < "$identity_path" || exit $? ;;
                l) printf '%s\0' "${entry_targets["$identity_path"]}" || exit $? ;;
                d) ;;
                *) exit 65 ;;
              esac
            done
            # The sorted consumer is a child: flush its last ownership batch there,
            # rather than losing it when the pipeline returns.
            if [[ "$operation" == ownership ]] && ((${#batch[@]})); then
              chown -h www-data:www-data -- "${batch[@]}" || exit $?
            fi
          }
          if [[ "$operation" == fingerprint ]]; then
            ampache_identity_entry "$HOME/.ampache" || exit $?
            printf '%s\0' "$identity_path" || exit $?
            if [[ -z "$identity_inode" ]]; then
              printf 'absent\n'
            else ampache_identity_digest "$identity_path" || exit $?; fi
          fi
        }
      )
      # The backup owner certifies one source per physical path or live inode.
      # The NUL manifest freezes that selection BEFORE any live removal, making
      # retry independent of the old inode's continued existence. Legacy rows are
      # admitted in order; later spellings never replace the first certified copy.
      local store="${BACKUP_DIR:-/opt/${NSAPP}.backup}" registry
      registry="$store/.ampache-identities"
      local -a saved_paths=() saved_inodes=() saved_sources=() saved_digests=() certified_sources=()
      local -a saved_alias_paths=() saved_alias_keys=()
      local -A saved_by_path=() saved_by_inode=()
      function ampache_identity_store_check() {
        local physical mount
        [[ ! -L "$store" && (! -e "$store" || -d "$store") ]] || return 65
        physical=$(realpath -m -- "$store") || return $?
        ampache_identity_mounts || return $?
        for mount in "${identity_mounts[@]}"; do
          [[ "$mount" != "$physical" && "$mount" != "$physical/"* ]] || return 65
        done
      }
      function ampache_identity_save_entry() {
        local path="$1" source="$2" digest="${3:-}" inode="${4:-}" index
        ampache_identity_entry "$path" || return $?
        [[ -z "$inode" ]] || identity_inode=$inode
        [[ ! -v saved_by_path["$identity_path"] ]] || return 0
        if [[ -n "$identity_inode" && -v saved_by_inode["$identity_inode"] ]]; then
          index=${saved_by_inode["$identity_inode"]}
          saved_alias_paths+=("$identity_path") saved_alias_keys+=("$index")
          saved_by_path["$identity_path"]=$index
          return 0
        fi
        index=${#saved_paths[@]}
        saved_paths+=("$identity_path") saved_inodes+=("$identity_inode") saved_sources+=("$source") saved_digests+=("$digest")
        saved_by_path["$identity_path"]=$index
        [[ -z "$identity_inode" ]] || saved_by_inode["$identity_inode"]=$index
      }
      function ampache_identity_backup() {
        local fd path inode source digest row object relative index stage
        local -a requests=(config/ampache.cfg.php public/rest/.htaccess public/play/.htaccess advanced-config)
        ampache_identity_store_check || return $?
        if [[ -e "$registry" ]]; then
          [[ -f "$registry" && ! -L "$registry" ]] || return 65
          exec {fd}< "$registry"
          IFS= read -r -d '' row <&"$fd" || return 65
          [[ "$row" == ampache-identity-v1 ]] || return 65
          while :; do
            path=''
            if ! IFS= read -r -d '' path <&"$fd"; then
              [[ -z "$path" ]] || return 65
              break
            fi
            IFS= read -r -d '' inode <&"$fd" && IFS= read -r -d '' source <&"$fd" && IFS= read -r -d '' digest <&"$fd" || return 65
            [[ "$source" == "$store/"* ]] || return 65
            case "/${source#"$store/"}/" in *//* | */./* | */../*) return 65 ;; esac
            _backup_check_parents "$store" "${source#"$store/"}" || return $?
            [[ "$(ampache_identity_digest "$source")" == "$digest" ]] || return 65
            certified_sources+=("$source")
            ampache_identity_save_entry "$path" "$source" "$digest" "$inode" || return $?
          done
          exec {fd}<&-
        elif [[ -e "$store/.manifest" ]]; then
          [[ -f "$store/.manifest" && ! -L "$store/.manifest" ]] || return 65
          row=$(cat -- "$store/.manifest") || return $?
          while IFS= read -r path; do
            [[ -n "$path" ]] || continue
            case "$path" in /*) ;; *) return 65 ;; esac
            case "/${path#/}/" in *//* | */./* | */../*) return 65 ;; esac
            source="$store/files$path"
            _backup_check_parents "$store/files" "${path#/}" || return $?
            [[ -e "$source" || -L "$source" ]] || return 65
            certified_sources+=("$source")
            ampache_identity_list "$source" || return $?
            for object in "${identity_entries[@]}"; do
              relative=${object#"$source"}
              ampache_identity_save_entry "$path$relative" "$object" || return $?
            done
          done <<< "$row"
        fi
        # Complete canonical selection before creating ANY backup objects.
        for row in "${requests[@]}"; do
          path="$ampache_root/$row"
          [[ -e "$path" || -L "$path" ]] || continue
          ampache_identity_list "$path" || return $?
          for object in "${identity_entries[@]}"; do ampache_identity_save_entry "$object" '' || return $?; done
        done
        _backup_check_parents "$store" objects/placeholder || return $?
        mkdir -p -- "$store/objects" || return $?
        for index in "${!saved_paths[@]}"; do
          source=${saved_sources[$index]}
          if [[ -z "$source" ]]; then
            path=${saved_paths[$index]}
            stage=$(mktemp -d "$store/objects/entry.XXXXXX") || return $?
            source="$stage/object"
            if [[ -d "$path" && ! -L "$path" ]]; then
              mkdir -- "$source" && chmod --reference="$path" -- "$source" && chown --reference="$path" -- "$source" || return $?
            else
              cp -a -- "$path" "$source" || return $?
            fi
            digest=$(ampache_identity_digest "$source") || return $?
            [[ "$(ampache_identity_digest "$path")" == "$digest" ]] || return 65
            saved_sources[$index]=$source saved_digests[$index]=$digest
            certified_sources+=("$source")
          elif [[ -z "${saved_digests[$index]}" ]]; then
            saved_digests[$index]=$(ampache_identity_digest "$source") || return $?
          fi
        done
        stage=$(mktemp "$store/.identities.XXXXXX") || return $?
        {
          printf 'ampache-identity-v1\0' || return $?
          for index in "${!saved_paths[@]}"; do
            printf '%s\0' "${saved_paths[$index]}" "${saved_inodes[$index]}" "${saved_sources[$index]}" "${saved_digests[$index]}" || return $?
          done
          for index in "${!saved_alias_paths[@]}"; do
            path=${saved_alias_keys[$index]}
            printf '%s\0' "${saved_alias_paths[$index]}" "${saved_inodes[$path]}" "${saved_sources[$path]}" "${saved_digests[$path]}" || return $?
          done
        } > "$stage"
        mv -T -- "$stage" "$registry" || return $?
      }
      function ampache_identity_restore() {
        local index path source observed status
        ampache_identity_store_check || return $?
        # Validate the whole selection before removing even the first live file.
        for index in "${!saved_paths[@]}"; do
          [[ "$(ampache_identity_digest "${saved_sources[$index]}")" == "${saved_digests[$index]}" ]] || return 65
        done
        for index in "${!saved_paths[@]}"; do
          path=${saved_paths[$index]} source=${saved_sources[$index]}
          ampache_identity_entry "$path" || return $?
          [[ "$identity_path" == "$path" ]] || return 65
          if [[ -d "$source" && ! -L "$source" ]]; then
            [[ ! -L "$path" && (! -e "$path" || -d "$path") ]] || return 65
            mkdir -p -- "$path" && chmod --reference="$source" -- "$path" && chown --reference="$source" -- "$path" || return $?
          else
            mkdir -p -- "${path%/*}" || return $?
            [[ ! -d "$path" || -L "$path" ]] || return 65
            if [[ -f "$source" && ! -L "$source" && -f "$path" && ! -L "$path" ]] && ampache_identity_inplace; then
              cp -p -- "$source" "$path" || return $?
            else
              status=$?
              [[ "$status" == 1 ]] || return "$status"
              rm -f -- "$path" || return $?
              cp -a -- "$source" "$path" || return $?
            fi
          fi
          observed=$(ampache_identity_digest "$path") || return $?
          [[ "$observed" == "${saved_digests[$index]}" ]] || return 65
        done
        for index in "${!saved_alias_paths[@]}"; do
          path=${saved_alias_paths[$index]} source=${saved_paths[${saved_alias_keys[$index]}]}
          ampache_identity_entry "$path" || return $?
          [[ "$identity_path" == "$path" ]] || return 65
          [[ ! -d "$source" ]] || return 65
          observed=$identity_inode
          ampache_identity_entry "$source" || return $?
          [[ -z "$observed" || "$observed" != "$identity_inode" ]] || continue
          mkdir -p -- "${path%/*}" || return $?
          rm -f -- "$path" || return $?
          ln -P -- "$source" "$path" || return $?
        done
        # A later alias must not be able to overwrite a previously verified key.
        for index in "${!saved_paths[@]}"; do
          [[ "$(ampache_identity_digest "${saved_paths[$index]}")" == "${saved_digests[$index]}" ]] || return 65
        done
      }
      function ampache_identity_inplace() {
        local mount inode links
        links=$(stat -c '%h' -- "$identity_path") || return $?
        ((links > 1)) && return 0
        for mount in "${identity_mounts[@]}"; do
          [[ -f "$mount" && ! -L "$mount" ]] || continue
          inode=$(stat -c '%d:%i' -- "$mount") || return $?
          [[ "$inode" != "$identity_inode" ]] || return 0
        done
        return 1
      }
      function ampache_identity_retire() {
        local index source object observed expected certified=1 retained
        # Ownership/mode are deliberately initialized after restore. Verify bytes
        # again after those consumers AND activation, before retiring any copy.
        for index in "${!saved_paths[@]}"; do
          observed=$(ampache_identity_contents "${saved_paths[$index]}") || return $?
          expected=$(ampache_identity_contents "${saved_sources[$index]}") || return $?
          [[ "$observed" == "$expected" ]] || return 65
        done
        for index in "${!saved_alias_paths[@]}"; do
          ampache_identity_entry "${saved_alias_paths[$index]}" || return $?
          observed=$identity_inode
          ampache_identity_entry "${saved_paths[${saved_alias_keys[$index]}]}" || return $?
          [[ -n "$observed" && "$observed" == "$identity_inode" ]] || return 65
        done
        ampache_identity_store_check || return $?
        # Unknown backing is never swept. Preserve the complete store beside the
        # active name, just as the framework does for uncertified recovery bytes.
        ampache_identity_list "$store" || return $?
        for object in "${identity_entries[@]}"; do
          case "$object" in "$store" | "$registry" | "$store/.manifest" | "$store/files" | "$store/objects") continue ;; esac
          observed=0
          for source in "${certified_sources[@]}"; do
            if [[ "$object" == "$source" || "$object" == "$source/"* || "$source" == "$object/"* ]]; then
              observed=1
              break
            fi
          done
          [[ "$observed" == 1 ]] || certified=0
        done
        ampache_identity_store_check || return $?
        if [[ "$certified" == 1 ]]; then
          rm -rf -- "$store" || return $?
        else
          retained=$(mktemp -d "$store.incomplete.XXXXXX") || return $?
          mv -T -- "$store" "$retained/object" || return $?
          msg_warn "Uncertified backup retained at $retained/object"
        fi
      }
      function ampache_identity_permissions() {
        local entry
        local -A visited=()
        for entry in public/rest/.htaccess public/play/.htaccess; do
          ampache_identity_entry "$ampache_root/$entry" || return $?
          [[ ! -L "$identity_path" ]] || continue
          [[ ! -v visited["$identity_inode"] ]] || continue
          visited["$identity_inode"]=1
          chmod 664 -- "$identity_path" || return $?
        done
      }
      function ampache_runtime_state() (
        set -o pipefail
        ampache_footprint fingerprint | sha256sum
      )
      function ampache_recover() {
        local status=$?
        trap - EXIT
        if [[ "$status" != 0 && "$stop_attempted" == 1 && "$write_phase" == deployment && "$prior" == active ]]; then
          after=$(ampache_runtime_state) || after=unverified
          if [[ "$after" == "$before" ]]; then
            systemctl start apache2 || msg_warn "Unable to restart previous Ampache service"
          else
            msg_warn "Previous Ampache runtime is unverified; Apache stays stopped"
          fi
        elif [[ "$status" != 0 && "$stop_attempted" == 1 && "$write_phase" != deployment ]]; then
          systemctl stop apache2 || msg_warn "Unable to stop unverified Ampache service"
        fi
        if [[ "$status" != 0 && -d "$store" ]]; then
          msg_warn "Ampache update failed; recovery bytes retained at $store"
        fi
        exit "$status"
      }
      prior=$(systemctl show apache2 --property=ActiveState --value)
      case "$prior" in active | inactive | failed) ;; *) return 65 ;; esac
      ampache_identity_mounts
      before=$(ampache_runtime_state)
      trap ampache_recover EXIT

      msg_info "Stopping Service"
      stop_attempted=1
      systemctl stop apache2
      msg_ok "Stopped Service"

      msg_info "Creating Backup"
      ampache_identity_backup
      msg_ok "Backup Created"

      fetch_and_deploy_gh_release "Ampache" "ampache/ampache" "prebuild" "$release" "$ampache_root" "ampache-*_all_php8.4.zip" "7."

      # Backup is read-only with respect to the live runtime. Restore is not:
      # it removes/copies config even through mounted parents. End eligibility
      # BEFORE that writer (and subsequent chmod/chown), regardless of version.
      write_phase=configuration
      ampache_identity_restore
      ampache_identity_permissions
      ampache_footprint ownership

      msg_info "Starting Service"
      write_phase=activation
      systemctl start apache2
      write_phase=retirement
      ampache_identity_retire
      msg_ok "Started Service"
    )
    msg_ok "Updated successfully!"
    get_lxc_ip
    local host="$LOCAL_IP"
    [[ "$host" != *:* ]] || host="[$host]"
    msg_info "Complete database update by visiting: http://${host}/update.php"
  else
    local status=$?
    [[ "$status" == 1 ]] || return "$status"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc") --script-id "ampache" -- "$@"
