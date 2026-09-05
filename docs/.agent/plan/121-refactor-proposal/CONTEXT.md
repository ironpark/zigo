# SCOPE

src/gen/emit/common.zig, src/gen/emit/handles.zig, src/gen/lower/ownership.zig,
src/gen/ir/abi.zig, src/reflect/walk.zig와 추출한 type_spelling, target_types, packages, pairing 모듈. helper 성능 개선은 별도 측정 작업으로 남긴다.

# CONTEXT

120-gen-simplify-cleanup의 구현 커밋 a5d77a0과 기준 테스트 450개 통과를 확인하고 완료 처리했다. handles는 타입마다 여러 lifecycle predicate를
조회하고 common은 타입 표기, 프로그램 분석, 구체 emitter를 함께 참조한다.
reflect/walk는 필드 접근자, 패키지 closure, 발견과 선언 검증을 함께 담당한다.
references.referencedHelpersAlloc은 수렴할 때까지 공개 출력을 반복 렌더링한다.
성능 병목 여부는 아직 측정하지 않았다.
