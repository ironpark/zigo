# SCOPE

- `build.zig`: `addStandardSteps`가 `b.getInstallStep()`에 `install_library`를 걸고 `StandardStepOptions`로 끌 수 있게 함. `systemLibraryFlags` 옆에 `.other_step`(정적 라이브러리 Compile)과 `.static_path` 아카이브를 절대 경로로 수집하는 함수 추가, 정적 백엔드에서 LDFLAGS에 나열. `cgo_flags.extra_ldflags` 추가.
- `src/gen/cli.zig`, `src/main.zig`, `src/gen/generator.zig`, `src/gen/emit.zig`: `--extra-ldflags` 전달과 emit.
- `src/gen/validate.zig`: `hasConstructorInit`이 receiver 유무와 무관하게 `goOwner() == constructor.type`을 받아들임.
- `src/gen/emit.zig`(cgo·purego): receiver 메서드이면서 새 handle을 반환하는 생성자 경로. Go 시그니처 `func (t *Terminal) NewStream(...) (*Stream, error)`, receiver 획득/poison 규칙은 메서드 규칙, 반환은 생성자 규칙(caller 소유, 소멸자 짝, boxing 지원).
- 예제: 07 또는 03에 receiver 생성자 케이스 추가; 정적 링크 입력 케이스는 예제 하나에 작은 정적 C 라이브러리를 `addStaticLibrary`로 붙여 검증.
- 문서: `docs/bindings.md`, `docs/configuration.md`, `docs/generated-code.md`, `docs/limitations.md`, `CHANGELOG.md`.

# CONTEXT

## Current implementation and bottlenecks

- `validate.zig:1241`: `function.receiver != null`이면 생성자 init 후보에서 제외. `emit.zig:6916` `constructorForInit`은 receiver를 보지 않지만, 생성자 emit 경로는 receiver 없는 함수만 전제한다.
- `build.zig:1131`: `link_objects`에서 `.system_lib`만 LDFLAGS로 옮긴다. `.other_step` 정적 라이브러리와 `.static_path`는 무시된다. Zig는 정적 라이브러리를 링크하지 않으므로 그 입력은 결과 아카이브에 들어가지 않는다.
- `emit.zig:1378`: `ldflags_override`가 있으면 기본 아카이브 경로를 통째로 대체. `system_ldflags`는 그 뒤에 덧붙는다.
- `build.zig:886`: `addInstallArtifact`로 만든 `install_lib`은 `go-lib`/`go` 스텝에서만 의존된다.

## Target structure and invariants

- 생성자는 receiver를 가질 수 있다. `semantic.json`은 이미 `receiver: "Terminal"`, `go_owner: "Stream"`을 기록하므로 스키마 변경 없이 validate와 emit만 넓힌다. `constructors[]`의 `type`은 반환 타입이다.
- 정적 백엔드 LDFLAGS 순서: 바인딩 아카이브 → 모듈의 정적 링크 입력(선언 순서, 절대 경로) → `extra_ldflags` → `system_ldflags`. `ldflags`(override)는 앞 두 항목만 대체하고 `extra_ldflags`·`system_ldflags`는 그대로 붙는다.
- `.other_step`의 Compile 아티팩트는 `getEmittedBin()`의 절대 경로를 쓰고 install_library 스텝이 그 아티팩트에 의존하게 해 순서를 보장한다. 캐시 경로가 raw 파일에 들어가므로 `go-check`의 바이트 비교와 충돌하면 LDFLAGS 줄만 별도 생성 파일로 분리하는 것을 검토하고, 결정을 여기에 기록한다.
- 기본 install에 라이브러리를 거는 것은 `StandardStepOptions.install_library_by_default = true`로 끌 수 있다.
