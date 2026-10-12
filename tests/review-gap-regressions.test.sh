#!/usr/bin/env bash
# Tests only: execute the pinned implementation, delegate actual command faults.
set -euo pipefail
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
# shellcheck source=tests/lib/safety-gap-common.sh
source "$ROOT/tests/lib/safety-gap-common.sh"

review_call() {
  local label=$1 rc
  export SG_INVOCATION="$label" SG_OBSERVE_ACTIVE=1
  if [[ "$SG_ID" == K4 && "$SG_SCENARIO" == input-store-alias ]]; then
    if _codeberg_deploy_tree "$KR/source/app" "$SG_TARGET"; then rc=0; else rc=$?; fi
  elif fetch_and_deploy_codeberg_release "$SG_APP" safety/review tarball latest "$SG_TARGET"; then rc=0; else rc=$?; fi
  printf '%s\n' "$rc" > "$KR/$label-status.txt"
  sg_snapshot "$KR/$label-consumers.json" "target=$SG_TARGET" "marker=$HOME/.$SG_APP"
  sg_review_capture "$SG_SCENARIO-$label" "$SG_TARGET/payload" "$HOME/.$SG_APP" > "$KR/$label-capture.txt"
  export SG_OBSERVE_ACTIVE=0
}

review_journal() {
  python3 - "$KR/seed-capture.txt" << 'PY'
import json,pathlib,sys
receipt=json.loads(pathlib.Path(pathlib.Path(sys.argv[1]).read_text().strip()).read_text())
own=[item for item in receipt['journals'] if json.loads((pathlib.Path(item['snapshot'])/'manifest.json').read_text())['target']==receipt['target']]
assert len(own)==1
print(own[0]['path'])
PY
}

review_active_lock() {
  python3 - "$BASHPID" << 'PY'
import json,os,pathlib,subprocess,sys
owner=int(sys.argv[1]); root=pathlib.Path(os.environ['KR']); lock=pathlib.Path('/var/lib/scripts-underground/release-deploy/lock')
identity=pathlib.Path(f'/proc/{owner}/cmdline').read_bytes().replace(b'\0',b' ').decode()
environment=dict(part.split(b'=',1) for part in pathlib.Path(f'/proc/{owner}/environ').read_bytes().split(b'\0') if b'=' in part)
assert os.getpgid(owner)==os.getpgrp()
assert 'review-gap-regressions.test.sh --variant benign-owner' in identity
assert environment[b'SG_CASE'].decode()==os.environ['SG_CASE']
result=subprocess.run(['/usr/bin/flock','--exclusive','--nonblock','--conflict-exit-code','79',str(lock),'true'],close_fds=True)
(root/'active-lock-barrier.json').write_text(json.dumps({'owner_pid':owner,'pgid':os.getpgid(owner),'identity':identity,'contender_status':result.returncode,'lock_inode':lock.stat().st_ino})+'\n')
PY
}

review_copy_fault_capture() {
  python3 - "$1" "$2" "$3" << 'PY'
import hashlib,json,os,pathlib,sys
root=pathlib.Path(os.environ['KR']); source=pathlib.Path(sys.argv[1]); path=pathlib.Path(sys.argv[2]); data=path.read_bytes(); st=path.lstat()
index=len(list(root.glob('copy-fault-*.json'))); prefix=root/f'copy-fault-{index}'
prefix.with_suffix('.bin').write_bytes(data)
record={'source':str(source),'path':str(path),'copy_status':int(sys.argv[3]),'size':len(data),'sha256':hashlib.sha256(data).hexdigest(),
 'prefix_matches':source.read_bytes()[:len(data)]==data,'identity':f'{st.st_dev}:{st.st_ino}:{st.st_nlink}','mode':st.st_mode&0o7777,
 'xattrs':{key:os.getxattr(path,key).hex() for key in os.listxattr(path)}}
prefix.with_suffix('.json').write_text(json.dumps(record,indent=2)+'\n')
PY
}

