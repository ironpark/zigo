// Command symbol-audit checks that the `symbol` recorded for every function in
// a generated `zigo/semantic.json` is the name the bindings actually export:
// unique across the document, and present in the generated cgo call sites.
package main

import (
	"encoding/json"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

type document struct {
	Prefix    string `json:"prefix"`
	Functions []struct {
		Name      string `json:"name"`
		Receiver  string `json:"receiver"`
		Namespace string `json:"namespace"`
		Symbol    string `json:"symbol"`
	} `json:"functions"`
}

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: symbol-audit <example-dir>...")
		os.Exit(2)
	}
	failed := false
	for _, root := range os.Args[1:] {
		if err := audit(root); err != nil {
			fmt.Fprintf(os.Stderr, "symbol audit: %s: %v\n", root, err)
			failed = true
		}
	}
	if failed {
		os.Exit(1)
	}
}

func audit(root string) error {
	raw, err := os.ReadFile(filepath.Join(root, "zigo", "semantic.json"))
	if err != nil {
		return err
	}
	var parsed document
	if err := json.Unmarshal(raw, &parsed); err != nil {
		return err
	}
	exported, err := exportedSymbols(root)
	if err != nil {
		return err
	}
	seen := map[string]string{}
	for _, function := range parsed.Functions {
		owner := function.Receiver
		if owner == "" {
			owner = function.Namespace
		}
		identity := function.Name
		if owner != "" {
			identity = owner + "." + function.Name
		}
		if previous, duplicate := seen[function.Symbol]; duplicate {
			return fmt.Errorf("%s and %s both claim the symbol %s", previous, identity, function.Symbol)
		}
		seen[function.Symbol] = identity
		if !strings.HasPrefix(function.Symbol, parsed.Prefix+"_") {
			return fmt.Errorf("%s: symbol %s does not carry the %s prefix", identity, function.Symbol, parsed.Prefix)
		}
		if !exported[function.Symbol] {
			return fmt.Errorf("%s: symbol %s is not called by the generated bindings", identity, function.Symbol)
		}
	}
	return nil
}

var callPattern = regexp.MustCompile(`\bC\.([A-Za-z_][A-Za-z0-9_]*)`)

// The cgo bindings name every wrapper they call, so the set of `C.<symbol>`
// references is the export list the metadata has to agree with.
func exportedSymbols(root string) (map[string]bool, error) {
	symbols := map[string]bool{}
	err := filepath.WalkDir(filepath.Join(root, "go"), func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if entry.IsDir() || !strings.HasSuffix(path, "_gen.go") {
			return nil
		}
		source, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		for _, match := range callPattern.FindAllSubmatch(source, -1) {
			symbols[string(match[1])] = true
		}
		return nil
	})
	return symbols, err
}
