#include <stdint.h>

extern "C" int32_t fxp_div_q8_24(int32_t a, int32_t b) {
    if (b == 0) return 0x7FFFFFFF;  // max Q8.24 nếu chia 0
    int64_t a_shifted = ((int64_t)a) << 24;
    return (int32_t)(a_shifted / b);
}
