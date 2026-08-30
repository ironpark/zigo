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

func documents(group *ast.CommentGroup, name string) bool {
	if group == nil {
		return false
	}
	text := strings.TrimSpace(group.Text())
	return text == name || strings.HasPrefix(text, name+" ")
}

func report(fset *token.FileSet, position token.Pos, path, name string) {
	line := fset.Position(position).Line
	fmt.Fprintf(os.Stderr, "%s:%d: exported generated declaration %s has no identifier-leading GoDoc\n", path, line, name)
}
