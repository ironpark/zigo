package errors_test

import (
	"errors"
	calculator "example.com/zigo/errors/errors"
	"fmt"
)

func ExampleDivide() {
	value, err := calculator.Divide(12, 3)
	if err != nil {
		panic(err)
	}
	fmt.Println(value)
	_, err = calculator.Divide(12, 0)
	fmt.Println(errors.Is(err, calculator.ErrDivideByZero))
	// Output:
	// 4
	// true
}
