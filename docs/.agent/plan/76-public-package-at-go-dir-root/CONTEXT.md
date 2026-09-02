# SCOPE

- `build.zig`: `GoBindingsOptions.go_package_path: ?[]const u8`(기본 = `go_package`). `"."`은 루트를 뜻한다. 그 외는 `raw_package`와 같은 경로 검증 규칙. 공개 패키지 출력 디렉터리·raw colocation 판정(`raw_package == go_package_path`)·include/library 상대 경로 계산을 경로 기준으로 바꾼다.
- generator CLI: `--go-package-path` 추가(기본 = `--go-package`). emit이 raw import path(`<go_module>/<raw_package>`)와 공개 import path(`<go_module>` 또는 `<go_module>/<path>`)를 경로 기준으로 만든다. report에 경로 표시.
- stale 정리: 루트 발행 시 `go_dir` 루트의 사용자 파일(`go.mod`, 손으로 쓴 `.go`)은 마커가 없으므로 지워지지 않음을 테스트로 고정한다.
- 예제 하나(신규 12 또는 기존 03)를 루트 발행으로 전환하거나 추가해 cgo·purego 검증.
- 문서: `docs/configuration.md`(표·예시·import path), `docs/generated-code.md`(트리), `docs/limitations.md`, `CHANGELOG.md`.

# CONTEXT

## Current implementation and bottlenecks

- `build.zig:727`: `go_package`는 `validateGoPackageName`으로 식별자 검증 후 이름과 디렉터리에 함께 쓰인다.
- `build.zig:1093`: `raw_package`가 `go_package`와 같은 문자열이면 colocate. 경로 비교가 이름과 얽혀 있다.
- `build.zig:783`: `raw_source_dir = go_dir/raw_package.path`에서 cgo include/library 상대 경로를 계산한다. 루트 발행 + colocate면 `raw_source_dir = go_dir`이 된다.
- `emit.zig:1166` 부근: 공개 패키지 이름을 import path의 마지막 요소로도 쓴다.
- stale 정리(`build.zig:1064`)는 `go_dir` 전체를 걸어 마커가 있는 파일만 지우므로 루트 발행에도 안전하다.

## Target structure and invariants

- 이름과 경로는 분리된 두 값이다. `go_package`는 식별자이고 `go_package_path`는 `go_dir` 기준 상대 경로 또는 `"."`이다. 기본 `go_package_path = go_package`이므로 기존 프로젝트는 변화가 없다.
- 공개 import path = `go_module` + (`path == "."` ? `""` : `"/" + path`). raw import path는 지금처럼 `go_module/raw_package`.
- colocation 판정은 `raw_package == go_package_path`. `raw_package = "."`은 colocation 표기로만 허용하고 단독으로는 거부한다(`internal/raw`를 루트에 둘 이유가 없다).
- Go의 `internal/` 규칙상 `<go_dir>/internal/raw`는 `<go_dir>` 루트 패키지에서 import 가능하다.
- 루트 발행 시 생성 파일 이름이 사용자의 루트 파일과 충돌하지 않도록 기존 접미(`_cgo_gen.go` 등)를 유지한다.

## Implementation outcome and deviations

- 신규 12나 기존 03 대신, 이미 cgo와 purego를 함께 검증하는 `04-callback`을 루트 발행
  예제로 전환했다. 새 CI 열거 항목을 늘리지 않으면서 두 backend의 모듈 루트 import를 같은
  API로 검증하기 위한 선택이다.
- cgo 구성은 `go_package_path = raw_package = "."`으로 두어 `raw_source_dir == go_dir`일 때
  생성되는 `${SRCDIR}/../zig-out/{include,lib}` 경로까지 통합 검증한다. purego 공개 패키지도
  루트에 두되 raw는 기본 `internal/raw`에 유지했다. 기존 purego loader/registry 내부 테스트를
  보존하면서 루트 공개 패키지가 internal raw를 import하는 조합도 함께 검증하기 위해서다.
- `zig build go` 뒤에도 기존 `go.mod`와 hand-written 루트 테스트가 남고, CI가 생성 후 Git
  상태를 검사하는 기존 흐름으로 cleanup 보존 계약을 고정한다.