review_faults() {
  jq() {
    local query="${*: -2:1}" file="${*: -1}"
    if [[ "${SG_FAULT:-none}" == commit-producer && "$*" == *'--arg state COMMITTED'* && "$*" == *'state:$state'* ]]; then
      if [[ "${SG_PRODUCER_OUTPUT:-0}" == 1 ]]; then
        command jq "$@" > "$KR/producer-output.json" || return "$?"
        command cat "$KR/producer-output.json" || return "$?"
      fi
      sg_review_fault commit-producer jq "$@" status=99
      return 99
    elif [[ "${SG_FAULT:-none}" == mount-writer && "$*" == *'sort_by(.id)'* && "$file" == */mounts.json.lines ]]; then
      sg_review_fault mount-writer jq "$@" status=99
      return 99
    elif [[ "${SG_FAULT:-none}" == manifest-writer && "$*" == *'root_identity:$identity'* ]]; then
      sg_review_fault manifest-writer jq "$@" status=99
      return 99
    elif [[ "${SG_FAULT:-none}" == state-producer && "$*" == *'--arg state PREPARING'* && "$*" == *'state:$state'* ]]; then
      sg_review_fault state-producer jq "$@" status=99
      return 99
    elif [[ "${SG_FAULT:-none}" == plan-producer && "$file" == */plan.lines && "$*" == *'sort_by('* ]]; then
      sg_review_fault plan-producer jq "$@" status=99
      return 99
    elif [[ "${SG_FAULT:-none}" == *reader && -f "$KR/payload-published" ]]; then
      if [[ "$SG_FAULT" == rollback-reader && "$query" == 'reverse[]' && "$file" == */plan.json ]] ||
        [[ "$SG_FAULT" == verify-plan-reader && "$query" == '.[]' && "$file" == */plan.json ]] ||
        [[ "$SG_FAULT" == verify-alias-reader && "$query" == '.[]' && "$file" == */aliases.json ]]; then
        if [[ "$SG_SCENARIO" == changed-plan ]]; then
          printf 'external changed payload\n' > "$SG_TARGET/payload"
          sg_review_fault controlled-external-edit "$SG_TARGET/payload"
        fi
        if [[ "${SG_READER_PREFIX:-0}" == 1 ]]; then
          command jq -c "first($query)" "$file" > "$KR/reader-prefix-output.json" || return "$?"
          command cat "$KR/reader-prefix-output.json" || return "$?"
        fi
        sg_review_fault "$SG_FAULT" jq "$@" status=99
        return 99
      fi
    fi
    command jq "$@"
  }
  cp() {
    local from="${*: -2:1}" to="${*: -1}" actual_status
    if [[ "${SG_FAULT:-none}" == seed-recovery && "$to" == */restore && -f "$from" && "$(< "$from")" == 1.0.0 ]]; then
      sg_review_fault marker-restore cp "$@" status=1
      return 1
    elif [[ "${SG_FAULT:-none}" == seed-prepared && "$to" == */restore && -f "$from" && "$(< "$from")" == 'old payload' ]]; then
      sg_review_fault payload-restore cp "$@" status=1
      return 1
    elif [[ "${SG_FAULT:-none}" == publish-copy && "$to" == */publish ]] ||
      [[ "${SG_FAULT:-none}" == restore-copy && "$to" == */restore ]]; then
      command cp "$@" || return "$?"
      review_copy_fault_capture "$from" "$to" 1
      sg_review_fault copy-after-real-candidate cp "$@" status=1
      return 1
    elif [[ "$SG_ID" == K9 && "$SG_SCENARIO" == restore-conflict && "$to" == */restore && "$(< "$from")" == 'original nested' ]]; then
      command cp "$@" || return "$?"
      printf 'foreign restore bytes\n' >> "$to"
      review_copy_fault_capture "$from" "$to" 1
      sg_review_fault directory-child-restore-conflict cp "$@" status=1
      return 1
    elif [[ "$SG_ID" == K7 && "$to" == */publish && "$SG_FAULT" != none ]]; then
      if [[ "$SG_SCENARIO" == zero-copy ]]; then
        review_copy_fault_capture "$from" "$to" 1
        sg_review_fault zero-byte-copy cp "$@" status=1
        return 1
      elif [[ "$SG_SCENARIO" == partial-copy ]]; then
        if command cp "$@"; then return 0; else actual_status=$?; fi
        review_copy_fault_capture "$from" "$to" "$actual_status"
        sg_review_fault native-partial-copy cp "$@" status="$actual_status"
        return "$actual_status"
      elif [[ "$SG_SCENARIO" == conflict-* ]]; then
        command cp "$@" || return "$?"
        case "$SG_SCENARIO" in
          conflict-bytes) printf 'foreign bytes\n' >> "$to" ;;
          conflict-mode) chmod 700 "$to" ;;
          conflict-xattr) setfattr -n user.foreign -v foreign "$to" ;;
          conflict-acl) setfacl -m u:65534:r--,m::--- "$to" ;;
          conflict-inode)
            command cp -P --preserve=all "$to" "$KR/foreign-inode"
            command mv -T "$KR/foreign-inode" "$to"
            ;;
          conflict-hardlink) ln "$to" "$KR/foreign-hardlink" ;;
        esac
        review_copy_fault_capture "$from" "$to" 1
        sg_review_fault external-candidate-conflict cp "$@" status=1
        return 1
      fi
    fi
    command cp "$@"
  }
  mv() {
    local from="${*: -2:1}" to="${*: -1}"
    if [[ "${SG_FAULT:-none}" == aliases-publication && "$to" == */aliases.json ]]; then
      sg_review_fault aliases-publication mv "$@" status=1
      return 1
    elif [[ "${SG_FAULT:-none}" == bootstrap-publication && "${from##*/}" == init-* && "${to##*/}" == txn-* ]]; then
      command mv "$@" || return "$?"
      sg_review_fault bootstrap-renamed-then-error mv "$@" status=1
      return 1
    fi
    if [[ "$from" == */publish && "$to" == "$HOME/.$SG_APP" && ("${SG_FAULT:-none}" == marker-fail || "${SG_FAULT:-none}" == restore-copy || "${SG_FAULT:-none}" == rollback-reader) ]]; then
      sg_review_fault marker-publication mv "$@" status=1
      return 1
    fi
    command mv "$@" || return "$?"
    if [[ "$SG_ID" == K4 && "$SG_SCENARIO" == benign-owner && "$to" == */state.json && "$(command jq -r .state "$to")" == APPLYING ]]; then
      review_active_lock
    fi
    if [[ "$from" == */publish ]]; then
      if [[ "$to" == "$SG_TARGET/payload" ]]; then printf 'real payload publication\n' > "$KR/payload-published"; fi
      if [[ "${SG_FAULT:-none}" == seed-recovery && "$to" == "$HOME/.$SG_APP" ]]; then
        sg_review_fault marker-renamed-then-error mv "$@" status=1
        return 1
      fi
      if [[ "${SG_FAULT:-none}" == seed-prepared && "$to" == "$SG_TARGET/payload" ]]; then
        sg_review_fault payload-renamed-then-error mv "$@" status=1
        return 1
      fi
      if [[ "$SG_ID" == K4 && "$to" == "$SG_TARGET/store/lock" ]]; then
        python3 - "$BASHPID" << 'PY'
import json,os,pathlib,subprocess,sys
owner=int(sys.argv[1]); root=pathlib.Path(os.environ['KR']); lock=pathlib.Path('/var/lib/scripts-underground/release-deploy/lock')
identity=pathlib.Path(f'/proc/{owner}/cmdline').read_bytes().replace(b'\0',b' ').decode()
environment=dict(part.split(b'=',1) for part in pathlib.Path(f'/proc/{owner}/environ').read_bytes().split(b'\0') if b'=' in part)
assert os.getpgid(owner)==os.getpgrp()
assert 'review-gap-regressions.test.sh --variant store-bind' in identity
assert environment[b'SG_CASE'].decode()==os.environ['SG_CASE']
result=subprocess.run(['/usr/bin/flock','--exclusive','--nonblock','--conflict-exit-code','79',str(lock),'true'],close_fds=True)
(root/'active-lock-barrier.json').write_text(json.dumps({'owner_pid':owner,'pgid':os.getpgid(owner),'identity':identity,'contender_status':result.returncode,'lock_inode':lock.stat().st_ino})+'\n')
PY
      fi
    fi
  }
}

