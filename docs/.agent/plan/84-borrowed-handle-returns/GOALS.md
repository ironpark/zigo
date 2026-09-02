# GOALS

## Problem and the end result from the user's point of view

`Terminal.switchScreen` 은 떠나는 화면 `!?*Screen`을 돌려주고 `Screen`은 터미널이 소유한다. 즉 caller-owned가 아니라 빌린 handle이다. zigo가 빌린 handle을 만드는 경로는 tagged union projection의 `*TRef` 하나뿐이고 일반 메서드에는 대응하는 축이 없다. `.returns = .caller`는 소유권 이전이라 맞지 않고 `.child_of_receiver`는 생성자에만 붙는다. libghostty-vt에서 아직 바인딩되지 않은 표면 대부분(Selection, search, snapshot, formatter)이 `Screen` handle 하나에 걸려 있다.

끝난 뒤: receiver를 가진 메서드에 `.returns = .borrowed`를 명시하면 `*T`, `?*T`, `!*T`, `!?*T`(T는 등록된 opaque 타입) 반환이 receiver에 수명이 묶인 빌린 handle이 된다. 빌린 handle로 T의 메서드를 호출할 수 있고, 부모가 닫히면 더 쓸 수 없다.

## Measurable goals

- 예제: 부모 handle의 메서드가 자식 뷰를 빌려 주고, 뷰의 메서드가 동작하며, 부모 `Close()` 뒤 뷰 사용이 `ErrHandleClosed` 계열 오류를 돌려주는 cgo·purego Go 테스트(`-race` 포함).
- `?*T` 반환은 `(*T, bool, error)` 형태(플랜 71의 optional 규칙)로 나가고 절대 위치 nil은 false.
- 명시 없이 opaque 포인터를 반환하는 비생성자 메서드는 진단으로 `.returns = .borrowed` 또는 `.caller`를 안내한다.
- 기존 예제 생성물 바이트 동일.

## Supported scope and non-goals

- 범위: 함수 메타 해석(`.returns = .borrowed`가 이미 기본값이므로 "명시됨"을 구분해 기록), semantic.json 필드(명시일 때만), validate 진단, cgo·purego emit(빌린 handle 구조·수명), abi_diff, 골든, 예제, 문서, CHANGELOG.
- 비범위: receiver 없는 함수의 빌린 반환(수명을 묶을 부모가 없음, 진단), 빌린 handle을 다시 caller-owned로 승격, 빌린 handle의 소멸자 호출.

## Reference source / commit / license

`src/gen/ir/semantic.zig:253`(`Ownership { borrowed, caller, library }`), `src/gen/validate.zig:250-260`(ZIGO015), 플랜 82의 자식 handle 기계(`emit.zig` `children`/`parent`/`ErrHandleInUse`, `typeHasDependentChildren`), tagged union projection의 `*TRef`(`docs/bindings.md:936, 993`), 플랜 71의 optional 반환 규칙. gostty 보고 B. 라이선스 변경 없음.

## Completion criteria for the whole plan

모든 phase done, `zig build test`·`zig fmt --check`·전 예제 cgo+purego 녹색, CHANGELOG Unreleased Added.
