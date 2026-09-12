# SCOPE

건드리는 곳:

- `src/author.zig`, `src/dsl.zig`, `src/declare.zig`, `src/normalize.zig` -- `zigo.session` 선언
- `src/gen/ir/semantic.zig`, `src/gen/ir/abi.zig` -- session 선언의 IR 표현
- `src/gen/plugins/` -- 새 내장 플러그인 `SESSION`과 `src/gen/plugins/builtins.zig` 등록
- `src/reflect/names.zig` -- `Session` 타입 이름과 접근자 이름의 충돌 검사
- `src/gen/validate/` -- 관계·패키지·중복 진단
- `docs/reference/diagnostics.md` -- 새 진단 코드
- `examples/07-event-queue` -- 인수 예제와 Go 테스트
- `docs/authoring/objects-and-lifetimes.md`, `docs/reference/binding-api.md`,
  `docs/reference/generated-go-api.md`, `CHANGELOG.md`

건드리지 않는 곳: `src/gen/emit/shim.zig`, `header.zig`, `raw.zig`, `purego.zig`,
`src/gen/emit/handles.zig`의 수명 계산, `src/gen/emit_rust/`.

# CONTEXT

## Current implementation and bottlenecks

dependent 자식은 부모 핸들 구조체의 `children int` 필드로 추적됩니다
(`src/gen/emit/handles.zig:51`). 자식 생성자는 `zigoAcquireChild`로 카운터를 올리고
(`:168`), 자식의 `Close`는 `zigoDropChild`로 내립니다(`:188`, `:248`). 부모의 `Close`는
`children != 0`이면 `*HandleInUseError`를 돌려주고 네이티브 객체를 해제하지 않습니다
(`:260`, `:277`). 이 설계 자체는 옳습니다. 부모를 먼저 해제하면 자식의 네이티브
포인터가 dangling이 되므로, 거절이 유일하게 안전한 답입니다.

문제는 그 위에 아무 것도 없다는 점입니다. 생성 패키지는 "무엇이 무엇의 자식인지"를
런타임에 이미 알고 있는데, 그 지식을 소비자에게 올바른 순서로 닫아 주는 형태로는
내주지 않습니다. 소비자는 같은 관계를 Go 쪽에서 손으로 다시 적습니다.

합성 Go 타입을 만드는 경로는 이미 있습니다. `zigo.interface` 선언은 어떤 Zig 선언에도
1:1로 대응하지 않는 Go 코드를 전용 파일에 씁니다(`src/gen/plugins/interfaces.zig`).
Session은 그 경로를 재사용합니다.

## Target structure and invariants

- `Session`은 **입양 컨테이너**입니다. 멤버 핸들을 받아 보관하고, 접근자로 돌려주고,
  올바른 순서로 닫습니다. 네이티브 호출을 하지 않으므로 C 표면에 아무 영향이 없습니다.
- 닫는 순서는 선언 순서가 아니라 **IR의 부모-자식 관계에서 유도**합니다. 자식이 먼저,
  primary가 마지막입니다. 선언에 적힌 `children`이 실제로 primary의 dependent child인지
  검증하고, 아니면 진단으로 거절합니다.
- `Close`는 멱등이고 동시 호출에 안전합니다. 한 멤버의 실패가 다른 멤버의 닫기를
  막지 않으며, 모든 오류는 `errors.Join`으로 합쳐 돌려줍니다.
- `nil` 멤버는 허용합니다. 조건부로 만들어지지 않은 자식을 건너뜁니다.
- 생성 코드는 `var _ io.Closer = (*Session)(nil)`을 함께 씁니다. 계약이 깨지면
  소비자 빌드가 아니라 이 패키지의 빌드가 먼저 실패합니다.
- 이름은 `interfaces`와 같은 공개 이름 공간 검사를 받습니다.
