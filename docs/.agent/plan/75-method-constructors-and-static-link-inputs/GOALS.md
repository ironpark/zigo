# GOALS

## Problem and the end result from the user's point of view

libghostty-vt 바인딩에서 드러난 세 가지다. (A) `fn newStream(gpa: Allocator, terminal: *Terminal) !*Stream`은 receiver 규칙에 따라 `Terminal`의 메서드이면서 `Stream`의 생성자인데, `validate.zig` `hasConstructorInit`이 `receiver != null`을 거부해 ZIGO010으로 막힌다. (B) `.cgo_static`에서 zigo가 만드는 정적 아카이브는 모듈이 링크하는 다른 정적 아카이브(`link_objects`의 `.other_step`/`.static_path`), ubsan_rt, compiler_rt를 흡수하지 못하고, `cgo_flags.ldflags`는 기본 LDFLAGS를 대체만 하므로 덧붙일 방법이 없다. (C) `zig build`만 하면 `zig-out/lib`에 바인딩 라이브러리가 설치되지 않아 곧바로 `go test`가 실패한다.

끝난 뒤: `func (t *Terminal) NewStream() (*Stream, error)`가 생성되고, 정적 백엔드가 모듈의 정적 링크 입력을 LDFLAGS에 자동으로 나열하며 `extra_ldflags`로 덧붙일 수 있고, 기본 install이 라이브러리를 설치한다.

## Measurable goals

- receiver 있는 생성자 예제가 cgo·purego에서 통과하고, 반환 handle은 caller 소유·소멸자 짝을 가진다.
- 정적 아카이브를 링크 입력으로 가진 모듈의 예제(또는 테스트)에서 생성된 raw 파일의 `#cgo LDFLAGS`에 그 아카이브 절대 경로가 나열되고 `go build`가 링크된다.
- `cgo_flags.extra_ldflags`가 기본값 뒤에 덧붙는다.
- `zig build`만으로 `zig-out/lib`에 바인딩 라이브러리가 생긴다.

## Supported scope and non-goals

- 범위: `src/gen/validate.zig`, `src/gen/emit.zig`(생성자 경로), `build.zig`(링크 입력 수집, `extra_ldflags`, install), 문서, CHANGELOG, 예제/골든.
- 비범위: fat archive 병합(플랫폼별 ar/libtool 의존), doctor의 미해결 심볼 진단(선택 phase로만 남김), 동적 백엔드 변경.

## Reference source / commit / license

`src/gen/validate.zig:1239-1250`, `src/gen/emit.zig:6916-6940`, `src/gen/emit.zig:1370-1392`, `build.zig:111-136, 886, 1126-1150`. ghostty `src/build/GhosttyLibVt.zig:327` `CombineArchivesStep`는 참고만. 라이선스 변경 없음.

## Completion criteria for the whole plan

모든 phase done, `zig build test`·`zig fmt --check`·전 예제 cgo+purego 녹색, CHANGELOG Unreleased에 Added/Fixed 기재.
