#!/usr/bin/env python3
"""Guest-only differential oracle: emitted owner versus native apk in Alpine.

Invoke explicitly on the core-alpine DO guest; ordinary fixture suites do not
depend on pct. All configurations are disposable disk-backed --root fixtures.
Native exit status is not a parse-success signal: compare the complete observed
inventory AND actual HTTP requests, including the origin's resolved path.
"""
import argparse
from collections import Counter
import io
import json
import os
from pathlib import Path
import re
import subprocess
import tarfile
import threading
from types import SimpleNamespace
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote


I2 = "/x86_64/APKINDEX.tar.gz"
I3 = "/x86_64/Packages.adb"
MAIN = "etc/apk/repositories"
ETC = "etc/apk/repositories.d/"
LIB = "lib/apk/repositories.d/"
PIN = "/alpine/v3.23/main"
URL = "@ORIGIN@" + PIN


def cases():
    """Explicit native inventory and deliberate admission policy per row."""
    rows = []

    def row(name, text, paths, policy=0, files=None, resolved=None):
        rows.append(dict(name=name, files={MAIN: text, **(files or {})},
                         expected=paths, policy=policy, resolved=resolved))

    row("plain", URL + "\n", [PIN + I2])
    row("components", "@ORIGIN@/alpine/v3.23 main community\n",
        [PIN + I2, "/alpine/v3.23/community" + I2])
    row("literal-dollar-url", "@ORIGIN@/vendor/p$ss\n", ["/vendor/p$ss" + I2])
    row("literal-dollar-set", "set key=p$ss\n@ORIGIN@/vendor/${key}\n", ["/vendor/p$ss" + I2])
    row("literal-dollar-component", "@ORIGIN@/alpine/v3.23 p$ss $ $$ $name\n",
        ["/alpine/v3.23/" + p + I2 for p in ("p$ss", "$", "$$", "$name")])
    row("literal-before-braced", "set key=main\n@ORIGIN@/alpine/v3.23/$${key}\n",
        ["/alpine/v3.23/$main" + I2])
    row("braced-url", "set root=@ORIGIN@/alpine/v3.23\nv2 ${root} main\n", [PIN + I2])
    row("assignment-time", "set part=main\nset copy=${part}\nset part=community\n"
        "@ORIGIN@/alpine/v3.23 ${copy} ${part}\n", [PIN + I2, "/alpine/v3.23/community" + I2])
    for size, value in (("", ""), ("0", ""), ("1", "m"), ("4", "main"), ("100", "main")):
        row("slice-" + (size or "empty"), "set key=main\n@ORIGIN@/alpine/v3.23/${key:" + size + "}\n",
            ["/alpine/v3.23/" + value + I2]
            if value else ["/alpine/v3.23" + I2])
    row("slice-oversized", "set key=main\n@ORIGIN@/alpine/v3.23/${key:9999}\n", [], 65)
    for size in (4095, 4096, 4097):
        row("slice-buffer-" + str(size), "set root=" + URL + "\nv2 ${root:" + str(size) + "}\n",
            [PIN + I2] if size <= 4096 else [], 0 if size <= 4096 else 65)
    for name, bad in (("negative", "${key:-1}"), ("alpha", "${key:x}"),
                      ("two-colons", "${key:1:2}"), ("unclosed", "${key"),
                      ("undefined", "${missing}"), ("empty-key", "${}")):
        row("invalid-" + name, "set key=main\n" + URL + "\n@ORIGIN@/vendor/" + bad + "\n"
            "@ORIGIN@/alpine/edge/main\n", [PIN + I2], 65)
    row("undefined-component", URL + "\n@ORIGIN@/alpine/v3.23 ${missing}\n", [PIN + I2], 65)
    row("default-first", "set -default key=main\n@ORIGIN@/alpine/v3.23 ${key}\n", [PIN + I2])
    row("default-keeps", "set key=main\nset -default key=edge\n@ORIGIN@/alpine/v3.23 ${key}\n", [PIN + I2])
    row("default-repeated", "set key=main\nset -default -default key=edge\n"
        "@ORIGIN@/alpine/v3.23 ${key}\n", [PIN + I2])
    row("default-expands-before-decision", "set key=main\nset -default key=${missing}\n" + URL + "\n", [], 65)
    row("overwrite", "set key=edge\nset key=main\n@ORIGIN@/alpine/v3.23 ${key}\n", [PIN + I2])
    row("key-case-digits", "set A_1=main\n@ORIGIN@/alpine/v3.23 ${A_1}\n", [PIN + I2])
    row("empty-value", "set key=\n@ORIGIN@/alpine/v3.23/${key}main\n", [PIN + I2])
    row("assignment-spaces", "set key=main community\n@ORIGIN@/alpine/v3.23 ${key}\n",
        [PIN + I2, "/alpine/v3.23/community" + I2])
    row("expanded-empty-components", "set key=\n@ORIGIN@/alpine/v3.23 ${key}\n", [])
    row("expanded-type-materialization", "set root=" + URL + "/index.adb\n${root}\n",
        [PIN + "/index.adb" + I2])
    for key in ("APK_ARCH", "APK_custom", "_key", "1key", "a-b", "a.b", "a "):
        row("invalid-key-" + key.replace(" ", "space"), "set " + key + "=main\n" + URL + "\n", [], 65)
    row("bad-set-option", "set -unknown key=main\n" + URL + "\n", [], 65)
    row("missing-equals", "set key\n" + URL + "\n", [], 65)
    row("apk-arch", "@ORIGIN@/vendor/${APK_ARCH}\n", ["/vendor/x86_64" + I2])
    row("whole-comment", "# @ORIGIN@/alpine/edge/main\n" + URL + "\n", [PIN + I2])
    row("inline-hash-components", URL + " # retained\n",
        [PIN + "/#" + I2, PIN + "/retained" + I2])
    for name, prefix in (("space", " "), ("tab", "\t"), ("indented-comment", " # ignored"),
                         ("only-spaces", "  ")):
        row("file-abort-" + name, URL + "\n" + prefix + "\n@ORIGIN@/alpine/edge/main\n", [PIN + I2], 65)
    row("blank-record", "\n" + URL + "\n\n", [PIN + I2])
    row("no-final-newline", URL, [PIN + I2])
    row("tabs-between", "v2\t@operator\t@ORIGIN@/alpine/v3.23\tmain\tcommunity\t\n",
        [PIN + "\tcommunity\t" + I2])
    row("trailing-space", URL + " \t\n", [PIN + I2])
    for kind, suffix in (("v2", I2), ("v3", I3), ("ndx", "")):
        row("typed-" + kind, kind + " @operator " + URL + "\n", [PIN + suffix])
        row("components-" + kind, kind + " @operator @ORIGIN@/alpine/v3.23 main community\n",
            [PIN + suffix, "/alpine/v3.23/community" + suffix])
    row("tag-untyped", "@operator " + URL + "\n", [PIN + I2])
    row("tag-literal-dollar", "@p$ss " + URL + "\n", [PIN + I2])
    row("tag-not-expanded", "@${missing} " + URL + "\n", [PIN + I2])
    for text in ("v2", "v3 @operator", "@operator", "unknown " + URL, "relative/path"):
        row("invalid-record-" + str(len(rows)), text + "\n" + URL + "\n", [], 65)
    for suffix in ("index.adb", "APKINDEX.tar.gz"):
        row("implicit-" + suffix, "@ORIGIN@/alpine/v3.23/" + suffix + "\n", ["/alpine/v3.23/" + suffix])
    row("inference-before-expansion", "set root=@ORIGIN@/alpine/v3.23/index.adb\nv2 ${root}\n${root}\n",
        ["/alpine/v3.23/index.adb" + I2])
    row("inference-raw-suffix", "set root=@ORIGIN@/alpine/v3.23\n${root}/index.adb\n",
        ["/alpine/v3.23/index.adb"])
    row("trailing-url-slashes", URL + "///\n", [PIN + I2])
    row("trailing-component-slashes", "v2 @ORIGIN@/alpine/v3.23 main///\n", [PIN + I2])
    row("ndx-trailing-component", "ndx @ORIGIN@/alpine/v3.23 index.adb/\n", ["/alpine/v3.23/index.adb/"])
    row("double-slashes", "@ORIGIN@/pub//alpine/v3.23//main\n", ["/pub//alpine/v3.23//main" + I2])
    row("leading-component-slash", "@ORIGIN@/alpine/v3.23 /main\n", ["/alpine/v3.23//main" + I2])
    row("duplicate-tags", URL + "\n@operator " + URL + "/\n", [PIN + I2])
    row("duplicate-components", "@ORIGIN@/alpine/v3.23 main main\n", [PIN + I2])
    row("alternate-mirror-root", "@ORIGIN@/pub/mirrors/alpine/v3.23/main\n",
        ["/pub/mirrors/alpine/v3.23/main" + I2])
    row("vendor", "@ORIGIN@/vendor/custom/packages\n", ["/vendor/custom/packages" + I2])
    for branch in ("edge", "latest-stable", "v3.24", "v3.230"):
        row("branch-" + branch, "@ORIGIN@/pub/alpine/" + branch + "/main\n",
            ["/pub/alpine/" + branch + "/main" + I2], 65)
    for name, path, policy, resolved in (
            ("dot-safe", "/alpine/v3.23/./main", 0, PIN),
            ("dotdot-safe", "/alpine/v3.23/sub/../main", 0, PIN),
            ("dotdot-escape", "/alpine/v3.23/../edge/main", 65, "/alpine/edge/main"),
            ("dotdot-remove-anchor", "/alpine/v3.23/../../vendor/main", 65, "/vendor/main"),
            ("encoded-dotdot", "/alpine/v3.23/%2e%2e/edge/main", 65, "/alpine/edge/main"),
            ("mixed-dotdot", "/alpine/v3.23/.%2E/edge/main", 65, "/alpine/edge/main"),
            ("encoded-slash", "/alpine/v3.23%2f..%2fedge/main", 65, "/alpine/edge/main"),
            ("encoded-anchor", "/%61lpine/edge/main", 65, "/alpine/edge/main"),
            ("encoded-safe", "/alpine/v3.23/%2e/main", 0, PIN)):
        row(name, "@ORIGIN@" + path + "\n", [path + I2], policy, resolved=[resolved + I2])
    row("component-dotdot", "v2 @ORIGIN@/alpine/v3.23 ../edge/main\n",
        ["/alpine/v3.23/../edge/main" + I2], 65, resolved=["/alpine/edge/main" + I2])
    row("expanded-component-dotdot", "set part=%2e%2e/edge/main\nv3 @ORIGIN@/alpine/v3.23 ${part}\n",
        ["/alpine/v3.23/%2e%2e/edge/main" + I3], 65, resolved=["/alpine/edge/main" + I3])
    row("main-before-dirs", "set key=main\n", [PIN + I2], files={LIB + "10-use.list":
        "@ORIGIN@/alpine/v3.23 ${key}\n"})
    row("sorted-union-variables", "", [PIN + I2], files={
        ETC + "20-use.list": "set -default key=edge\n@ORIGIN@/alpine/v3.23 ${key}\n",
        LIB + "10-vars.list": "set key=main\n"})
    for name, mask in (("etc-precedence", URL + "\n"), ("empty-mask", ""), ("null-mask", None)):
        row(name, "", [PIN + I2] if mask else [], files={
            ETC + "operator.list": mask, LIB + "operator.list": "@ORIGIN@/alpine/edge/main\n"})
    row("etc-edge-wins", "", ["/alpine/edge/main" + I2], 65, files={
        ETC + "operator.list": "@ORIGIN@/alpine/edge/main\n", LIB + "operator.list": URL + "\n"})
    row("ignored-files", URL + "\n", [PIN + I2], files={
        ETC + ".hidden.list": "@ORIGIN@/alpine/edge/main\n",
        LIB + "operator.txt": "@ORIGIN@/alpine/edge/main\n"})
    row("aborted-main-still-loads-dirs", "${missing}\n", [PIN + I2], 65,
        files={ETC + "operator.list": URL + "\n"})
    row("aborted-dir-still-loads-next", "", [PIN + I2], 65, files={
        LIB + "10-bad.list": "set key=${missing}\n@ORIGIN@/alpine/edge/main\n",
        ETC + "20-valid.list": URL + "\n"})
    row("space-metachar-filename", "", [PIN + I2], files={ETC + "operator ;$x.list": URL + "\n"})
    return rows


