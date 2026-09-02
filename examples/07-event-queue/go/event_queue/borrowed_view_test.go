package event_queue

import (
	"errors"
	"testing"
)

func TestBorrowedViewFollowsParentLifetime(t *testing.T) {
	box, err := NewBorrowBox(42)
	if err != nil {
		t.Fatal(err)
	}
	view, err := box.View()
	if err != nil {
		t.Fatal(err)
	}
	if got, err := view.Get(); err != nil || got != 42 {
		t.Fatalf("view.Get() = (%d, %v), want (42, nil)", got, err)
	}
	if err := box.Close(); err != nil {
		t.Fatal(err)
	}
	if _, err := view.Get(); !errors.Is(err, ErrInvalidHandle) {
		t.Fatalf("view.Get() after parent Close = %v, want ErrInvalidHandle", err)
	}
	if err := view.Close(); err != nil {
		t.Fatalf("borrowed view Close = %v", err)
	}
}

func TestBorrowedViewPoisonPropagatesToParent(t *testing.T) {
	box, err := NewBorrowBox(7)
	if err != nil {
		t.Fatal(err)
	}
	view, err := box.View()
	if err != nil {
		t.Fatal(err)
	}
	if err := view.Explode(); !errors.Is(err, ErrNativePanic) {
		t.Fatalf("view.Explode() = %v, want ErrNativePanic", err)
	}
	if _, err := box.View(); !errors.Is(err, ErrNativePanic) {
		t.Fatalf("box.View() after borrowed panic = %v, want ErrNativePanic", err)
	}
}

func TestBorrowedViewPinsParentDuringNativeCall(t *testing.T) {
	box, err := NewBorrowBox(9)
	if err != nil {
		t.Fatal(err)
	}
	view, err := box.View()
	if err != nil {
		t.Fatal(err)
	}
	if _, err := view.zigoAcquire("borrowed call"); err != nil {
		t.Fatal(err)
	}
	if err := box.Close(); !errors.Is(err, ErrHandleInUse) {
		t.Fatalf("box.Close() during borrowed call = %v, want ErrHandleInUse", err)
	}
	view.zigoRelease()
	if err := box.Close(); err != nil {
		t.Fatalf("box.Close() after borrowed call = %v", err)
	}
}
