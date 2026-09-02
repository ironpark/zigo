# GOALS

## Problem and the end result from the user's point of view

두 가지 모두 컴파일되지 않는 Go를 만든다. (C) `fn setTitle(self: *Terminal, t: []const u8) !void`는 receiver 변수명이 타입 이름 첫 글자 `t`라서 `func (t *Terminal) SetTitle(t []byte) error`가 되고 `t redeclared`로 실패한다. (D) `fn getPwd(self: *const Terminal) ?[:0]const u8`은 `([]byte, bool, error)`를 반환하는데 receiver/handle/range 검사 실패 경로가 `return nil, err`만 써서 `not enough return values`로 실패한다. panic 경로는 `nil, false, err`로 올바르다.

끝난 뒤: receiver 변수명은 파라미터 이름(및 생성 코드가 쓰는 지역 이름)과 충돌하지 않도록 밀리고, 검사 실패 경로는 optional 반환에서 `zero, false, err`를 돌려준다.

## Measurable goals

- `t` 파라미터를 가진 `Terminal` 메서드 골든이 `func (te *Terminal) SetTitle(t []byte)`처럼 충돌 없는 이름으로 컴파일된다.
- optional 반환 메서드(handle 검사, narrow int 범위 검사, optional handle 파라미터 각각)의 골든이 `go vet`을 통과한다.
- 기존 예제 생성물은 receiver 충돌이 없는 한 바이트 동일하다.

## Supported scope and non-goals

- 범위: `src/gen/emit.zig`의 receiver 변수명 계산과 `writeCheckedErrorReturn`, 골든 케이스, 예제 테스트, 문서, CHANGELOG.
- 비범위: 파라미터 이름이 생성 코드의 다른 지역 이름(`ptr`, `err`, `code`, `result`)과 충돌하는 문제는 별도 조사 항목으로만 기록.

## Reference source / commit / license

`src/gen/emit.zig:6917`(`receiverVariableAlloc`), `src/gen/emit.zig:3532-3536`(메서드 헤더), `src/gen/emit.zig:5205-5245`(`renderHandleChecks`), `src/gen/emit.zig:5266-5285`(`writeCheckedErrorReturn`). 라이선스 변경 없음.

## Completion criteria for the whole plan

모든 phase done, `zig build test`·`zig fmt --check`·전 예제 cgo+purego 녹색, CHANGELOG Unreleased에 Fixed 기재.
