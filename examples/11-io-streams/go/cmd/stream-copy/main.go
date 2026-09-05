// stream-copy sends stdin through a Zig reader/writer function to stdout.
package main

import (
	"example.com/zigo/streams/streams"
	"fmt"
	"io"
	"os"
)

func run(input io.Reader, output io.Writer) error {
	_, err := streams.Tee(input, output)
	return err
}

func main() {
	if err := run(os.Stdin, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "stream-copy:", err)
		os.Exit(1)
	}
}
