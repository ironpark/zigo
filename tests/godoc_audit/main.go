package main

import (
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: godoc-audit <generated-dir>...")
		os.Exit(2)
	}
	fset := token.NewFileSet()
	failed := false
	for _, root := range os.Args[1:] {
		// Go allows a package doc on exactly one file of a package, so the
		// generated tree has to place it on exactly one file too.
		packageDocs := map[string][]string{}
		err := filepath.WalkDir(root, func(path string, entry fs.DirEntry, walkErr error) error {
			if walkErr != nil {
				return walkErr
			}
			if entry.IsDir() || !strings.HasSuffix(path, "_gen.go") {
				return nil
			}
			file, err := parser.ParseFile(fset, path, nil, parser.ParseComments)
			if err != nil {
				return err
			}
			directory := filepath.Dir(path)
			if _, seen := packageDocs[directory]; !seen {
				packageDocs[directory] = nil
			}
			if file.Doc != nil {
				packageDocs[directory] = append(packageDocs[directory], path)
				if want := "Package " + file.Name.Name; !strings.HasPrefix(strings.TrimSpace(file.Doc.Text()), want) {
					fmt.Fprintf(os.Stderr, "%s: package doc does not open with %q\n", path, want)
					failed = true
				}
			}
			for _, declaration := range file.Decls {
				switch value := declaration.(type) {
				case *ast.FuncDecl:
					if ast.IsExported(value.Name.Name) && !documents(value.Doc, value.Name.Name) {
						report(fset, value.Pos(), path, value.Name.Name)
						failed = true
					}
				case *ast.GenDecl:
					for _, spec := range value.Specs {
						switch item := spec.(type) {
						case *ast.TypeSpec:
							if ast.IsExported(item.Name.Name) && !documents(firstDoc(item.Doc, value.Doc), item.Name.Name) {
								report(fset, item.Pos(), path, item.Name.Name)
								failed = true
							}
						case *ast.ValueSpec:
							for _, name := range item.Names {
								if ast.IsExported(name.Name) && !documents(firstDoc(item.Doc, value.Doc), name.Name) {
									report(fset, name.Pos(), path, name.Name)
									failed = true
								}
							}
						}
					}
				}
			}
			return nil
		})
		if err != nil {
			fmt.Fprintf(os.Stderr, "godoc audit: %s: %v\n", root, err)
			os.Exit(1)
		}
		for directory, files := range packageDocs {
			if len(files) != 1 {
				fmt.Fprintf(os.Stderr, "%s: expected exactly one file with a package doc, found %d\n", directory, len(files))
				failed = true
			}
		}
	}
	if failed {
		os.Exit(1)
	}
}

func firstDoc(primary, fallback *ast.CommentGroup) *ast.CommentGroup {
	if primary != nil {
		return primary
	}
	return fallback
}

// A generated doc either splices the body onto the identifier ("Len reports
// ...") or, when the body is a sentence of its own, opens with the identifier
// alone on the first line. Both start at the identifier, which is what godoc
// asks for.
func documents(group *ast.CommentGroup, name string) bool {
	if group == nil {
		return false
	}
	text := strings.TrimSpace(group.Text())
	if text == name {
		return true
	}
	first, rest, _ := strings.Cut(text, "\n")
	if strings.TrimSpace(first) == name {
		return strings.TrimSpace(rest) != ""
	}
	return strings.HasPrefix(text, name+" ") && !splicesNounPhrase(text, name)
}

// Words that can only open a sentence, never continue one that began with the
// identifier. "SelectionSilent the selection flag bits" is the shape this
// catches: a doc that was lowercased and glued onto the name.
var sentenceOpeners = map[string]bool{
	"the": true, "a": true, "an": true, "this": true, "these": true,
	"those": true, "it": true, "its": true, "their": true, "there": true,
}

func splicesNounPhrase(text, name string) bool {
	body := strings.TrimSpace(strings.TrimPrefix(text, name))
	word, _, _ := strings.Cut(body, " ")
	return sentenceOpeners[word]
}

func report(fset *token.FileSet, position token.Pos, path, name string) {
	line := fset.Position(position).Line
	fmt.Fprintf(os.Stderr, "%s:%d: exported generated declaration %s has no identifier-leading GoDoc\n", path, line, name)
}
