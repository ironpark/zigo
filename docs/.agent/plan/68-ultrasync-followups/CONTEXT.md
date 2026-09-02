# SCOPE

- `src/reflect/names.zig:14-30`: fallback 소스를 루트 모듈로.
- `src/gen/emit.zig`: `renderKeepAliveDefers`(:4452), union accessor 템플릿(:3231, :3970, :4003), 테스트 :5411; `writeSliceWrittenAssignments`(:623 부근)와 C 선언·raw·purego의 `_written` 출력; 필요 시 패닉 메시지 경로(:405-432, `errorForCode` 템플릿).
- `src/gen/lower.zig:120-129`: `.return`이면 `.slice_written` 파라미터를 붙이지 않는다.
- `src/gen/abi_diff.zig:89-90, 261-263`: `writtenEqual` 차이를 breaking으로.
- `examples/07-event-queue`(`.return` 사용처, 벤치마크 위치), `examples/01-scalar`(패키지 doc 예), 골든.

# CONTEXT

## Current implementation and bottlenecks

- `names.zig:18`은 `document.doc == null`일 때 `bindings_source`의 `//!`를 읽는다. `:25`에서 `root_path`를 읽어 doc 스캔에 쓰므로 루트 소스는 이미 손에 있다. 65가 01-scalar의 `bindings.zig`에 `//!` 시연을 넣었다.
- `renderKeepAliveDefers`는 receiver와 `.opaque_ptr` 파라미터마다 `defer runtime.KeepAlive`를 낸다(`:4459, :4464`). handle 검사(`renderHandleChecks`)가 성공한 handle마다 `defer x.zigoRelease()`를 내므로 중복. optional nil handle은 둘 다 no-op. 문자열·value struct 슬라이스 데이터의 `KeepAlive`(`:2169, :2171`)는 Go 포인터를 C에 넘기는 동안 필요하므로 대상이 아니다. `Close`의 `runtime.KeepAlive(c)`(`:3836`)도 `cleanup.Stop()` 뒤 필요.
- `lower.zig:120-129`가 `.out`이면 무조건 `_written`(`*usize`, role `.slice_written`)을 붙인다. shim `writeSliceWrittenAssignments`가 `.return`이면 `= result`, `.all`이면 `= _len`, 오류 경로 0. raw cgo(`:1099` `var {name}Written C.size_t`)와 purego(`:1966-1970` `uintptr`)가 변수를 선언해 넘기고 `.return`에서는 읽지 않는다. `abi_diff.writtenEqual`(`:261`)은 `.compatible`.
- 패닉 경로: Zig 패닉 핸들러 → `{prefix}_panic_bridge`가 thread-local 버퍼에 복사 → `longjmp` → C 래퍼가 `-2` 반환 → Go `errorForCode`가 `raw.LastErrorMessage()`(두 번째 cgo 호출)로 읽음. 두 호출 사이 goroutine 이동을 막으려 `LockOSThread`. 래퍼 자신은 `-2`를 반환하는 시점에 같은 스레드에서 메시지를 갖고 있다.

## Target structure and invariants

- 패키지 doc 순서: `go_package_doc` → 루트 모듈(`.root` 소스 파일)의 `//!` → 기본 문장. `bindings.zig`의 `//!`는 읽지 않는다. 문서와 01-scalar 예제를 맞춘다(`//!`를 `src/root.zig`로 옮긴다).
- handle 획득 경로에서 `KeepAlive` 제거. 남는 `KeepAlive`는 (a) `Close`, (b) Go 메모리 포인터 인자. 이 규칙을 `renderKeepAliveDefers` 주석과 `generated-code.md`에 적는다.
- `.return`: lowering이 `_written`을 생성하지 않고, shim은 `written` 대입 없이 반환값만, 헤더·raw·purego에 파라미터 없음. `.all`은 그대로. `abi_diff`: `writtenEqual` 차이는 `.breaking` "parameter written hint changed (C signature)". `ir_version`은 올리지 않는다(문서 형식 불변).
- `LockOSThread`: 07-event-queue에 Go 벤치마크(`Cancel`류 가벼운 error union 호출 vs 같은 함수를 `LockOSThread` 없이 호출하는 손으로 쓴 대조군)를 두고 ns/op 차이를 `docs/limitations.md`에 기록. 대체 설계는 phase 4에서만, 조건 충족 시. 후보: (a) error union 래퍼가 `-2`일 때 메시지를 전역 슬롯 배열에 넣고 슬롯 인덱스를 반환 코드에 인코딩(`-2 - slot`), Go가 인덱스로 한 번 더 읽고 해제 — 두 번째 호출은 남지만 스레드 고정 불필요; (b) Go가 `sync.Pool` 버퍼 포인터를 넘기고 래퍼가 `-2`에서 memcpy — cgo escape 비용 측정 필요. 어느 쪽이든 `last_error_message` 심볼 제거와 함께 breaking.
