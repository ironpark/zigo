# GOALS

## Problem and the end result from the user's point of view

생성 트리는 `<go_dir>/<go_package>/`(공개)와 `<go_dir>/internal/raw/`(raw)로 고정이다. `go_package`는 Go 식별자이면서 하위 디렉터리 이름을 겸하므로 비우거나 `.`으로 둘 수 없고, Go 모듈 루트 자체를 공개 패키지로 만들 수 없다. raw 쪽은 `raw_package`를 공개 패키지 경로와 같게 두면 colocate되는 탈출구가 있지만 공개 패키지에는 대응물이 없다. gostty는 이 제약 때문에 공개 패키지를 `vt/`에 두었다.

끝난 뒤: 바인딩 옵션으로 공개 패키지의 **경로**를 따로 지정할 수 있고, `"."`이면 `go_dir` 루트에 발행되어 `import "<go_module>"`로 쓰인다. 패키지 이름은 계속 `go_package`(기본값 유지)다.

## Measurable goals

- `go_package_path = "."`인 예제가 cgo·purego에서 `go build`·`go test` 통과하고 import path가 `<go_module>`이 된다.
- 기본값(경로 = 이름)일 때 모든 기존 예제의 생성물이 바이트 동일하다.
- `raw_package == go_package_path`로 루트에 colocate하는 조합도 동작하거나, 지원하지 않으면 build.zig에서 명확히 panic한다.

## Supported scope and non-goals

- 범위: `build.zig` 옵션·검증·경로 계산·stale 정리, `src/gen/cli.zig`·`src/main.zig`·`src/gen/generator.zig`·`src/gen/emit.zig`의 import path 계산, report 출력, 문서, CHANGELOG, 예제/골든.
- 비범위: `go_dir` 밖으로 발행, 여러 공개 패키지, 패키지 이름을 경로에서 추론하는 규칙 변경.

## Reference source / commit / license

`build.zig:727-732`(go_package 해석), `build.zig:783`(raw_source_dir), `build.zig:1092-1104`(`resolveRawPackage`), `build.zig:1006-1080`(생성 마커 기반 stale 정리), `src/gen/emit.zig:1166`(패키지 이름/경로 사용), `docs/configuration.md:44-101`. 라이선스 변경 없음.

## Completion criteria for the whole plan

모든 phase done, `zig build test`·`zig fmt --check`·전 예제 cgo+purego 녹색, CHANGELOG Unreleased에 Added 기재.
