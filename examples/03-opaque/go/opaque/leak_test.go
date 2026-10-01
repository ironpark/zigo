package opaque

import (
	"os"
	"os/exec"
	"runtime"
	"strings"
	"testing"
	"time"
)

// With ZIGO_DEBUG_LEAKS set, a handle the garbage collector reclaims without
// Close says so on standard error, with the stack that created it. A closed
// handle says nothing. The switch is read at package initialisation, so the
// check runs in a child process that starts with it set.
func TestDroppedHandleIsReportedUnderLeakTracking(t *testing.T) {
	if os.Getenv("ZIGO_LEAK_CHILD") == "1" {
		leakOneContext(t)
		return
	}
	command := exec.Command(os.Args[0], "-test.run=TestDroppedHandleIsReportedUnderLeakTracking")
	command.Env = append(os.Environ(), "ZIGO_LEAK_CHILD=1", "ZIGO_DEBUG_LEAKS=1")
	output, err := command.CombinedOutput()
	if err != nil {
		t.Fatalf("child failed: %v; output: %s", err, output)
	}
	const report = "zigo: Context was garbage-collected without Close; created at:"
	if got := strings.Count(string(output), report); got != 1 {
		t.Fatalf("child reported %d leaks, want 1; output: %s", got, output)
	}
	if !strings.Contains(string(output), "leakOneContext") {
		t.Fatalf("leak report does not name the creating function; output: %s", output)
	}
}

func TestLeakTrackingIsOffByDefault(t *testing.T) {
	if os.Getenv("ZIGO_DEBUG_LEAKS") != "" {
		t.Skip("leak tracking is enabled in this environment")
	}
	if zigoLeakTracking {
		t.Fatal("leak tracking is on without ZIGO_DEBUG_LEAKS")
	}
	if site := zigoLeakSite(); site != nil {
		t.Fatalf("zigoLeakSite recorded %d bytes with tracking off", len(site))
	}
}

func leakOneContext(t *testing.T) {
	closed, err := NewContext()
	if err != nil {
		t.Fatal(err)
	}
	if err := closed.Close(); err != nil {
		t.Fatal(err)
	}
	before := LiveBytes()
	if _, err := NewContext(); err != nil {
		t.Fatal(err)
	}
	// Cleanups run on a goroutine of their own after a collection, so the
	// native release is what says the dropped handle has been reclaimed.
	for deadline := time.Now().Add(5 * time.Second); LiveBytes() != before; {
		if time.Now().After(deadline) {
			t.Fatal("the dropped Context was never reclaimed")
		}
		runtime.GC()
		time.Sleep(10 * time.Millisecond)
	}
}