variant_main() {
  export SG_SCENARIO=$1 KR="$SG_CASE/fs/$1" SG_TARGET="$SG_CASE/fs/$1/target"
  export HOME="$KR/home" SG_APP="review-${SG_ID,,}-$1" SG_INVOCATION=setup SG_FAULT=none SG_OBSERVE_ACTIVE=0
  export SG_PRODUCER_OUTPUT=0 SG_READER_PREFIX=0
  mkdir "$KR" "$KR/home" "$KR/target" "$KR/source" "$KR/source/app" "$KR/lib" "$KR/bin" "$KR/cache"
  mkdir "$KR/lib/dpkg"
  cp -P /var/lib/dpkg/status "$KR/lib/dpkg/status"
  mount --bind "$KR/lib" /var/lib
  mount --bind "$KR/bin" /usr/local/bin
  mount --bind "$KR/cache" /var/cache
  printf 'old payload\n' > "$SG_TARGET/payload"
  printf 'custom sentinel\n' > "$SG_TARGET/custom"
  printf '1.0.0\n' > "$HOME/.$SG_APP"
  printf 'incoming payload\n' > "$KR/source/app/payload"
  printf 'incoming README\n' > "$KR/source/app/README"
  sg_load
  python3 - "$BASHPID" << 'PY'
import json,os,pathlib,sys
root=pathlib.Path(os.environ['KR']); pid=int(sys.argv[1]); parent=json.loads((pathlib.Path(os.environ['SG_CASE'])/'worker-context.json').read_text())
assert os.readlink('/proc/self/ns/mnt')!=parent['mntns']
record={'pid':pid,'pgid':os.getpgid(pid),'mntns':os.readlink('/proc/self/ns/mnt'),'enclosing_pgid':parent['pgid'],
 'case':os.environ['SG_ID'],'variant':os.environ['SG_SCENARIO'],'manifest_sha256':os.environ['SG_MANIFEST_SHA256']}
(root/'variant-context.json').write_text(json.dumps(record,indent=2)+'\n')
PY
  export SG_OBSERVE_ACTIVE=0
  review_faults
  export CLEAN_INSTALL=0
  case "$SG_ID" in
    K1)
      if [[ "$SG_SCENARIO" == *off ]]; then set +o pipefail; else set -o pipefail; fi
      set -o > "$KR/caller-options.txt"
      if [[ "$SG_SCENARIO" == commit-* ]]; then SG_FAULT=commit-producer; fi
      [[ "$SG_SCENARIO" != commit-output-* ]] || SG_PRODUCER_OUTPUT=1
      ;;
    K4)
      mkdir -m 700 /var/lib/scripts-underground /var/lib/scripts-underground/release-deploy
      printf 'stable lock\n' > /var/lib/scripts-underground/release-deploy/lock
      printf 'retained canary\n' > /var/lib/scripts-underground/release-deploy/canary
      if [[ "$SG_SCENARIO" == store-descendant ]]; then
        mkdir "$SG_TARGET/shared" "$KR/source/app/shared" /var/lib/scripts-underground/release-deploy/linked
        printf 'old store-region leaf\n' > "$SG_TARGET/shared/lock"
        mount --bind "$SG_TARGET/shared" /var/lib/scripts-underground/release-deploy/linked
        printf 'incoming store-region leaf\n' > "$KR/source/app/shared/lock"
      elif [[ "$SG_SCENARIO" == input-store-alias ]]; then
        mkdir "$KR/source/app/store"
        mount --bind /var/lib/scripts-underground/release-deploy "$KR/source/app/store"
      elif [[ "$SG_SCENARIO" != benign-owner ]]; then
        mkdir "$SG_TARGET/store" "$KR/source/app/store"
        if [[ "$SG_SCENARIO" == stacked-store-bind ]]; then
          mkdir "$KR/covered"
          mount --bind "$KR/covered" "$SG_TARGET/store"
        fi
        mount --bind /var/lib/scripts-underground/release-deploy "$SG_TARGET/store"
        printf 'incoming lock\n' > "$KR/source/app/store/lock"
      fi
      stat -Lc '%d:%i' /var/lib/scripts-underground/release-deploy/lock > "$KR/lock-before.txt"
      findmnt --kernel --json --output TARGET,SOURCE,FSROOT,MAJ:MIN > "$KR/mount-origins.json"
      ;;
    K3)
      if [[ "$SG_SCENARIO" == prepared-metadata ]]; then
        printf 'unentered original\n' > "$SG_TARGET/zz-late"
        printf 'unentered incoming\n' > "$KR/source/app/zz-late"
      fi
      ;;
    K5)
      if [[ "$SG_SCENARIO" == overlap ]]; then
        mkdir -m 700 /var/lib/scripts-underground /var/lib/scripts-underground/release-deploy
        export SG_TARGET=/var/lib/scripts-underground/release-deploy/installed
        mkdir "$SG_TARGET"
        printf 'old payload\n' > "$SG_TARGET/payload"
      else SG_FAULT="$SG_SCENARIO"; fi
      ;;
    K6)
      mkdir "$KR/source/app/newdir"
      printf 'new leaf\n' > "$KR/source/app/newdir/leaf"
      [[ "$SG_SCENARIO" != absent-root ]] || rmdir "$SG_TARGET" 2> /dev/null || {
        rm "$SG_TARGET/payload" "$SG_TARGET/custom"
        rmdir "$SG_TARGET"
      }
      SG_FAULT=marker-fail
      ;;
    K7)
      SG_FAULT="$SG_SCENARIO"
      if [[ "$SG_SCENARIO" == partial-copy ]]; then
        mkdir "$KR/tmpfs-seed"
        command cp -PR --preserve=mode,ownership,timestamps,xattr "$SG_TARGET/." "$KR/tmpfs-seed/"
        mount -t tmpfs -o size=128k tmpfs "$SG_TARGET"
        command cp -PR --preserve=mode,ownership,timestamps,xattr "$KR/tmpfs-seed/." "$SG_TARGET/"
        python3 - "$KR/source/app/payload" << 'PY'
