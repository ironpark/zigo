package materialized

import (
	"encoding/binary"
	"testing"
)

func TestMaterializedRejectsInvalidArrayRanges(t *testing.T) {
	for _, tc := range []struct{ offset, count, stride uint64 }{
		{0, ^uint64(0), 8}, {0, 1 << 61, 8}, {41, 0, 8}, {39, 1, 8}, {40, 1, 16},
	} {
		t.Run("invalid", func(t *testing.T) {
			defer func() {
				if got := recover(); got != "zigo: invalid materialized result buffer" {
					t.Fatalf("panic=%v", got)
				}
			}()
			zigoMaterializedArray(make([]byte, 40), tc.offset, tc.count, tc.stride)
		})
	}
	if got := zigoMaterializedArray(make([]byte, 40), 40, 0, 8); len(got) != 0 {
		t.Fatal("empty end range")
	}
}

func TestMaterializedRejectsRootCountBeforeAllocation(t *testing.T) {
	for _, count := range []uint64{^uint64(0), 1 << 61, 1} {
		t.Run("count", func(t *testing.T) {
			buffer := make([]byte, 40)
			for offset, value := range map[int]uint64{0: zigoMaterializedMagicVersion, 8: 1, 16: count, 24: 40, 32: 40} {
				binary.LittleEndian.PutUint64(buffer[offset:], value)
			}
			defer func() {
				if got := recover(); got != "zigo: invalid materialized result buffer" {
					t.Fatalf("panic=%v", got)
				}
			}()
			zigoDecodeProbeSliceBuffer(buffer)
		})
	}
}

func TestMaterializedRejectsFieldCountBeforeAllocation(t *testing.T) {
	for _, field := range []int{72, 88, 152} {
		t.Run("field", func(t *testing.T) {
			buffer := make([]byte, 200)
			for offset, value := range map[int]uint64{0: zigoMaterializedMagicVersion, 8: 1, 16: 1, 24: 40, 32: 200, 40 + field: 1 << 61} {
				binary.LittleEndian.PutUint64(buffer[offset:], value)
			}
			defer func() {
				if got := recover(); got != "zigo: invalid materialized result buffer" {
					t.Fatalf("field=%d panic=%v", field, got)
				}
			}()
			zigoDecodeProbeBuffer(buffer)
		})
	}
}

func FuzzMaterializedArrayRange(f *testing.F) {
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
		result := zigoMaterializedArray(make([]byte, 40), offset, count, stride)
		if uint64(len(result)) != count*stride {
			t.Fatal("wrong range length")
		}
	})
}
