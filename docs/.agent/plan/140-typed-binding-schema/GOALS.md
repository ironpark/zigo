# GOALS

## Problem and the end result from the user's point of view

`zigo.define`은 익명 리터럴을 `@hasField`로 더듬어 읽는다. 그래서 모르는 키(`.doc`)가 조용히 버려지고, `.params`(위치)와 `.param_meta`(이름)가 따로 놀아 계약이 사라지며, 타입을 값으로 등록하고 이름 문자열로 참조해 오타가 런타임 진단으로만 잡힌다. 선언을 `zigo.Binding`·`zigo.Type`·`zigo.Function`·`zigo.Param` 같은 타입 구조체로 받으면 모르는 키, repr별 허용 키, 기본값을 Zig 컴파일러가 직접 검사하고, 파라미터 계약은 자리에 붙으며, 타입 참조는 값이 된다.

## Measurable goals

- `define(comptime binding: zigo.Binding)`. 반영 코드에서 선언에 대한 `@hasField` 덕타이핑이 사라진다.
- `.param_meta`, `.repr`, `.@"opaque"`, `.written = .@"return"`, 함수 항목의 `.semantic`/`.release`/`.go`, `.field_meta`, `.omit_variants`, `.exclude` 없는 `.discover` 제약 등 카탈로그의 불일치 14건이 해소된다.
- 예제 13개, 생성기 케이스, 문서가 새 문법이고 `zig build test`와 예제 go-check가 통과한다.

## Supported scope and non-goals

선언 문법만 바꾼다. IR(`semantic.json`), 생성기, C ABI, Go 생성물의 형태는 그대로다. 전환기·구 문법 호환은 두지 않는다. 함수 정렬은 하지 않는다(순서는 `.functions` 뒤 `.methods`).

## Reference source / commit / license

/tmp/zigo-syntax/probe.zig 탐침(타입 필드 union 슬라이스, `&.{}` 강제 변환, enum 리터럴→union, 오타의 네이티브 컴파일 에러 확인). 문법 카탈로그는 이 대화의 에이전트 보고.

## Completion criteria for the whole plan

네 phase 완료 후 `scripts/release.sh 0.15.0`이 통과한다.
