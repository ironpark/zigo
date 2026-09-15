package calculator_test

import (
	"example.com/zigo/quick-start/calculator"
	"fmt"
	"strings"
	"testing"
)

func ExampleAdd() {
	fmt.Println(calculator.Add(2, 3))
	// Output: 5
}

// BuildInfo comes from the buildinfo plugin's own native source rather than
// from src/root.zig, so its exact text depends on the toolchain and target
// this example was built with. What it always starts with is the Zig version.
func TestBuildInfo(t *testing.T) {
	info := calculator.BuildInfo()
	if info == "" {
		t.Fatal("BuildInfo() is empty")
	}
	if !strings.HasPrefix(info, "zig ") {
		t.Fatalf("BuildInfo() = %q, want a string starting with %q", info, "zig ")
	}
}
