# SCOPE

`static const size_t` offset 변수를 cgo가 정수 상수로 해석하는 C 표현으로 교체한다.

# CONTEXT

## Current implementation and bottlenecks

macOS에서는 통과하지만 Linux cgo가 file-scope `static const size_t`를 Go object의 외부
reference로 만들며, C translation unit의 내부 linkage definition과 연결되지 않는다.

## Target structure and invariants

offset은 실제 생성 header의 `offsetof`로 계속 계산한다. Go layout test의 비교 범위와 값은
유지하고 runtime function 또는 hard-coded offset을 도입하지 않는다.