import pathlib,sys
pathlib.Path(sys.argv[1]).write_bytes(b'A'*1048576)
PY
      fi
      ;;
    K8)
      mkdir "$SG_TARGET/parent" "$KR/native-parent" "$KR/source/app/parent" "$KR/source/app/parent/newdir"
      chown 0:65534 "$SG_TARGET/parent" "$KR/native-parent"
      chmod 2775 "$SG_TARGET/parent" "$KR/native-parent"
      if [[ "$SG_SCENARIO" == default-acl ]]; then
        setfacl -m u:65534:rwx,d:u:65534:r-x "$SG_TARGET/parent" "$KR/native-parent"
      fi
      mkdir -m 755 "$KR/native-parent/newdir"
      stat -c '%a:%u:%g' "$KR/native-parent/newdir" > "$KR/native-mkdir.txt"
      python3 - "$KR/native-parent/newdir" "$KR/native-directory.json" << 'PY'
import json,os,pathlib,sys
sys.path.insert(0,os.environ['SG_REVIEW_SUPPORT'])
from probe import point
pathlib.Path(sys.argv[2]).write_text(json.dumps(point(sys.argv[1]),indent=2)+'\n')
PY
      printf 'new leaf\n' > "$KR/source/app/parent/newdir/leaf"
      ;;
    K9)
      mkdir "$SG_TARGET/obsolete" "$SG_TARGET/obsolete/nested"
      printf 'original nested\n' > "$SG_TARGET/obsolete/nested/.leaf"
      if [[ "$SG_SCENARIO" == inherited-extras ]]; then
        chown 0:65534 "$SG_TARGET"
        chmod 2775 "$SG_TARGET"
        setfacl -m d:u:65534:r-x "$SG_TARGET"
      else
        setfacl -m u:65534:rwx,d:u:65534:r-x "$SG_TARGET/obsolete/nested"
      fi
      python3 - "$SG_TARGET/obsolete/nested" << 'PY'
