# SCOPE

`build.zig`, `src/build_options.zig`, `src/reflect/`, `src/gen/{cli,emit}.zig`,
`examples/`, `docs/`.

# CONTEXT

## Current implementation and bottlenecks

- `backend`와 `link_mode`가 독립 옵션이지만 purego는 `.dynamic`을 강제하고 위반 시 `@panic`이다.
- `raw_package`는 `.internal`/`.colocated`/`.path` 세 갈래인데 앞의 둘은 특정 경로의 별칭이다.
- `types`와 `specializations`가 분리되어 있고 후자는 `.name`이 필수인 opaque 등록일 뿐이다.
- `repr`이 타입 종류와 접근 전략을 한 축에 섞는다 (`tagged_union` vs `tagged_union_value`).
- 명시 목록은 `.name` + `.@"fn"`, 자동 발견은 `.path` 문자열로 같은 메타데이터를 붙인다.
- `layout.<target>.json`은 스텁이며 아무도 읽지 않는다. reflector CLI 인자 두 개가 여기 묶여 있다.
- 생성된 Go의 에러가 `Error`(코드 비교), `HandleError`, 센티널, `LibraryError`로 갈린다.

## Target structure and invariants

- 옵션은 표현 가능한 상태만 갖는다. 불가능한 조합은 컴파일 단계에서 존재하지 않는다.
- 선언을 지칭하는 방법은 경로 하나다.
- 타입의 *종류*와 *접근 전략*은 서로 다른 축이다.
- 산출물은 소비될 때만 만든다.
- 각 phase는 독립적으로 릴리스 가능한 깨는 변경이며, 마이그레이션 표를 남긴다.
