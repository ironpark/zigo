package materialized_test

import (
	"example.com/zigo/materialized/materialized"
	"fmt"
)

func ExampleSnapshot() {
	// This is a Go-owned value tree. No native handle needs Close.
	value := materialized.Snapshot()
	fmt.Println(value.Name, value.Child.Value, value.Maybe == nil)
	fmt.Println(value.Tags)
	// Output:
	// materialized 42 true
	// [alpha beta]
}

func ExampleFill() {
	output := make([]materialized.Probe, 2)
	n := materialized.Fill(output)
	fmt.Println(n, output[:n][0].Name)
	// Output: 2 materialized
}
