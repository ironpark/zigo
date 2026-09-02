# GOALS

## Problem and the end result from the user's point of view

`term.NewStream()`이 돌려주는 `Stream`은 ghostty의 `Handler.deinit`이 terminal을 통해 allocator를 얻으므로 `Terminal`보다 먼저 닫혀야 한다. 순서가 뒤집히면 use-after-free다. zigo에는 독립된 두 handle 사이의 순서를 표현할 수단이 없어 호출자 계약으로 남아 있다.

끝난 뒤: receiver를 가진 생성자(0.4.0)에 `.child_of_receiver = true` 같은 메타를 달면, 자식 handle이 부모를 참조로 잡아 부모 `Close()`가 열린 자식이 있는 동안 오류(`ErrHandleInUse`)를 돌려주거나(기본), 옵션에 따라 자식을 먼저 닫는다. 부모가 poison되면 자식도 poison된다.

## Measurable goals

- 골든·예제: 자식이 열린 채 부모 `Close()` → 오류, 자식 `Close()` 후 부모 `Close()` → 성공. race 테스트 통과.
- 메타 없는 생성자는 기존 동작·생성물 바이트 동일.

## Supported scope and non-goals

- 범위: 함수 메타, semantic.json 필드(옵션이 있을 때만), Go handle 구조(부모 참조·자식 카운트), cgo·purego, 골든, 예제 07(`Ticker`) 또는 03, 문서, CHANGELOG.
- 비범위: 임의 두 handle 사이의 순서, GC finalizer.

## Reference source / commit / license

`src/gen/emit.zig` handle lifecycle(`zigoAcquire`/`zigoRelease`/`zigoPoison`, `zigoCheckedPointer`), projection의 `parent` 참조 패턴, 플랜 75 phase 2(receiver 생성자). gostty `docs/zigo-findings.md` "알려진 제약". 라이선스 변경 없음.

## Completion criteria for the whole plan

모든 phase done, `zig build test`·`zig fmt --check`·전 예제 cgo+purego 녹색, CHANGELOG Unreleased Added.
