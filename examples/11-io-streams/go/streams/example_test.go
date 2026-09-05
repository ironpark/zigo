package streams_test

import (
	"bytes"
	"example.com/zigo/streams/streams"
	"fmt"
	"io"
	"strings"
)

func ExampleTee() {
	var output bytes.Buffer
	n, err := streams.Tee(strings.NewReader("hello\n"), &output)
	if err != nil {
		panic(err)
	}
	fmt.Printf("%d bytes: %q\n", n, output.String())
	// Output: 6 bytes: "hello\n"
}

func ExampleSource() {
	source, err := streams.NewSource([]byte("native bytes"))
	if err != nil {
		panic(err)
	}
	defer source.Close()
	data, err := io.ReadAll(source)
	if err != nil {
		panic(err)
	}
	fmt.Println(string(data))
	// Output: native bytes
}
