#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
# Cold generated bundles and real archives/files; Java and service control modeled.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=apache-tomcat
script_type=lxc
variants=(fresh override update current pending index download extract copy start)
hook_paths=(/tmp tmp)

runtime_hooks_variant() {
  case "$variant" in index | extract | start) fault=$variant ;; esac
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
      printf '<a href="v%s/">release</a>\n' "$(cat "$c/target-version")"
    else
      [[ "$APP_FAULT" != download ]] || return 22
      if [[ "$APP_FAULT" == extract ]]; then
        # A truncated distribution must never replace live files.
        tar -czf "$out" -C "$c" payload
        truncate -s 64 "$out"
      else
        tar -czf "$out" -C "$c" payload
      fi
    fi
  }
  systemctl() {
    printf '%s\n' "$*" >> "$c/services"
    [[ "$1" != start && "$*" != *--now* ]] || {
      [[ "$APP_FAULT" != start ]] || return 51
      "/opt/tomcat-$(cat "$c/major")/bin/catalina.sh" > "$c/started-version"
    }
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
  fi
}
runtime_hooks_expected() {
  case "$fault" in index) expected=28 ;; extract) expected=251 ;; start) expected=51 ;; esac
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
    fi
    case "$fault" in
      index | download | extract | copy)
        check "$("$c/opt/tomcat-11/bin/catalina.sh" 2> /dev/null || true)" consumer-11.0.28 "$app/$variant failed preparation preserves old consumer"
        if [[ "$fault" != copy ]]; then
          check "$(grep -c '^stop ' "$c/services" || true)" 0 "$app/$variant failed preparation does not stop listener"
        fi
        ;;
    esac
  fi
}
runtime_hooks_retry_assert() {
  check "$("$c/opt/tomcat-11/bin/catalina.sh")" consumer-11.0.29 "$app/$variant pending retry consumer"
}
runtime_hooks_failure_services_assert() {
  local expected_starts=0
  [[ "$fault" != start ]] || expected_starts=1
  check "$(grep -Ec '^(start|reload|restart)|--now' "$c/services" || true)" "$expected_starts" "$app/$variant failure admits only its explicit failed-start attempt"
}
runtime_hooks_main "$@"
