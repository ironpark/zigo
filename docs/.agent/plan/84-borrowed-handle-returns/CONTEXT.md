# SCOPE

- **선언**: 함수 메타 `.returns = .borrowed`를 receiver 있는 메서드에 명시. reflection은 "명시된 borrowed"를 `SemanticFn`에 기록한다(예: `borrowed_return: true`, 명시일 때만 semantic.json에 나타남). receiver 없는 함수나 opaque 포인터가 아닌 반환에 붙으면 진단(다음 빈 ZIGO 코드).
- **수명 정책(이 플랜의 핵심 결정, phase 0에서 확정해 CONTEXT에 기록)**. 두 후보:
  1. **뷰 무효화(권장)**: 빌린 handle은 부모에 등록된 뷰다. 부모 `Close()`는 뷰가 네이티브 호출 중(`active > 0`)이면 그 호출이 끝날 때까지 기다리거나 `ErrHandleInUse`를 돌려주고, 아니면 모든 뷰를 `closed`로 표시한 뒤 닫는다. 뷰에는 `Close()`가 없다(또는 조기 분리용 no-op `Close()`를 둔다). 뷰는 네이티브 자원을 소유하지 않으므로 GC로 사라져도 안전하다. `switchScreen`처럼 호출마다 뷰를 돌려주는 API에 맞는다.
  2. **자식 거부(보고자 제안)**: 플랜 82의 `child_of_receiver` 기계를 그대로 써서, 뷰가 살아 있는 동안 부모 `Close()`가 `ErrHandleInUse`를 돌려준다. 뷰에 `Close()`가 필요하고(분리만 하고 네이티브 호출 없음) 호출자가 매번 닫아야 한다.
  어느 쪽이든 poison 전파는 82와 같다.
- **Go 표면**: 반환 타입은 T의 일반 handle 타입 그대로(`*Screen`). handle 구조체에 `borrowed`(또는 `owner`) 상태를 두어 `Close()`가 소멸자를 부르지 않게 한다. T에 생성자·소멸자 짝이 없어도 handle 타입이 생성되어야 한다(지금은 등록 opaque가 짝 없이 반환될 수 있는지 확인하고 필요하면 허용).
- **C/shim**: 포인터를 그대로 넘긴다. optional은 플랜 71 규칙, error union은 기존 코드 규칙.
- **abi_diff**: borrowed ↔ caller 전환은 breaking.
- **예제**: 07(purego 커버)에 부모 handle이 내부 객체를 빌려 주는 메서드를 추가하거나 03에 추가하고 07로 purego 커버.
- **문서**: `docs/bindings.md`(소유권 절에 `.borrowed` 명시), `docs/generated-code.md`(수명 표), `docs/limitations.md`, CHANGELOG.

# CONTEXT

## Current implementation and bottlenecks

- `Ownership` 기본값이 `.borrowed`라 "명시하지 않음"과 "빌린 handle 반환"이 구분되지 않는다. opaque 포인터 반환은 생성자 짝(caller)일 때만 의미가 있고, 그 외에는 lowering이 없거나 진단이다.
- 빌린 handle의 유일한 선례는 projection `*TRef`: receiver가 열려 있는 동안만 유효하고 부모 획득 실패 시 오류를 돌려준다.
- 플랜 82가 handle 구조체에 `children`/`parent`를 추가했고 `ErrHandleInUse`·`HandleInUseError`가 있다. 플랜 83이 lifecycle 헬퍼를 `internal/lifecycle`로 옮기는 중이므로, 이 플랜은 83 이후에 시작해 그 구조 위에서 구현한다.

## Target structure and invariants

- 빌린 handle은 네이티브 자원을 소유하지 않는다. 소멸자를 절대 부르지 않는다.
- 부모가 닫힌 뒤 빌린 handle의 모든 연산은 오류를 돌려주고(포인터를 만지지 않음), 부모가 poison되면 빌린 handle도 poison된다.
- 뷰가 네이티브 호출 중일 때 부모가 닫히는 경합은 불가능해야 한다(부모 Close가 뷰의 `active`를 확인).
- 같은 네이티브 포인터에 대한 뷰가 여러 개일 수 있다(호출마다 새 Go 값). 동일성 비교는 문서에서 약속하지 않는다.