import os,sys
os.setxattr(sys.argv[1],'user.review-metadata',b'original-xattr')
for i,name in enumerate(['user.back\\slash','user.line\nname','user.return\rname','user.equal=name']):
 os.setxattr(sys.argv[1],name,bytes([0,i,255])+b'original\0binary')
PY
      getfacl -cpn "$SG_TARGET/obsolete/nested" > "$KR/acl-before.txt"
      export CLEAN_INSTALL=1 SG_FAULT=marker-fail
      ;;
    K10)
      printf 'old referent\n' > "$SG_TARGET/value"
      if [[ "$SG_SCENARIO" == deep-nested ]]; then
        mkdir "$SG_TARGET/nested" "$SG_TARGET/nested/deeper"
        ln -s ../../value "$SG_TARGET/nested/deeper/intermediate"
        ln -s nested/deeper/intermediate "$SG_TARGET/alias"
        printf 'eligible obsolete sibling\n' > "$SG_TARGET/nested/deeper/obsolete"
      elif [[ "$SG_SCENARIO" == nested ]]; then
        mkdir "$SG_TARGET/nested"
        ln -s ../value "$SG_TARGET/nested/intermediate"
        ln -s nested/intermediate "$SG_TARGET/alias"
      else
        ln -s value "$SG_TARGET/intermediate"
        ln -s intermediate "$SG_TARGET/alias"
      fi
      printf 'incoming referent\n' > "$KR/source/app/alias"
      export CLEAN_INSTALL=1
      ;;
    K11)
      mkdir "$KR/project"
      python3 - << 'PY'
import io,json,os,pathlib,tarfile,tomllib
root=pathlib.Path(os.environ['KR']); variant=os.environ['SG_SCENARIO']
standalone=variant.startswith('uv-')
text=('' if standalone else '[tool.uv]\n')+'required-version = "==0.12.13"\n'
if variant.endswith('crlf'): text=text.replace('\n','\r\n')
path=root/'project'/('uv.toml' if standalone else 'pyproject.toml'); path.write_bytes(text.encode())
parsed=tomllib.loads(path.read_bytes().decode()); pin=parsed['required-version'] if standalone else parsed['tool']['uv']['required-version']
(root/'oracle.json').write_text(json.dumps({'effective':pin,'expected':'0.12.13','input_sha256':__import__('hashlib').sha256(path.read_bytes()).hexdigest()})+'\n')
for version in ['0.12.13','0.12.22']:
    program=f'#!/bin/sh\nif [ "$1" = "--version" ]; then printf "uv {version}\\n"; exit 0; fi\nprintf "# completion\\n"\n'.encode()
    with tarfile.open(root/f'uv-{version}.tar.gz','w:gz') as archive:
        entry=tarfile.TarInfo('uv-fixture/uv'); entry.mode=0o755; entry.size=len(program); archive.addfile(entry,io.BytesIO(program))
