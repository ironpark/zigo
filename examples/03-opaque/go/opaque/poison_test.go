package opaque

import (
	"errors"
	"os"
	"os/exec"
	"strings"
	"testing"
)

// A Zig panic longjmps out of the native frames without running their defers,
// so whatever the handle points at may be half-changed. The call reports the
// panic once; every later call on that handle is refused with the same kind
// of error, and Close leaks the native object rather than release it.
func TestPanicPoisonsTheHandle(t *testing.T) {
	context, err := NewContext()
	if err != nil {
		t.Fatal(err)
	}
	live := LiveBytes()

	err = context.Crash()
	if !errors.Is(err, ErrNativePanic) {
		t.Fatalf("Crash() = %#v, want *NativePanicError", err)
	}
	if !strings.Contains(err.Error(), "deliberate handle panic") {
		t.Fatalf("Crash() = %q, want the panic message", err)
	}

	_, err = context.Add(1)
	if !errors.Is(err, ErrNativePanic) {
		t.Fatalf("Add(1) after a panic = %#v, want *NativePanicError", err)
	}
	var refused *NativePanicError
	if !errors.As(err, &refused) || refused.Operation != "Context.Add receiver" {
		t.Fatalf("Add(1) after a panic = %#v, want the refused operation named", err)
	}
	if !strings.Contains(refused.Message, "Context.Crash") || !strings.Contains(refused.Message, "deliberate handle panic") {
		t.Fatalf("Add(1) after a panic = %q, want the earlier panic named", err)
	}

	if err := context.Close(); err != nil {
		t.Fatal(err)
	}
	if got := LiveBytes(); got != live {
		t.Fatalf("LiveBytes() after closing a poisoned handle = %d, want %d (leaked on purpose)", got, live)
	}
	if _, err := context.Add(1); !errors.Is(err, ErrInvalidHandle) {
		t.Fatalf("Add(1) after Close = %#v, want *HandleError", err)
	}
}

// The Zig method returns no error union, so before this rule the C wrapper's
// landing pad had no status to return and handed back a zero value: a fatal
// panic came out as a silent success. Its Go signature carries an `error`
// because the handle check needs one, and that is where the panic arrives.
func TestInfalliblePanicReachesTheCaller(t *testing.T) {
	context, err := NewContext()
	if err != nil {
		t.Fatal(err)
	}

	got, err := context.CrashInfallible()
	if !errors.Is(err, ErrNativePanic) {
		t.Fatalf("CrashInfallible() = %d, %#v, want *NativePanicError", got, err)
	}
	if !strings.Contains(err.Error(), "deliberate infallible panic") {
		t.Fatalf("CrashInfallible() = %q, want the panic message", err)
	}

	// The same poisoning rule applies: the native object may be half-changed.
	if _, err := context.Add(1); !errors.Is(err, ErrNativePanic) {
		t.Fatalf("Add(1) after an infallible panic = %#v, want *NativePanicError", err)
	}
}

// A function with no handle and no promoted integer has no `error` in its Go
// signature, so there is nowhere to report a panic to. zigo keeps Zig's
// meaning: the message goes to stderr and the process aborts. Verified from a
// child process, because the parent would not survive it.
func TestFatalPanicAbortsTheProcess(t *testing.T) {
	if os.Getenv("ZIGO_CRASH_CHILD") == "1" {
		CrashFatal()
		return
	}
	command := exec.Command(os.Args[0], "-test.run=TestFatalPanicAbortsTheProcess")
	command.Env = append(os.Environ(), "ZIGO_CRASH_CHILD=1")
	output, err := command.CombinedOutput()
	if err == nil {
		t.Fatalf("child exited cleanly; output: %s", output)
	}
	var exit *exec.ExitError
	if !errors.As(err, &exit) {
		t.Fatalf("child failed to run: %v", err)
	}
	if !strings.Contains(string(output), "zigo: native panic: deliberate fatal panic") {
		t.Fatalf("child output = %q, want the panic message on stderr", output)
	}
}
