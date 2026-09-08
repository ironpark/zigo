package lookup

import (
	"math"
	"strconv"
	"testing"
)

func TestLookupBoundaries(t *testing.T) {
	cases := []struct {
		value interface{ String() string }
		want  string
	}{
		{Dense(-2), "Dense(-2)"}, {DenseMinus, "minus"}, {DenseZero, "zero"}, {DenseTwo, "two"}, {Dense(3), "Dense(3)"},
		{HolesLow, "low"}, {HolesNext, "next"}, {Holes(-126), "Holes(-126)"}, {HolesHigh, "high"}, {Holes(-124), "Holes(-124)"},
		{Min64Low, "low"}, {Min64High, "high"}, {Min64(math.MaxInt64), "Min64(9223372036854775807)"},
		{Max64Low, "low"}, {Max64High, "high"}, {Max64(math.MaxUint64), "Max64(18446744073709551615)"},
		{Max8(253), "Max8(253)"}, {Max8Low, "low"}, {Max8High, "high"},
		{SparseLow, "low"}, {SparseHigh, "high"}, {Sparse(0), "Sparse(0)"}, {SingleOnly, "only"}, {Single(0), "Single(0)"},
	}
	for _, c := range cases {
		if got := c.value.String(); got != c.want {
			t.Errorf("%T: got %q, want %q", c.value, got, c.want)
		}
	}
	for i := -128; i <= 127; i++ {
		v := Holes(i)
		got, err := ParseHoles(v.String())
		if err != nil || got != v {
			t.Fatalf("round trip %d: %d, %v", v, got, err)
		}
	}
	v := DenseOne
	if err := v.UnmarshalText([]byte("missing")); err == nil || v != DenseOne {
		t.Fatal("failed parse changed receiver")
	}
}

var nameSink string
var valueSink Dense
var denseByName = map[string]Dense{"minus": DenseMinus, "zero": DenseZero, "one": DenseOne, "two": DenseTwo}

func denseSwitch(v Dense) string {
	switch v {
	case DenseMinus:
		return "minus"
	case DenseZero:
		return "zero"
	case DenseOne:
		return "one"
	case DenseTwo:
		return "two"
	}
	return "Dense(" + strconv.Itoa(int(v)) + ")"
}

func BenchmarkDenseString(b *testing.B) {
	values := [...]Dense{DenseMinus, DenseTwo, DenseZero, DenseOne}
	b.Run("array", func(b *testing.B) {
		for i := 0; i < b.N; i++ {
			nameSink = values[i&3].String()
		}
	})
	b.Run("switch", func(b *testing.B) {
		for i := 0; i < b.N; i++ {
			nameSink = denseSwitch(values[i&3])
		}
	})
}

func BenchmarkParseDense(b *testing.B) {
	names := [...]string{"minus", "two", "zero", "one"}
	b.Run("switch", func(b *testing.B) {
		for i := 0; i < b.N; i++ {
			valueSink, _ = ParseDense(names[i&3])
		}
	})
	b.Run("map", func(b *testing.B) {
		for i := 0; i < b.N; i++ {
			valueSink = denseByName[names[i&3]]
		}
	})
}

func largeSwitch(v Large) string {
	switch v {
	case 0:
		return "tag0"
	case 1:
		return "tag1"
	case 2:
		return "tag2"
	case 3:
		return "tag3"
	case 4:
		return "tag4"
	case 5:
		return "tag5"
	case 6:
		return "tag6"
	case 7:
		return "tag7"
	case 8:
		return "tag8"
	case 9:
		return "tag9"
	case 10:
		return "tag10"
	case 11:
		return "tag11"
	case 12:
		return "tag12"
	case 13:
		return "tag13"
	case 14:
		return "tag14"
	case 15:
		return "tag15"
	case 16:
		return "tag16"
	case 17:
		return "tag17"
	case 18:
		return "tag18"
	case 19:
		return "tag19"
	case 20:
		return "tag20"
	case 21:
		return "tag21"
	case 22:
		return "tag22"
	case 23:
		return "tag23"
	case 24:
		return "tag24"
	case 25:
		return "tag25"
	case 26:
		return "tag26"
	case 27:
		return "tag27"
	case 28:
		return "tag28"
	case 29:
		return "tag29"
	case 30:
		return "tag30"
	case 31:
		return "tag31"
	}
	return "Large(" + strconv.Itoa(int(v)) + ")"
}

func BenchmarkLargeString(b *testing.B) {
	b.Run("array", func(b *testing.B) {
		for i := 0; i < b.N; i++ {
			nameSink = Large(i & 31).String()
		}
	})
	b.Run("switch", func(b *testing.B) {
		for i := 0; i < b.N; i++ {
			nameSink = largeSwitch(Large(i & 31))
		}
	})
	b.Run("array-miss", func(b *testing.B) {
		for i := 0; i < b.N; i++ {
			nameSink = Large(32 + (i & 31)).String()
		}
	})
	b.Run("switch-miss", func(b *testing.B) {
		for i := 0; i < b.N; i++ {
			nameSink = largeSwitch(Large(32 + (i & 31)))
		}
	})
}
