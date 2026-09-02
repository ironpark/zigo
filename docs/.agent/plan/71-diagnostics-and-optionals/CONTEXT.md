# SCOPE

- `src/reflect/walk.zig:529-534`: optional 반영 확장. `src/gen/ir/semantic.zig`: `optional` 노드는 이미 있음(`:115, :185`), child 제한만 완화. `src/gen/validate.zig`: 위치 규칙, 공개 이름 충돌 진단. `src/gen/lower.zig`: presence + 값 lowering. `src/gen/emit.zig`: shim·C·raw·public. `src/gen/abi_diff.zig`.
- `src/gen/diagnostic.zig` `Site`에 `line`/`column` 선택 필드, `src/reflect/names.zig`가 함수·파라미터의 소스 위치를 semantic 문서에 기록(`semantic.json`에 `source: {path, line, column}` 선택 필드), `validate.zig`가 그것을 `Site`에 넣음. CLI 렌더링.
- `.github/workflows/release.yml`, README·`docs/getting-started.md`, `docs/development.md`.

# CONTEXT

## Current implementation and bottlenecks

- `?*T`(opaque)는 `pointer.is_optional`(`lower.zig:693`)로 NULL 전달. 다른 optional은 reflection에서 `@compileError`.
- `ZIGO007`은 `functionSymbolAlloc` 결과의 충돌만 본다. 공개 Go 이름은 `rawGoNameAlloc`과 별개로 마지막 세그먼트(또는 `.name`)에서 나온다.
- `diagnostic.Site{ path, declaration }`. `names.zig`는 `std.zig.Ast`로 함수 선언을 찾아 doc·파라미터 이름을 붙이므로 토큰 위치(`tree.tokenLocation`)를 얻을 수 있다. 다만 진단은 semantic.json 검증 단계(`validate.zig`)에서 나오고, 그 시점에 소스 위치를 알려면 문서에 실려 있어야 한다.
- CI는 `ci.yml` 하나. 릴리즈 워크플로 없음.

## Target structure and invariants

- **optional ABI**: 파라미터 `?T`(T가 스칼라·bool·enum·승격 정수)는 C에서 `bool has_x, T x` 두 인자. 반환 `?T`는 `bool` 반환 + `T *out`(또는 error union이면 상태 + `bool *out_has` + `T *out`). `?[]const u8`·`?[]T`는 `ptr == NULL`을 부재로(길이 0과 구별). `?ExternStruct`는 파라미터에서 `const T *`(NULL = 부재), 반환에서 `bool` + `T *out`. Go: 파라미터는 `*T`(nil = 부재)로 통일하되 스칼라는 `Optional[T]` 제네릭 대신 `*T`를 쓴다(단순함 우선, 문서화). 반환은 `(T, bool)` 또는 error union이면 `(T, bool, error)`. 슬라이스·문자열 파라미터는 Go `[]T`/`string`이 nil/빈 문자열로 부재를 표현할 수 없으므로 `*[]T`/`*string`. `semantic.json`은 기존 `optional` 노드 그대로. `abi_diff`: `T` ↔ `?T` 변경은 breaking.
- **공개 이름 충돌**: `validate.zig`에 공개 Go 이름(함수: 마지막 세그먼트 또는 `.name`; 메서드는 receiver별) 집합을 만들어 충돌 시 새 진단. 타입 이름·enum tag·callback 타입 이름의 충돌도 같은 검사. 메시지에 두 Zig 경로와 `.name` 힌트. 진단 코드는 시작 시점에 다음 번호 확인.
- **소스 위치**: `names.zig`가 함수마다 `source = { path, line, column }`를 기록(파라미터는 `line, column`만). `semantic.json`에 선택 필드로 직렬화(부재 허용, abi_diff는 무시). `validate.zig`의 모든 함수·파라미터 진단이 있으면 그것을 `Site`에 넣고, 없으면 지금처럼 `semantic.json`. 렌더링 `--> path:line:col (Owner.fn)`.
- **릴리즈**: `release.yml`이 `0.*` 태그 푸시에서 `zig build test`를 돌리고 CHANGELOG의 해당 절을 추출해 `gh release create`. `docs/development.md`에 절차(CHANGELOG 절 작성 → `build.zig.zon` 버전 → 태그 → 푸시). README·getting-started의 fetch를 `git+https://github.com/ironpark/zigo#<최신 태그>`로 하고 릴리즈 절차에 갱신 단계를 둔다.