def run(argv, **kwargs):
    return subprocess.run(argv, capture_output=True, text=True, timeout=45, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ctid", required=True, choices=["3201"])
    parser.add_argument("--workspace", required=True, type=Path)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--case", action="append", help="Run only these named table rows")
    args = parser.parse_args()
    assert run(["hostname"]).stdout.strip() == "scripts-underground-proxmox-core-alpine"
    assert args.workspace.is_absolute() and not str(args.workspace).startswith("/tmp")
    args.workspace.mkdir(parents=True, exist_ok=True)
    assert run(["findmnt", "-rn", "-T", str(args.workspace), "-o", "FSTYPE"]).stdout.strip() not in ("", "tmpfs", "ramfs")
    config = run(["pct", "config", args.ctid])
    assert config.returncode == 0 and "hostname: alpine-native\n" in config.stdout
    assert "hwaddr=02:43:00:00:32:01," in config.stdout
    ct = ["pct", "exec", args.ctid, "--", "env", "TMPDIR=/var/lib/core-alpine-proof/tmp"]
    version = run(ct + ["apk", "--version"])
    assert version.returncode == 0
    closure = run(["bash", "-c", 'source "$1/misc/core.func"; _alpine_repository_contents', "_", str(args.source)])
    assert closure.returncode == 0 and "_alpine_repository_policy" in closure.stdout
    allocated = run(ct + ["mktemp", "-d", "/var/lib/core-alpine-proof/oracle.XXXXXX"])
    assert allocated.returncode == 0
    work = allocated.stdout.strip()
    assert re.fullmatch(r"/var/lib/core-alpine-proof/oracle\.[A-Za-z0-9]+", work)
    requests = []

    class Recorder(SimpleHTTPRequestHandler):
        def __init__(self, *a, **kw):
            super().__init__(*a, directory=str(args.workspace / "origin"), **kw)

        def do_GET(self):
            # Observe the origin consumer, not a client-side normalization guess.
            translated = self.translate_path(self.path)
            requests.append(dict(raw=self.path, resolved="/" + os.path.relpath(translated, self.directory)))
            self.send_error(404)

        def log_message(self, *_):
            pass

    server = ThreadingHTTPServer(("172.29.43.1", 0), Recorder)
    thread = threading.Thread(target=server.serve_forever)
    thread.start()
    origin = "http://172.29.43.1:" + str(server.server_port)
    results = []
    try:
        for case in cases():
            if args.case and case["name"] not in args.case:
                continue
            root = work + "/" + case["name"]
            files = {"etc/os-release": "ID=alpine\nVERSION_ID=3.23.8\n", "etc/apk/arch": "x86_64\n",
                     **case["files"]}
            policy = closure.stdout.replace("/lib/apk/", root + "/lib/apk/").replace("/etc/", root + "/etc/")
            files["policy.sh"] = policy + '\n_alpine_repository_policy "$@"\n'
            payload = io.BytesIO()
            with tarfile.open(fileobj=payload, mode="w") as archive:
                for path, text in files.items():
                    item = tarfile.TarInfo(path)
                    if text is None:
                        item.type = tarfile.SYMTYPE
                        item.linkname = "/dev/null"
                        archive.addfile(item)
                    else:
                        data = text.replace("@ORIGIN@", origin).encode()
                        item.size = len(data)
                        archive.addfile(item, io.BytesIO(data))
            requests.clear()
            # One transport per case; every producer status is retained separately.
            command = '''set -e
root=$1
mkdir -p "$root"
tar -xf - -C "$root"
rc=0
apk --root "$root" add --initdb --no-cache --allow-untrusted -v > "$root/native.out" 2> "$root/native.err" || rc=$?
printf '%s' "$rc" > "$root/native.status"
for action in project check; do
  rc=0
  /bin/ash "$root/policy.sh" "$action" > "$root/$action.out" 2> "$root/$action.err" || rc=$?
  printf '%s' "$rc" > "$root/$action.status"
done
rc=0
/bin/ash "$root/policy.sh" mirror mirror.invalid > "$root/mirror.out" 2> "$root/mirror.err" || rc=$?
printf '%s' "$rc" > "$root/mirror.status"
rc=0
/bin/ash "$root/policy.sh" project > "$root/after.out" 2> "$root/after.err" || rc=$?
printf '%s' "$rc" > "$root/after.status"
tar -cf - -C "$root" native.out native.err native.status project.out project.err project.status check.out check.err check.status mirror.out mirror.err mirror.status after.out after.err after.status
'''
            observed = subprocess.run(ct + ["/bin/ash", "-c", command, "_", root],
                                      input=payload.getvalue(), capture_output=True, timeout=45, check=True)
            with tarfile.open(fileobj=io.BytesIO(observed.stdout)) as archive:
                def result(prefix):
                    def read(suffix):
                        return archive.extractfile(prefix + suffix).read().decode()
                    return SimpleNamespace(returncode=int(read(".status")), stdout=read(".out"), stderr=read(".err"))
                native, projection, admission, mirror, after = (result(p) for p in ("native", "project", "check", "mirror", "after"))
            inventory = re.findall(r"WARNING: fetching (.*): HTTP 404: Not Found", native.stderr)
            expected = [origin + path for path in case["expected"]]
            errors = []
            if native.returncode != 0 or inventory != expected:
                errors.append("native inventory differs from explicit expected identities/count")
            if projection.returncode != 0 or projection.stdout.splitlines() != inventory:
                errors.append("owner projection != native inventory")
            if admission.returncode != case["policy"]:
                errors.append("admission policy status")
            mirrored = [p.replace(origin, "http://mirror.invalid", 1) if "/alpine/" in unquote(p) else p for p in expected]
            if mirror.returncode != case["policy"]:
                errors.append("mirror admission policy status")
            if after.returncode != 0 or after.stdout.splitlines() != (mirrored if not case["policy"] else expected):
                errors.append("mirror changed inventory semantics or refusal changed bytes")
            if Counter(unquote(r["raw"]) for r in requests) != Counter(unquote(p) for p in case["expected"]):
                errors.append("actual native requests differ from expected inventory")
            if case["resolved"] is not None and Counter(r["resolved"] for r in requests) != Counter(case["resolved"]):
                errors.append("origin-resolved paths differ from explicit expectation")
            results.append(dict(**case, native=dict(status=native.returncode, stdout=native.stdout, stderr=native.stderr,
                                                   inventory=inventory, requests=list(requests)),
                                projection=dict(status=projection.returncode, stdout=projection.stdout, stderr=projection.stderr),
                                admission=dict(status=admission.returncode, stderr=admission.stderr),
                                mirror=dict(status=mirror.returncode, stderr=mirror.stderr, inventory=after.stdout.splitlines()), errors=errors))
            (args.workspace / "results.json").write_text(json.dumps(dict(complete=False, apk=version.stdout.strip(), cases=results), indent=2) + "\n")
            if errors:
                print("MISMATCH " + case["name"] + ": " + "; ".join(errors), flush=True)
        failures = sum(bool(r["errors"]) for r in results)
        (args.workspace / "results.json").write_text(json.dumps(dict(complete=True, apk=version.stdout.strip(), cases=results), indent=2) + "\n")
        print(f"NATIVE_APK_DIFFERENTIAL_{'FAIL' if failures else 'PASS'} cases={len(results)} mismatches={failures}")
        return bool(failures)
    finally:
        server.shutdown()
        thread.join()
        server.server_close()
        subprocess.run(ct + ["rm", "-rf", "--", work], check=True, capture_output=True)


if __name__ == "__main__":
    raise SystemExit(main())
