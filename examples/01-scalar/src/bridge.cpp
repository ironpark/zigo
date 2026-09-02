#include "support.hpp"

extern "C" std::int32_t scalar_bridge_add(std::int32_t a, std::int32_t b) {
    return scalar_support_add(a, b);
}
