# SCOPE

src/gen/emit/common.zig, src/gen/emit/handles.zig, src/gen/lower/ownership.zig,
src/gen/ir/abi.zig, src/reflect/walk.zig. helper 성능 개선은 측정 후 별도 판단한다.

# CONTEXT

120-gen-simplify-cleanup은 진행 중으로 기록되어 있다. 해당 정리와 중복하지 않도록
구현 착수 전에 현재 결과를 확인한다. handles는 타입마다 여러 lifecycle predicate를
조회하고 common은 타입 표기, 프로그램 분석, 구체 emitter를 함께 참조한다.
reflect/walk는 필드 접근자, 패키지 closure, 발견과 선언 검증을 함께 담당한다.
references.referencedHelpersAlloc은 수렴할 때까지 공개 출력을 반복 렌더링한다.
성능 병목 여부는 아직 측정하지 않았다.