PY
      sg_release_routes github astral-sh/uv 0.12.13 "$KR/uv-0.12.13.tar.gz" uv-x86_64-unknown-linux-gnu.tar.gz prebuild
      sg_release_routes github astral-sh/uv 0.12.22 "$KR/uv-0.12.22.tar.gz" uv-x86_64-unknown-linux-gnu.tar.gz prebuild
      ;;
    K12)
      python3 - << 'PY'
import json,os,pathlib,urllib.parse
root=pathlib.Path(os.environ['KR']); variant=os.environ['SG_SCENARIO']; requested='vérsion/2' if variant.startswith('unicode') else 'version/2' if variant.startswith('raw') else '1.0.0'
suffix='\n\n' if variant.endswith('newline') else ' ' if variant.endswith('space') else '\t' if variant.endswith('tab') else '\x01' if variant.endswith('control') else ''
tag=requested+suffix
routes=pathlib.Path(os.environ['SG_ROUTES']); data=json.loads(routes.read_text())
data['https://codeberg.org/api/v1/repos/safety/pins/releases/tags/'+urllib.parse.quote(requested,safe='')]={'json':{'draft':False,'prerelease':False,'tag_name':tag,'assets':[]}}
routes.write_text(json.dumps(data)+'\n'); (root/'tag-oracle.json').write_text(json.dumps({'requested':requested,'raw_metadata':tag,'equivalent':requested==tag})+'\n'); (root/'requested.txt').write_text(requested)
PY
      printf '0.0.0\n' > "$HOME/.$SG_APP"
      ;;
    K13) [[ "$SG_SCENARIO" != rollback ]] || SG_FAULT=marker-fail ;;
    K15)
      case "$SG_SCENARIO" in
        control) ;;
        alias-reader) SG_FAULT=verify-alias-reader ;;
        rollback-reader | rollback-partial) SG_FAULT=rollback-reader ;;
        *) SG_FAULT=verify-plan-reader ;;
      esac
      [[ "$SG_SCENARIO" != *-partial ]] || SG_READER_PREFIX=1
      ;;
  esac
  tar -czf "$KR/release.tar.gz" -C "$KR/source" app
  sg_release_routes codeberg safety/review v2.0.0 "$KR/release.tar.gz" '' tarball
  sg_snapshot "$KR/before.json" "target=$SG_TARGET" "marker=$HOME/.$SG_APP"
  sg_review_capture "$SG_SCENARIO-before" "$SG_TARGET/payload" "$HOME/.$SG_APP" "$SG_TARGET/obsolete/nested" > "$KR/before-capture.txt"
  if [[ "$SG_ID" == K1 && "$SG_SCENARIO" != commit-* ]]; then
    mkdir "$KR/writer"
    printf '{"schema":1,"state":"PREPARED"}\n' > "$KR/writer/record.json"
    command cp "$KR/writer/record.json" "$KR/writer/original.json"
    export SG_OBSERVE_ACTIVE=1 SG_INVOCATION=writer
    if [[ "$SG_SCENARIO" == empty-* ]]; then
      printf '' > "$KR/writer/input"
    elif [[ "$SG_SCENARIO" == multiple-* ]]; then
      printf '{"schema":1,"state":"APPLIED"}\n{"schema":1,"state":"RESTORED"}\n' > "$KR/writer/input"
    elif [[ "$SG_SCENARIO" == truncated-* ]]; then
      printf '{"schema":1,"state":"APPLIED"' > "$KR/writer/input"
    else printf '{"schema":1,"state":"APPLIED"}\n' > "$KR/writer/input"; fi
    if _release_tx_write_json "$KR/writer/record.json" < "$KR/writer/input"; then rc=0; else rc=$?; fi
    printf '%s\n' "$rc" > "$KR/main-status.txt"
  elif [[ "$SG_ID" == K2 || "$SG_ID" == K3 ]]; then
    SG_FAULT=seed-recovery
    [[ "$SG_SCENARIO" != prepared-metadata ]] || SG_FAULT=seed-prepared
    review_call seed
    transaction=$(review_journal)
    printf '%s\n' "$transaction" > "$KR/seed-transaction.txt"
    if [[ "$SG_ID" == K2 ]]; then
      marker_id=$(command jq -r '.[] | select(.action=="marker") | .id' "$transaction/plan.json")
      payload_id=$(command jq -r --arg path "$SG_TARGET/payload" '.[] | select(.path==$path) | .id' "$transaction/plan.json")
      case "$SG_SCENARIO" in
        missing-plan | duplicate-destination)
          command cp "$transaction/plan.json" "$KR/plan-before-tamper.json"
          if [[ "$SG_SCENARIO" == missing-plan ]]; then rm "$transaction/plan.json"; else
            command jq '.[1].path=.[0].path' "$KR/plan-before-tamper.json" > "$transaction/plan.json"
          fi
          ;;
        missing-aliases)
          command cp "$transaction/aliases.json" "$KR/aliases-before-removal.json"
          rm "$transaction/aliases.json"
          ;;
        missing-input | missing-original)
          entry=incoming
          [[ "$SG_SCENARIO" != missing-original ]] || entry=original
          command cp "$transaction/entries/$marker_id/$entry" "$KR/$entry-before-removal"
          rm "$transaction/entries/$marker_id/$entry"
          ;;
        contradictory-state)
          command cp "$transaction/state.json" "$KR/state-before-tamper.json"
          command jq '.application_started=false' "$KR/state-before-tamper.json" > "$transaction/state.json"
          ;;
        operation-hole)
          command cp "$transaction/operations/$payload_id.json" "$KR/payload-operation-before-removal.json"
          rm "$transaction/operations/$payload_id.json"
          ;;
        *)
          command cp "$transaction/operations/$marker_id.json" "$KR/marker-operation-before-tamper.json"
          if [[ "$SG_SCENARIO" == missing-marker ]]; then
            rm "$transaction/operations/$marker_id.json"
          elif [[ "$SG_SCENARIO" == operation-cardinality ]]; then
            command cat "$KR/marker-operation-before-tamper.json" "$KR/marker-operation-before-tamper.json" > "$transaction/operations/$marker_id.json"
          else printf 'deliberately corrupt operation\n' > "$transaction/operations/$marker_id.json"; fi
          ;;
      esac
    elif [[ "$SG_SCENARIO" == edited-restored ]]; then
      printf 'external edit after restoration\n' > "$SG_TARGET/payload"
      sg_review_fault edited-restored "$SG_TARGET/payload"
    elif [[ "$SG_SCENARIO" == restored-incoming ]]; then
      printf 'incoming payload\n' > "$SG_TARGET/payload"
      sg_review_fault restored-incoming "$SG_TARGET/payload"
    elif [[ "$SG_SCENARIO" == restored-metadata ]]; then
      chmod 600 "$SG_TARGET/payload"
      sg_review_fault restored-metadata "$SG_TARGET/payload"
    elif [[ "$SG_SCENARIO" == prepared-metadata ]]; then
      late_id=$(command jq -r --arg path "$SG_TARGET/zz-late" '.[] | select(.path==$path) | .id' "$transaction/plan.json")
      [[ "$(command jq -r .state "$transaction/operations/$late_id.json")" == PREPARED ]] || exit 2
      chmod 600 "$SG_TARGET/zz-late"
      sg_review_fault prepared-metadata "$SG_TARGET/zz-late"
    fi
    sg_snapshot "$KR/before-retry.json" "target=$SG_TARGET" "marker=$HOME/.$SG_APP"
    sg_review_capture "$SG_SCENARIO-damaged" "$SG_TARGET/payload" "$HOME/.$SG_APP" > "$KR/damaged-capture.txt"
    SG_FAULT=none
    review_call retry
  elif [[ "$SG_ID" == K11 ]]; then
    export UV_PROJECT_DIR="$KR/project" SG_OBSERVE_ACTIVE=1 SG_INVOCATION=main
    if _uv_required_version "$UV_PROJECT_DIR" > "$KR/parser.txt"; then rc=0; else rc=$?; fi
    printf '%s\n' "$rc" > "$KR/parser-status.txt"
    if setup_uv; then rc=0; else rc=$?; fi
    printf '%s\n' "$rc" > "$KR/main-status.txt"
    [[ ! -x /usr/local/bin/uv ]] || /usr/local/bin/uv --version > "$KR/consumer-version.txt"
    get_cached_version uv > "$KR/consumer-cache.txt" || true
  elif [[ "$SG_ID" == K12 ]]; then
    requested=$(< "$KR/requested.txt")
    export SG_INVOCATION=main
    if _codeberg_release_json safety/pins "$requested" > "$KR/selected-metadata.json"; then rc=0; else rc=$?; fi
    printf '%s\n' "$rc" > "$KR/metadata-status.txt"
    CHECK_UPDATE_RELEASE=stale-selection
    if check_for_codeberg_release "$SG_APP" safety/pins "$requested"; then rc=0; else rc=$?; fi
    printf '%s\n' "$rc" > "$KR/main-status.txt"
    printf '%s' "${CHECK_UPDATE_RELEASE:-}" > "$KR/checker-selection.txt"
  elif [[ "$SG_ID" == K14 ]]; then
    python3 "$SG_REVIEW_SUPPORT/observer-specimens.py" "$KR" "$SG_SCENARIO"
    printf '0\n' > "$KR/main-status.txt"
  else
    review_call main
    if [[ "$SG_ID" == K5 ]]; then
      SG_FAULT=none
      export SG_TARGET="$KR/followup-target"
      review_call followup
    elif [[ "$SG_ID" == K7 ]]; then
      SG_FAULT=none
      [[ "$SG_SCENARIO" != partial-copy ]] || mount -o remount,size=4m "$SG_TARGET"
      review_call retry
    fi
  fi
  export SG_OBSERVE_ACTIVE=0
  sg_snapshot "$KR/after.json" "target=$SG_TARGET" "marker=$HOME/.$SG_APP"
  sg_review_capture "$SG_SCENARIO-final" "$SG_TARGET/payload" "$HOME/.$SG_APP" "$SG_TARGET/obsolete/nested" > "$KR/final-capture.txt"
  if [[ "$SG_ID" == K4 ]]; then
    stat -Lc '%d:%i' /var/lib/scripts-underground/release-deploy/lock > "$KR/lock-after.txt"
    command cp /var/lib/scripts-underground/release-deploy/canary "$KR/canary-after.txt"
    command cp /var/lib/scripts-underground/release-deploy/lock "$KR/lock-contents-after.txt"
  elif [[ "$SG_ID" == K8 && -d "$SG_TARGET/parent/newdir" ]]; then
    stat -c '%a:%u:%g' "$SG_TARGET/parent/newdir" > "$KR/created-mkdir.txt"
    python3 - "$SG_TARGET/parent/newdir" "$KR/created-directory.json" << 'PY'
