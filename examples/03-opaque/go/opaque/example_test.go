package opaque_test

import (
	"example.com/zigo/opaque/opaque"
	"fmt"
)

func ExampleContext() {
	counter, err := opaque.NewContext()
	if err != nil {
		panic(err)
	}
	defer counter.Close()

	total, err := counter.Add(3)
	if err != nil {
		panic(err)
	}
	fmt.Println(total)
	value, present, err := counter.MaybeTotal(false)
	if err != nil {
		panic(err)
	}
	fmt.Println(value, present)
	// Output:
	// 3
	// 0 false
}
