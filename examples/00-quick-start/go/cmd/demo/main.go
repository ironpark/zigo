package main

import (
	"example.com/zigo/quick-start/calculator"
	"fmt"
)

func main() {
	fmt.Printf("2 + 3 = %d\n", calculator.Add(2, 3))
	// Contributed by the buildinfo plugin, not by the binding: the plugin
	// ships its own Zig, and the native library answers out of it.
	fmt.Println(calculator.BuildInfo())
}
