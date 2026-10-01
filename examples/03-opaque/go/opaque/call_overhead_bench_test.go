package opaque

import (
	"testing"

	"example.com/zigo/opaque/internal/raw"
)

// These price what a generated method adds around its native call. The raw
// call is the floor; the method adds the handle pin (zigoAcquire/zigoRelease).
// The raw call allocates nothing: this binding has no callbacks, so its
// functions are declared `#cgo noescape` and the out-parameter stays on the
// stack.

func benchContext(b *testing.B) *Context {
	b.Helper()
	context, err := NewContext()
	if err != nil {
		b.Fatalf("NewContext: %v", err)
	}
	b.Cleanup(func() { context.Close() })
	return context
}

func BenchmarkAddMethod(b *testing.B) {
	context := benchContext(b)
	b.ReportAllocs()
	for b.Loop() {
		if _, err := context.Add(1); err != nil {
			b.Fatal(err)
		}
	}
}

func BenchmarkAddRaw(b *testing.B) {
	context := benchContext(b)
	ptr := context.ptr
	b.ReportAllocs()
	for b.Loop() {
		raw.ContextAdd(ptr, 1)
	}
}

func BenchmarkHandlePin(b *testing.B) {
	context := benchContext(b)
	b.ReportAllocs()
	for b.Loop() {
		if _, err := context.zigoAcquire("bench"); err != nil {
			b.Fatal(err)
		}
		context.zigoRelease()
	}
}

// Many goroutines calling one handle: the pin's lock is shared state, so this
// is the case where the wrapper costs the most next to the raw call.
func BenchmarkAddMethodParallel(b *testing.B) {
	context := benchContext(b)
	b.ReportAllocs()
	b.RunParallel(func(pb *testing.PB) {
		for pb.Next() {
			if _, err := context.Add(1); err != nil {
				b.Fatal(err)
			}
		}
	})
}

func BenchmarkAddRawParallel(b *testing.B) {
	context := benchContext(b)
	ptr := context.ptr
	b.ReportAllocs()
	b.RunParallel(func(pb *testing.PB) {
		for pb.Next() {
			raw.ContextAdd(ptr, 1)
		}
	})
}
