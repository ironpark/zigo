# SCOPE

- `src/reflect/walk.zig`: 짝짓기 규칙에 메타 우선 경로 추가, 주입 제외 arity, `.params` 길이 검증.
- `src/gen/semantic.zig`: 생성자 함수의 Zig 호출 경로를 Go 소유자(`namespace`)와 분리해 표현.
- `src/gen/emit.zig`: shim 호출식이 선언 위치 기반 경로를 쓰도록 수정; release 호출에 주입 인자 전달.
- `src/gen/validate.zig`: `.release` 매칭에서 `injected != null` 제외, `ZIGO027`(.params 길이) 진단, `.constructs`/`.destroys` 오용 진단.
- 예제 하나(기존 third-party 성격 예제 또는 신규)에 root 생성자 케이스 추가, 골든·semantic.json 재생성.
- 문서: `docs/bindings.md`, `docs/limitations.md`, `docs/generated-code.md`, `CHANGELOG.md`.

# CONTEXT

## Current implementation and bottlenecks

- `walk.zig:104-116`: `isConstructorName` 정확 일치 + 반환 opaque 타입 + 같은 타입 `receiver`의 `isDestructorName` 함수가 있어야 짝. 짝이 되면 `function.namespace = type_name`으로 덮어쓴다.
- `emit.zig:694`: `receiver orelse namespace`를 `target.{owner}.{name}(` Zig 호출 경로로 쓴다. `namespace`는 Go 소유자 이름이면서 Zig 경로 역할을 겸하고 있어 root 함수가 짝지어지면 경로가 틀린다. `appendFunction`은 `.path`로 실제 선언 위치를 알고 있다.
- `walk.zig:199-209`: `concreteParamCount/Index`는 receiver만 제외한다. `metadata.params[output_index]`는 comptime 튜플 인덱싱이라 길이가 짧으면 `index N outside tuple` 컴파일 에러.
- 주입 파라미터는 `semantic.Parameter.injected`만 세팅되고 `params`에 남는다. `validate.zig:1190`은 `params.len != 1`이면 ZIGO016.
- `src/root.zig`는 release 함수가 allocator를 주입받지 못해 `.allocator = .smp_allocator`를 파일 상수로 한 번 더 적어 두 곳을 손으로 맞춘다.

## Target structure and invariants

- 함수 메타 `.constructs = "<Type>"`, `.destroys = "<Type>"`. 메타가 있으면 이름 규칙을 건너뛴다. `.constructs`는 반환이 그 opaque 타입(또는 `!*T`)이어야 하고, `.destroys`는 첫 파라미터가 그 타입 포인터여야 하며 둘이 모두 있어야 짝. 위반은 진단 (`ZIGO028`, 하나의 코드에 메시지로 구분).
- 이름 규칙은 메타가 없을 때의 fallback으로 유지하되, root 함수가 fallback으로 짝지어져도 호출 경로가 올바라야 한다.
- `SemanticFn`에 Zig 호출 경로(예: `zig_path` 또는 `owner_is_receiver` 구분)를 두고 `namespace`는 Go 쪽 그룹화 전용으로 한다. semantic.json 스키마 변경은 abi_diff·골든에 반영.
- `.params`는 receiver와 주입 파라미터를 뺀 개수와 정확히 같아야 하며, 불일치는 `ZIGO027`(기대 개수·실제 개수·함수 위치 표시). comptime에서 검출하되 `@compileError`가 아니라 기존 진단 채널로 내보낸다. comptime 채널이 불가능하면 `@compileError`에 ZIGO027 접두 메시지로 대체하고 CONTEXT에 기록.
- `.release` 매칭: `injected == null`인 파라미터만 세어 정확히 하나의 slice여야 한다. shim은 release 호출 시 바인딩의 allocator를 주입한다. `src/root.zig`의 중복 allocator 상수를 제거한다.

## Deviations recorded during implementation

- `src/root.zig`은 16줄짜리 `define` DSL뿐이고 allocator 상수를 중복해 두지 않았다. 제거할
  중복이 없어 그 항목은 수행하지 않았다.
- `ZIGO027`/`ZIGO028`은 reflection 단계에서 나므로 `validate.zig`의 진단 목록이 아니라
  `walk.zig`가 같은 `error[ZIGOxxx]: ... / hint:` 형식으로 출력하고 각각
  `error.ParamNameCount`, `error.ConstructorPairing`을 반환한다(`@compileError` 아님).
  스냅샷은 메시지 생성 함수(`paramNameCountMessage`, `pairingMessageAlloc`)를 문자열로
  검증하는 테스트다. `zig build test`가 stderr 출력을 실패로 보므로 테스트 빌드에서는
  출력만 생략한다.
- Zig 호출 경로는 `namespace`가 아니라 `SemanticFn.zig_path`(선언 경로 전체)로 분리했고,
  Go 소속은 `go_owner`로 새로 두었다. 기본값과 같으면 문서에 나타나지 않으므로 기존 예제의
  `semantic.json`은 그대로다. receiver를 가진 root 함수(`freeTicker`)와 `.name`으로 이름을
  바꾼 함수의 잘못된 호출 경로도 같이 고쳐진다.
- 주입 파라미터가 시그니처 비교에 들어가 있어 `abi-diff`가 allocator 추가를 breaking으로
  보고했다. `abi_diff.zig`의 파라미터 비교를 노출 파라미터만 훑도록 바꾸고, 대신 `go_owner`
  변경을 breaking으로 추가했다(계획에 없던 범위).
- 새 예제 대신 purego까지 도는 `07-event-queue`에 `Ticker`(root 레벨 `newTicker`/`freeTicker`,
  `.constructs`/`.destroys`)와 allocator를 받는 `freeLimits`를 넣었고, 골든은
  `tests/generator_cases/root_constructor`로 추가했다.
