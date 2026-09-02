# SCOPE

- **A**: 자식 생성자가 receiver로 빌린 뷰를 받을 때 `zigoAcquireChild`와 `zigoDropChild`가 같은 소유 handle에 도달하게 한다. 뷰의 `zigoAcquireChild`는 `owner`로 위임하고, 자식이 보관하는 `parent`는 위임 결과의 소유 handle(또는 위임하는 뷰 — 어느 쪽이든 증가와 감소가 같은 대상)이어야 한다. 뷰의 `Close`/GC는 자식 카운트에 영향이 없어야 한다. 뷰가 다시 뷰를 빌려 주는 2단 위임도 같은 규칙.
- **B**: `validate.zig`에 C 식별자 공간 검사를 추가한다. 후보: 함수 심볼, 타입 c_name(handle typedef, enum typedef, struct typedef, snapshot 타입), enum 상수, release/콜백 트램폴린 등 헤더에 나타나는 모든 식별자. 충돌은 새 진단 코드로 두 선언을 함께 이름 짓고 `.name`/`.prefix`로 푸는 힌트를 준다. 검사는 lower 결과(실제 c_name) 기준으로 한다.
- **C**: `sliceReturnElement`와 `.returns = .caller` 검증이 `?[]T`, `!?[]T`를 slice로 인식하고, emit의 caller-owned slice 경로(복사 후 release)가 optional과 결합된다: 부재면 `nil, false, nil`, 존재면 복사·release 후 `data, true, nil`. c_string(`?[:0]const u8`) 변형도 확인.
- 예제: 07(빌린 뷰가 있는 예제)에 뷰의 자식 생성자와 optional slice caller 반환 추가; validate 스냅샷; 문서(`docs/bindings.md` 소유권·`.child_of_receiver`, `docs/limitations.md` C 심볼 규칙), CHANGELOG.

# CONTEXT

## Current implementation and bottlenecks

- 자식 예약은 부모 handle의 `zigoAcquireChild`(active++·children++)로, 해제는 자식이 보관한 `parent`의 `zigoDropChild`로 간다. 빌린 뷰는 lifecycle을 `owner`에 위임하지만 자식 예약 경로는 위임을 거치지 않거나, 자식이 `parent`로 뷰가 아닌 소유자를 잡아 감소만 소유자에게 간다. 정확한 경로는 phase 0에서 재현해 확인한다.
- Go 이름 충돌은 ZIGO021/ZIGO024가 검사하지만 C 이름은 `cTypeNameAlloc`/`functionSymbolAlloc`이 각자 만들 뿐 서로 비교하지 않는다.
- `sliceReturnElement`는 `.slice`와 `.error_union(.slice)`만 본다.

## Target structure and invariants

- 자식 카운트는 항상 소유 handle 하나에서만 증감하고, 뷰 계층이 몇 단이든 같은 대상에 도달한다.
- C 식별자 공간은 헤더 하나 안에서 유일해야 하며 진단이 생성 전에 이를 보장한다.
- optional slice의 소유권 의미는 slice와 같고, 부재는 release를 부르지 않는다.

## Implementation notes and deviations

- Phase 0 재현에서 borrowed view의 기존 `zigoAcquireChild`가 view-local `active`/`children`을
  증가시킨 뒤 `zigoRelease`는 owner로 위임해, 증가하지 않은 owning handle의 active를
  감소시키는 비대칭도 확인했다. 계획의 허용안 중 최종 owning handle을 reservation owner로
  반환·저장하는 방식을 택했고, cleanup 경로가 parent 예약을 보존하지 않던 누락도 함께 고쳤다.
- Phase 1은 별도 ABI IR을 만드는 대신 lower와 같은 naming 함수와 emission 조건을 validator에서
  사용해 cgo/purego의 실제 header 식별자 집합을 각각 계산했다. 기존의 더 구체적인 semantic·Go
  진단이 우선하도록 C 식별자 검사는 validator 후반에 둔다.
- Phase 2는 validation unwrap만으로 충분하지 않았다. caller-owned optional c_string도
  pointer+length 반환을 사용하도록 lower를 조정하고, 공개 error+optional tuple이 presence를
  보존하도록 emit 분기 순서를 함께 수정했다.
