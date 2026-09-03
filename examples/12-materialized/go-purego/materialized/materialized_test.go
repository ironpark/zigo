package materialized

import "testing"

func checkProbe(t testing.TB, got Probe) {
	t.Helper()
	if got.ID != 0xfeedbeef || !got.Active || got.Status != StatusReady || got.Name != "materialized" {
		t.Fatalf("scalar fields = %+v", got)
	}
	if len(got.Codes) != 3 || got.Codes[1] != -7 || len(got.Tags) != 2 || got.Tags[1] != "beta" {
		t.Fatalf("slice fields = %+v / %+v", got.Codes, got.Tags)
	}
	if got.Embedded.Label != "leaf" || got.Child == nil || got.Child.Value != 42 || got.Maybe != nil {
		t.Fatalf("nested fields = %+v / %+v / %+v", got.Embedded, got.Child, got.Maybe)
	}
	if len(got.Children) != 2 || got.Children[1].Label != "second" || got.Children[1].Enabled {
		t.Fatalf("children = %+v", got.Children)
	}
	if len(got.Child.Samples) != 3 || got.Child.Samples[2] != 9.75 {
		t.Fatalf("samples = %+v", got.Child.Samples)
	}
}

func TestMaterializedPositions(t *testing.T) {
	checkProbe(t, Snapshot())
	batch, err := ProbeMany()
	if err != nil {
		t.Fatal(err)
	}
	if len(batch) != 128 {
		t.Fatalf("ProbeMany returned %d items", len(batch))
	}
	checkProbe(t, batch[127])

	output := make([]Probe, 3)
	if written := Fill(output); written != uint(len(output)) {
		t.Fatalf("Fill wrote %d items", written)
	}
	checkProbe(t, output[2])
}

func BenchmarkMaterializedDecode(b *testing.B) {
	for range b.N {
		values, err := ProbeMany()
		if err != nil {
			b.Fatal(err)
		}
		if len(values) != 128 {
			b.Fatal(len(values))
		}
	}
}

func BenchmarkAccessorHandles(b *testing.B) {
	for range b.N {
		for i := range 128 {
			value, err := NewLegacyProbe(uint(i))
			if err != nil {
				b.Fatal(err)
			}
			if _, err := value.ID(); err != nil {
				b.Fatal(err)
			}
			if _, err := value.Active(); err != nil {
				b.Fatal(err)
			}
			child, err := value.Child()
			if err != nil {
				b.Fatal(err)
			}
			if _, err := child.Value(); err != nil {
				b.Fatal(err)
			}
			if err := value.Close(); err != nil {
				b.Fatal(err)
			}
		}
	}
}
