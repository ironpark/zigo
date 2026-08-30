package raw

import "testing"

func TestProjectionStatusAndOutputPreservation(t *testing.T) {
	value, code := ValueCreate(42)
	if code != 0 {
		t.Fatalf("ValueCreate code = %d", code)
	}
	defer ValueDeinit(value)

	const sentinel = uint8(0xa5)
	result, status := projectFlagWithInitial(value, sentinel)
	if status != 0 || result != sentinel {
		t.Fatalf("mismatch = (result %#x, status %d), want (%#x, 0)", result, status, sentinel)
	}

	result, status = projectFlagWithInitial(nil, sentinel)
	if status != 2 || result != sentinel {
		t.Fatalf("nil handle = (result %#x, status %d), want (%#x, 2)", result, status, sentinel)
	}

	if status := projectIntegerWithNullOutput(value); status != 2 {
		t.Fatalf("null output status = %d, want 2", status)
	}

}
