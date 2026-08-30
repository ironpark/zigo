package raw

/*
#include "zigo_tagged_union.h"

static uint8_t zg_test_project_flag_with_initial(
    const zg_value *self,
    uint8_t initial,
    uint8_t *result
) {
    *result = initial;
    return zg_value_project_flag(self, result);
}

static uint8_t zg_test_project_integer_with_null_output(const zg_value *self) {
    return zg_value_project_integer(self, NULL);
}

*/
import "C"

import "unsafe"

func projectFlagWithInitial(self unsafe.Pointer, initial uint8) (uint8, uint8) {
	var result C.uint8_t
	status := C.zg_test_project_flag_with_initial(
		(*C.zg_value)(self),
		C.uint8_t(initial),
		&result,
	)
	return uint8(result), uint8(status)
}

func projectIntegerWithNullOutput(self unsafe.Pointer) uint8 {
	return uint8(C.zg_test_project_integer_with_null_output((*C.zg_value)(self)))
}
