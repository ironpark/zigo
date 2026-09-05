package callback_test

import (
	"errors"
	callback "example.com/zigo/callback"
	"fmt"
)

func ExampleApply() {
	rejected := errors.New("application rejected the value")
	_, err := callback.Apply(7, func(value int32) (int32, error) {
		return 0, rejected
	})
	fmt.Println(errors.Is(err, rejected))
	// Output: true
}
