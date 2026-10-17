package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

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
		write(filepath.Join("scripts", name, "kept.sh"), "#!/usr/bin/env bash\necho kept\n")
		write(filepath.Join("_ast", name, "kept.json"), "stale output")
		write(filepath.Join("_ast", name, "removed.json"), "orphan")
		write(filepath.Join("_ast", name, "notes.txt"), "keep non-JSON files")
		if err := os.Mkdir(filepath.Join(root, "_ast", name, "directory.json"), 0755); err != nil {
			t.Fatal(err)
		}
	}
	// A matching slug in another collection must not keep an orphan alive.
	write("scripts/lxc/other-collection.sh", "echo kept\n")
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
