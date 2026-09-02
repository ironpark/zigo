# GOALS

## Problem and the end result from the user's point of view

gostty가 0.6.0에서 만난 세 가지다. (A) `.child_of_receiver = true` 생성자의 receiver가 **빌린** handle(`.returns = .borrowed` 뷰)이면 자식 등록과 해제가 서로 다른 소유자에게 가서 부모 카운트가 음수가 되고, 그 뒤 부모는 영원히 닫히지 않는다(`Terminal.Close: handle has open children: -1`). (B) 등록 타입의 C typedef(`zg_search_select`)와 함수 심볼(`Search.select` → `zg_search_select`)이 같은 이름을 만들면 헤더가 컴파일되지 않는데 진단이 없다. (C) `!?[]const u8` 반환에 `.returns = .caller`를 붙이면 optional을 slice로 보지 못해 ZIGO015로 거부된다. 문서는 optional slice가 slice의 소유권 규칙(`.release` 포함)을 따른다고 한다.

끝난 뒤: 빌린 뷰에서 만든 자식도 소유 handle의 카운트에 정확히 반영되어 자식을 닫으면 부모가 닫힌다. C 심볼 충돌은 생성 전에 진단된다. optional slice(`?[]T`, `!?[]T`)를 caller-owned로 반환하고 `.release`로 해제할 수 있다.

## Measurable goals

- Go 테스트(cgo·purego, `-race`): 소유 handle → 빌린 뷰 → 자식 생성 → 자식 Close → 부모 Close 성공; 자식이 열린 동안 부모 Close는 `ErrHandleInUse`(카운트 1); 뷰만 꺼내 두는 것은 카운트 무영향.
- validate 스냅샷: 타입 typedef ↔ 함수 심볼, 두 함수 심볼, enum 상수 ↔ 타입 등 C 식별자 충돌이 진단된다.
- 골든: `!?[]const u8` + `.returns = .caller` + `.release`가 Go `([]byte, bool, error)`로 나가고 release가 호출된다.
- 기존 예제 생성물 바이트 동일.

## Supported scope and non-goals

- 범위: `emit.zig`의 자식 카운트 경로(빌린 receiver), `validate.zig`의 C 심볼 공간 검사와 optional slice 소유권, `lower.zig` 필요 시, 골든, 예제, 문서, CHANGELOG.
- 비범위: C 심볼 충돌의 자동 회피(진단만), 빌린 뷰 자체를 부모의 자식으로 세는 정책 변경.

## Reference source / commit / license

`src/gen/emit.zig:5525-5545`(`zigoAcquireChild`/`zigoDropChild`, 뷰의 `zigoAcquire` 위임), 플랜 84 CONTEXT(뷰는 `owner` 필드로 부모 lifecycle에 위임), `src/gen/validate.zig:1520-1527`(`sliceReturnElement`), `:250-260`(ZIGO015), `src/gen/lower.zig:719, 797, 817, 840`(`cTypeNameAlloc`), `src/gen/naming.zig:45`(`functionSymbolAlloc`), ZIGO021/ZIGO024(Go 이름 충돌). 라이선스 변경 없음.

## Completion criteria for the whole plan

모든 phase done, `zig build test`·`zig fmt --check`·전 예제 cgo+purego 녹색, CHANGELOG Unreleased Fixed 세 건.
