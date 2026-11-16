package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestAddonReleaseCheckPolicy(t *testing.T) {
	good := `if check_for_gh_release app owner/repo; then :; else
local release_status=$?
[[ "$release_status" == 1 ]] || return "$release_status"
fi`
	cases := []struct {
		name, body string
		bad        bool
	}{
		{"tri-state", good, false},
		{"no-else", `if check_for_gh_release app owner/repo; then :; fi; exit`, true},
		{"boolean", `check_for_gh_release app owner/repo || true`, true},
		{"lost-status", strings.Replace(good, "local release_status=$?", "true; local release_status=$?", 1), true},
		{"inverted", strings.Replace(good, "== 1", "!= 1", 1), true},
		{"returns-success", strings.Replace(good, `return "$release_status"`, "return 0", 1), true},
		{"negated", `if ! check_for_gh_release app owner/repo; then return 0; fi`, true},
		{"substitution", "echo \"$(" + good + "\n)\"", true},
		{"subshell", "(" + good + "; ) || true", true},
		{"background", good + " &\nwait; exit 0", true},
		{"pipeline", "{ " + good + "; } | cat", true},
		{"nested-helper", "helper() { " + good + "; }; helper || true", true},
		{"comment", `# check_for_gh_release app owner/repo`, false},
		{"quoted-text", `echo 'check_for_gh_release app owner/repo'`, false},
		{"dynamic-command-outside-static-view", `"$checker" app owner/repo`, false},
		{"indirect-helper-outside-static-view", `app_release_check app owner/repo`, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			var violations []string
			analyzeScript("REPO_BASE=offline\nupdate_script() {\n:\n"+c.body+"\n}\n", TypeAddon, "fixture", &violations)
			if (len(violations) > 0) != c.bad {
				t.Fatalf("violations=%v; want invalid=%v", violations, c.bad)
			}
		})
	}
}

func TestLXCSourceIdentityPolicy(t *testing.T) {
	prefix := "#!/usr/bin/env bash\nREPO_BASE=offline\nAPP=Scanopy\ninstall_script() { :; }\n"
	valid := `source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc") --script-id "netvisor" -- "$@"`
	cases := []struct {
		name, footer string
		bad          bool
	}{
		{"literal", valid, false},
		{"absent", "", true},
		{"old", `source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")`, true},
		{"wrong", strings.Replace(valid, `"netvisor"`, `"scanopy"`, 1), true},
		{"dynamic", strings.Replace(valid, `"netvisor"`, `"$NSAPP"`, 1), true},
		{"default", strings.Replace(valid, `"netvisor"`, `"${var_lxc_script_id:-netvisor}"`, 1), true},
		{"duplicate", valid + "\n" + valid, true},
		{"comment", "# " + valid, true},
		{"function", "fake() { " + valid + "; }", true},
		{"string", "printf '%s\\n' '" + valid + "'", true},
		{"missing-forwarding", strings.Replace(valid, ` "$@"`, "", 1), true},
		{"conditional", "if true; then " + valid + "; fi", true},
		{"background", valid + " &", true},
		{"provider-string", `source <(printf '%s' 'curl /misc/bootstrap/lxc') --script-id "netvisor" -- "$@"`, true},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			var violations []string
			analyzeScript(prefix+c.footer+"\n", TypeLXC, "netvisor", &violations)
			if (len(violations) > 0) != c.bad {
				t.Fatalf("violations=%v; want invalid=%v", violations, c.bad)
			}
		})
	}
	for _, slug := range []string{"llama-cpp", "netvisor", "scanopy"} {
		var violations []string
		analyzeScript(prefix+strings.Replace(valid, `"netvisor"`, `"`+slug+`"`, 1)+"\n", TypeLXC, slug, &violations)
		if len(violations) > 0 {
			t.Fatalf("canonical %s: %v", slug, violations)
		}
	}
}

func TestAllMaintainedLXCSourceIdentities(t *testing.T) {
	files, err := filepath.Glob("../../scripts/lxc/*.sh")
	if err != nil || len(files) == 0 {
		t.Fatalf("maintained producer inventory: %v", err)
	}
	for _, path := range files {
		src, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		var violations []string
		analyzeScript(string(src), TypeLXC, strings.TrimSuffix(filepath.Base(path), ".sh"), &violations)
		if len(violations) > 0 {
			t.Errorf("%s: %v", path, violations)
		}
	}
	t.Logf("audited %d maintained LXC producers", len(files))
}

func TestGeneratorRemovesOrphanASTs(t *testing.T) {
	if os.Getenv("AST_GENERATOR_TEST_HELPER") == "1" {
		main()
		os.Exit(0)
	}

	root := t.TempDir()
	write := func(path, content string) {
		t.Helper()
		path = filepath.Join(root, path)
		if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(content), 0644); err != nil {
			t.Fatal(err)
		}
	}
	write("_config.yml", "")
	for _, coll := range collections {
		name := string(coll)
		content := "#!/usr/bin/env bash\necho kept\n"
		if coll == TypeLXC {
			content = "#!/usr/bin/env bash\nREPO_BASE=offline\n" + `source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc") --script-id "kept" -- "$@"` + "\n"
		}
		write(filepath.Join("scripts", name, "kept.sh"), content)
		write(filepath.Join("_ast", name, "kept.json"), "stale output")
		write(filepath.Join("_ast", name, "removed.json"), "orphan")
		write(filepath.Join("_ast", name, "notes.txt"), "keep non-JSON files")
		if err := os.Mkdir(filepath.Join(root, "_ast", name, "directory.json"), 0755); err != nil {
			t.Fatal(err)
		}
	}
	// A matching slug in another collection must not keep an orphan alive.
	write("scripts/lxc/other-collection.sh", "REPO_BASE=offline\n"+`source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc") --script-id "other-collection" -- "$@"`+"\n")
	write("_ast/addon/other-collection.json", "orphan")
	// An entirely removed source collection still needs its outputs cleaned up.
	if err := os.RemoveAll(filepath.Join(root, "scripts", "vm")); err != nil {
		t.Fatal(err)
	}

	executable, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	for run := 1; run <= 2; run++ {
		cmd := exec.Command(executable, "-test.run=^TestGeneratorRemovesOrphanASTs$")
		cmd.Dir = root
		cmd.Env = append(os.Environ(), "AST_GENERATOR_TEST_HELPER=1")
		if output, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("generator run %d: %v\n%s", run, err, output)
		}
		for _, coll := range collections {
			name := string(coll)
			orphans := []string{"removed"}
			if coll == TypeAddon {
				orphans = append(orphans, "other-collection")
			}
			for _, slug := range orphans {
				path := filepath.Join(root, "_ast", name, slug+".json")
				if _, err := os.Stat(path); !os.IsNotExist(err) {
					t.Errorf("run %d: orphan %s remains (stat: %v)", run, path, err)
				}
			}
			kept := filepath.Join(root, "_ast", name, "kept.json")
			if coll == TypeVM {
				if _, err := os.Stat(kept); !os.IsNotExist(err) {
					t.Errorf("run %d: AST from removed collection remains: %v", run, err)
				}
			} else if data, err := os.ReadFile(kept); err != nil || len(data) == 0 || string(data) == "stale output" {
				t.Errorf("run %d: matching AST was not regenerated: %v", run, err)
			}
			for _, file := range []string{"notes.txt", "directory.json"} {
				if _, err := os.Stat(filepath.Join(root, "_ast", name, file)); err != nil {
					t.Errorf("run %d: unrelated entry %s was removed: %v", run, file, err)
				}
			}
		}
	}
}