import json,os,pathlib,sys
sys.path.insert(0,os.environ['SG_REVIEW_SUPPORT'])
from probe import point
pathlib.Path(sys.argv[2]).write_text(json.dumps(point(sys.argv[1]),indent=2)+'\n')
PY
  elif [[ "$SG_ID" == K9 ]]; then
    getfacl -cpn "$SG_TARGET/obsolete/nested" > "$KR/acl-after.txt"
  elif [[ "$SG_ID" == K13 ]]; then python3 "$SG_REVIEW_SUPPORT/observer-specimens.py" "$KR" "$SG_SCENARIO"; fi
  python3 "$SG_REVIEW_SUPPORT/evaluate.py" "$SG_ID" "$KR"
}

if [[ "${1:-}" == --variant ]]; then
  variant_main "$2"
  exit 0
fi
sg_init "$@"
variants=()
case "$SG_ID" in
  K1) variants=(empty-on multiple-on writer-control-on commit-on empty-off multiple-off writer-control-off commit-off truncated-on truncated-off commit-output-on commit-output-off) ;;
  K2) variants=(missing-marker missing-plan corrupt-operation missing-aliases missing-input missing-original contradictory-state duplicate-destination operation-cardinality operation-hole) ;;
  K3) variants=(unedited-retry edited-restored restored-incoming restored-metadata prepared-metadata) ;;
  K4) variants=(store-bind stacked-store-bind store-descendant benign-owner input-store-alias) ;;
  K5) variants=(overlap mount-writer manifest-writer state-producer bootstrap-publication aliases-publication plan-producer) ;;
  K6) variants=(existing-root absent-root) ;;
  K7) variants=(publish-copy restore-copy zero-copy partial-copy conflict-bytes conflict-mode conflict-xattr conflict-acl conflict-inode conflict-hardlink) ;;
  K8) variants=(setgid-parent default-acl) ;;
  K9) variants=(acl-xattr inherited-extras restore-conflict) ;;
  K10) variants=(root-chain nested deep-nested) ;;
  K11) variants=(py-lf py-crlf uv-lf uv-crlf) ;;
  K12) variants=(numeric-normal numeric-newline raw-normal raw-newline unicode-normal unicode-newline numeric-space numeric-tab raw-control) ;;
  K13) variants=(success rollback) ;;
  K14) variants=(hardlink-damage mutation-undo no-mutation) ;;
  K15) variants=(control plan-reader alias-reader changed-plan rollback-reader plan-partial rollback-partial) ;;
  *) exit 2 ;;
esac
python3 - "${variants[@]}" << 'PY'
import json,os,pathlib,sys
(pathlib.Path(os.environ['SG_CASE'])/'review-schedule.json').write_text(json.dumps(sys.argv[1:])+'\n')
(pathlib.Path(os.environ['SG_CASE'])/'review-records.json').write_text('[]\n')
PY
python3 "$SG_REVIEW_SUPPORT/variant-supervisor.py" "${BASH_SOURCE[0]}" "${variants[@]}"
sg_review_summary "$SG_CASE/before.json" before
sg_review_summary "$SG_CASE/after.json" after
printf '0\n' > "$SG_CASE/operation-status.txt"
