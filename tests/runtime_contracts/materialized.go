package contracts

import (
	"encoding/binary"
	"testing"
)

// ArrayRanges verifies bounds checks before decoding array storage.
func ArrayRanges(t *testing.T, array func([]byte, uint64, uint64, uint64) []byte) {
	for _, tc := range []struct{ offset, count, stride uint64 }{
		{0, ^uint64(0), 8}, {0, 1 << 61, 8}, {41, 0, 8}, {39, 1, 8}, {40, 1, 16},
	} {
		t.Run("invalid", func(t *testing.T) {
			defer func() {
				if got := recover(); got != "zigo: invalid materialized result buffer" {
					t.Fatalf("panic=%v", got)
				}
			}()
			array(make([]byte, 40), tc.offset, tc.count, tc.stride)
		})
	}
	if got := array(make([]byte, 40), 40, 0, 8); len(got) != 0 {
		t.Fatal("empty end range")
	}
}

// RootCounts verifies malformed counts fail before allocating decoded roots.
func RootCounts(t *testing.T, magic, layout uint64, decode func([]byte)) {
	for _, count := range []uint64{^uint64(0), 1 << 61, 1} {
		t.Run("count", func(t *testing.T) {
			buffer := make([]byte, 40)
			for offset, value := range map[int]uint64{0: magic, 8: layout, 16: count, 24: 40, 32: 40} {
				binary.LittleEndian.PutUint64(buffer[offset:], value)
			}
			defer func() {
				if got := recover(); got != "zigo: invalid materialized result buffer" {
					t.Fatalf("panic=%v", got)
				}
			}()
			decode(buffer)
		})
	}
}

// FieldCounts verifies malformed counts fail before allocating decoded fields.
func FieldCounts(t *testing.T, magic, layout uint64, recordSize int, fields []int, decode func([]byte)) {
	for _, field := range fields {
		t.Run("field", func(t *testing.T) {
			buffer := make([]byte, 40+recordSize)
			for offset, value := range map[int]uint64{0: magic, 8: layout, 16: 1, 24: 40, 32: uint64(len(buffer)), 40 + field: 1 << 61} {
				binary.LittleEndian.PutUint64(buffer[offset:], value)
			}
			defer func() {
				if got := recover(); got != "zigo: invalid materialized result buffer" {
					t.Fatalf("field=%d panic=%v", field, got)
				}
			}()
			decode(buffer)
		})
	}
}

// FuzzArrayRange exercises the array range checker independently of the backend.
func FuzzArrayRange(f *testing.F, array func([]byte, uint64, uint64, uint64) []byte) {
	f.Add(uint64(40), uint64(0), uint8(8))
	f.Add(uint64(0), ^uint64(0), uint8(16))
	f.Fuzz(func(t *testing.T, offset, count uint64, width uint8) {
		stride := uint64(width%16) + 1
		valid := offset <= 40 && count <= (40-offset)/stride
		defer func() {
			if got := recover(); got != nil {
				if valid || got != "zigo: invalid materialized result buffer" {
					t.Fatalf("unexpected panic: %v", got)
				}
			} else if !valid {
				t.Fatal("invalid range accepted")
			}
		}()
		result := array(make([]byte, 40), offset, count, stride)
		if uint64(len(result)) != count*stride {
			t.Fatal("wrong range length")
		}
	})
}
