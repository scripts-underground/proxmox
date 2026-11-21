#!/usr/bin/env bash
# runtime-hooks-contract: lxc start-on-success
# shellcheck disable=SC2034,SC2154
# Cold generated bundles and real archives/files; Java and service control modeled.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=apache-tomcat
script_type=lxc
variants=(fresh override update current pending index empty download extract mismatch ambiguous copy stopped rollback cleanup start)
hook_paths=(/tmp tmp)

runtime_hooks_variant() {
  case "$variant" in index | empty | extract | mismatch | ambiguous | rollback | cleanup | start) fault=$variant ;; stopped) fault=copy ;; esac
  [[ "$variant" != override ]] || role=install
}
runtime_hooks_model() {
  apt() { :; }
  setup_java() { printf '%s\n' "$JAVA_VERSION" > "$c/java-version"; }
  get_system_arch() { printf amd64; }
  curl() {
    local out='' url=''
    while (($#)); do
      case "$1" in
        -o)
          out=$2
          shift
          ;;
        https:*) url=$1 ;;
      esac
      shift
    done
    if [[ "$url" == */tomcat-"$(cat "$c/major")"/ ]]; then
      [[ "$APP_FAULT" != index ]] || return 28
      if [[ "$APP_FAULT" == empty ]]; then
        printf '<html>no releases</html>\n'
      else
        printf '<a href="v%s/">release</a>\n' "$(cat "$c/target-version")"
      fi
    else
      [[ "$APP_FAULT" != download ]] || return 22
      if [[ "$APP_FAULT" == extract ]]; then
        # A truncated distribution must never replace live files.
        tar -czf "$out" -C "$c" payload
        truncate -s 64 "$out"
      elif [[ "$APP_FAULT" == mismatch ]]; then
        # A milestone header must not satisfy the selected stable release.
        mkdir -p "$c/mismatch"
        command cp -a "$c/payload" "$c/mismatch/"
        printf 'Apache Tomcat Version %s-M1\n' "$(cat "$c/target-version")" > "$c/mismatch/payload/RELEASE-NOTES"
        tar -czf "$out" -C "$c/mismatch" payload
      else
        tar -czf "$out" -C "$c" payload
      fi
    fi
  }
  systemctl() {
    [[ "$1" != start || "$APP_FAULT" != start ]] || return 51
    if [[ -f "$c/recovery-service" ]]; then
      runtime_hooks_recovery_service "$@" || return
    else
      printf '%s\n' "$*" >> "$c/services"
    fi
    if [[ "$1" == start || "$*" == *--now* ]]; then
      "/opt/tomcat-$(cat "$c/major")/bin/catalina.sh" > "$c/started-version"
    fi
  }
  # Live-copy failure as in the shared copy model; rollback also loses its restore.
  cp() {
    if [[ ("$APP_FAULT" == copy || "$APP_FAULT" == rollback) && "${!#}" == /opt/* && "$*" == *'/deploy-source.'* ]]; then
      command cp -a -- "$3" "${!#}"
      return 41
    fi
    command cp "$@"
  }
  mv() {
    [[ "$APP_FAULT" != rollback || "$1" != -n ]] || return 1
    command mv "$@"
  }
  rm() {
    [[ "$APP_FAULT" != cleanup || $# != 3 || "$1" != -rf || "$3" != */tomcat-update.* || "$3" == */tomcat-update.*/* ]] || return 1
    command rm "$@"
  }
}
runtime_hooks_setup() {
  local target_version=11.0.29 major=11 java=21
  if [[ "$variant" == override ]]; then
    target_version=10.1.48 major=10 java=17
    printf 'TOMCAT_VERSION=10\nJAVA_VERSION=17\n' > "$c/context.sh"
  fi
  printf '%s\n' "$target_version" > "$c/target-version"
  printf '%s\n' "$major" > "$c/major"
  printf '%s\n' "$java" > "$c/expected-java"
  mkdir -p "$c/payload/"{bin,lib,conf,webapps,logs,work,temp}
  printf '#!/bin/sh\nprintf "consumer-%s\\n"\n' "$target_version" > "$c/payload/bin/catalina.sh"
  chmod 0755 "$c/payload/bin/catalina.sh"
  printf 'Apache Tomcat Version %s\n' "$target_version" > "$c/payload/RELEASE-NOTES"
  printf 'new runtime jar\n' > "$c/payload/lib/catalina.jar"
  printf 'archive default\n' > "$c/payload/conf/server.xml"
  if [[ "$role" == update ]]; then
    mkdir -p "$c/opt/tomcat-11/"{bin,lib,conf,webapps,logs,work,temp}
    printf '#!/bin/sh\nprintf "consumer-11.0.28\\n"\n' > "$c/opt/tomcat-11/bin/catalina.sh"
    chmod 0755 "$c/opt/tomcat-11/bin/catalina.sh"
    printf 'Apache Tomcat Version 11.0.28\n' > "$c/opt/tomcat-11/RELEASE-NOTES"
    printf 'old runtime jar\n' > "$c/opt/tomcat-11/lib/catalina.jar"
    for path in conf/server.xml webapps/proof.jsp logs/operator.log work/application-state temp/application-state lib/custom.jar bin/setenv.sh; do
      printf 'USER %s\n' "$path" > "$c/opt/tomcat-11/$path"
    done
    chmod 0640 "$c/opt/tomcat-11/bin/setenv.sh"
    if [[ "$variant" == current || "$variant" == pending ]]; then
      cp "$c/payload/RELEASE-NOTES" "$c/opt/tomcat-11/RELEASE-NOTES"
      cp "$c/payload/bin/catalina.sh" "$c/opt/tomcat-11/bin/catalina.sh"
      cp "$c/payload/lib/catalina.jar" "$c/opt/tomcat-11/lib/catalina.jar"
    fi
    if [[ "$variant" == pending ]]; then
      printf 'interrupted repair\n' > "$c/state/$app"
      rm "$c/opt/tomcat-11/bin/catalina.sh"
    fi
    local initial=active
    [[ "$variant" != stopped ]] || initial=inactive
    runtime_hooks_recovery_setup tomcat "$initial" "$c/opt/tomcat-11"
    if [[ "$variant" == ambiguous ]]; then
      mkdir -p "$c/opt/tomcat-10/bin"
      printf 'Apache Tomcat Version 10.1.48\n' > "$c/opt/tomcat-10/RELEASE-NOTES"
    fi
  fi
}
runtime_hooks_expected() {
  case "$fault" in index) expected=28 ;; empty | mismatch | ambiguous) expected=65 ;; extract) expected=251 ;; rollback) expected=252 ;; start) expected=51 ;; esac
}
runtime_hooks_assert() {
  if [[ "$role" == install && "$rc" == 0 ]]; then
    check "$(cat "$c/java-version")" "$(cat "$c/expected-java")" "$app/$variant Java selection crosses bundle boundary"
    check "$("$c/opt/tomcat-$(cat "$c/major")/bin/catalina.sh")" "consumer-$(cat "$c/target-version")" "$app/$variant executable consumer"
  fi
  if [[ "$role" == update ]]; then
    for path in conf/server.xml webapps/proof.jsp logs/operator.log work/application-state temp/application-state lib/custom.jar bin/setenv.sh; do
      check "$(cat "$c/opt/tomcat-11/$path" 2> /dev/null || true)" "USER $path" "$app/$variant preserves $path"
    done
    check "$(stat -c %a "$c/opt/tomcat-11/bin/setenv.sh" 2> /dev/null || true)" 640 "$app/$variant preserves operator metadata"
    if [[ "$rc" == 0 ]]; then
      check "$("$c/opt/tomcat-11/bin/catalina.sh" 2> /dev/null || true)" consumer-11.0.29 "$app/$variant final executable consumer"
      check "$(cat "$c/opt/tomcat-11/lib/catalina.jar")" 'new runtime jar' "$app/$variant distribution library upgraded"
      if [[ "$variant" == current ]]; then
        check "$(grep -Ec '^(stop|start|restart) ' "$c/services" || true)" 0 "$app/$variant current release neither stops nor starts the service"
      else
        check "$(cat "$c/started-version" 2> /dev/null || true)" consumer-11.0.29 "$app/$variant service starts the deployed runtime"
        check "$(cat "$c/recovery-state")" active "$app/$variant service active after update"
      fi
    fi
    case "$fault" in
      index | empty | download | extract | mismatch | ambiguous | copy)
        check "$("$c/opt/tomcat-11/bin/catalina.sh" 2> /dev/null || true)" consumer-11.0.28 "$app/$variant failed preparation preserves old consumer"
        if [[ "$fault" != copy ]]; then
          check "$(grep -c '^stop ' "$c/services" || true)" 0 "$app/$variant failed preparation does not stop listener"
        fi
        ;;
    esac
    case "$variant" in
      copy) check "$(cat "$c/started-version" 2> /dev/null || true)" consumer-11.0.28 "$app/$variant verified rollback restarts the old runtime" ;;
      stopped | rollback) check "$(test -f "$c/started-version" && printf started || printf none)" none "$app/$variant failed update leaves Tomcat stopped" ;;
      cleanup) check "$(grep -c 'Unable to remove Tomcat staging directory' "$c/output" || true)" 1 "$app/$variant reports staging cleanup failure" ;;
    esac
    # The retry assertion observes only the retry's own service start.
    rm -f -- "$c/started-version"
  fi
}
runtime_hooks_retry_needed() { [[ "$role" == update && "$expected" != 0 && "$variant" != ambiguous ]]; }
runtime_hooks_retry_assert() {
  check "$("$c/opt/tomcat-11/bin/catalina.sh")" consumer-11.0.29 "$app/$variant pending retry consumer"
  check "$(cat "$c/started-version" 2> /dev/null || true)" consumer-11.0.29 "$app/$variant pending retry starts the deployed runtime"
}
runtime_hooks_main "$@"
