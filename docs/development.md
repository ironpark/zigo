# 프로젝트 개발

이 문서는 zigo 자체를 수정하는 기여자를 위한 안내입니다. zigo를 라이브러리로 사용하는
경우에는 [시작 가이드](getting-started.md)를 참고하세요.

## 빠른 검증

저장소 루트에서 Zig 단위 테스트와 스냅샷 테스트를 실행합니다.

```bash
zig build test --summary all
```

특정 예제를 변경했다면 해당 디렉터리에서 생성물과 Go 동작을 함께 확인합니다.

```bash
cd examples/05-pipeline
zig build test go-check abi-check go-coverage --summary all
zig build go
(cd go && go test -count=1 ./...)
```

`go-check`를 `go`보다 먼저 실행하면 커밋된 생성물이 변경 전부터 오래되어 있었는지 구분하기
쉽습니다. `go` 실행 후에는 `git status --short`로 의도하지 않은 생성물 변경이 없는지 확인하세요.

## 전체 예제 검증

모든 cgo 예제를 확인하려면 저장소 루트에서 실행합니다.

```bash
for example in examples/*; do
  (cd "$example" && zig build test go-check abi-check go-coverage --summary all)
  (cd "$example/go" && go test ./...)
done
```

`go-coverage`는 생성물을 바꾸지 않고 공개 Zig 선언 중 bound, excluded, unbound 함수를
출력합니다. 새 예제에는 의도적으로 빠뜨린 public 함수가 없다면 100%가 출력되어야 합니다.
JSON renderer까지 확인할 때는 예제가 `coverage_json`에 연결한
`-Dcoverage-json=zigo/coverage.json`을 함께 넘깁니다.

생성된 Go package에 참조되지 않는 내부 helper가 남지 않았는지는 CI와 같은 `U1000`
검사로 확인합니다. 현재 CI 버전은 `staticcheck` v0.8.1입니다.

```bash
go install honnef.co/go/tools/cmd/staticcheck@v0.8.1
for module in $(find examples -maxdepth 4 -name go.mod -print | sort); do
  (cd "${module%/go.mod}" && staticcheck -checks U1000 ./...)
done
```

각 예제의 역할은 [예제 선택 가이드](examples.md)에 정리되어 있습니다. 특히 다음 예제는
변경 범위를 넓게 검증합니다.

- `05-pipeline`: 여러 타입과 콜백을 조합한 생성 파이프라인
- `07-event-queue`: 애플리케이션 형태의 수명과 extern struct 값 전달
- `08-telemetry-hub`: 큰 API 자동 발견과 생성 비용
- `09-type-relations`: 타입 간 참조
- `10-tagged-union`: projection과 snapshot 표현
- `11-io-streams`: `std.Io` 스트림 파라미터와 Go `io.Writer`/`io.Reader`
- `12-materialized`: 중첩 결과 트리의 단일 버퍼 직렬화와 accessor 대비 benchmark

## purego 검증

purego 바인딩을 가진 예제는 공유 라이브러리를 먼저 만들고 cgo를 끈 상태에서 테스트합니다.

```bash
for example in examples/04-callback examples/07-event-queue examples/08-telemetry-hub; do
  (cd "$example" && zig build purego-go purego-go-verify --summary all)
  (cd "$example/go-purego" && CGO_ENABLED=0 go test ./...)
done

(cd examples/10-tagged-union && zig build go go-verify -Dpurego --summary all)
```

`08-telemetry-hub`는 자동 내부 로더가 `../../zig-out/lib`에서 라이브러리를 찾습니다.
`10-tagged-union`의 로더 실패 경로 테스트는 `ZIGO_TEST_LIBRARY`와
`ZIGO_TEST_WRONG_LIBRARY`가 없으면 건너뜁니다. CI의 전체 플랫폼 매트릭스와 환경 변수 구성은
[`.github/workflows/ci.yml`](../.github/workflows/ci.yml)이 정본입니다.

공유 라이브러리 자체는 다음 도구로 검사할 수 있습니다. 확장자는 현재 플랫폼에 맞게
`.dylib` 또는 `.so`를 사용합니다. 두 도구 모두 POSIX 전용이므로 Windows CI 잡
(`purego-windows`, `cgo-windows`)은 아티팩트 검사 없이 Go 스위트만 실행합니다.

```bash
tests/inspect_shared_library.sh \
  examples/04-callback/zig-out/lib/libcallback_zigo.dylib \
  zg_last_error_message

zig build shared-library-smoke -- \
  examples/04-callback/zig-out/lib/libcallback_zigo.dylib \
  zg_last_error_message
```

## 문서 변경

사용자 문서의 옵션과 명령은 `build.zig`, `examples/`와 CI를 기준으로 확인합니다. 공개 동작이나
지원 범위를 바꾸면 [사용자 문서 목차](README.md)와 관련
[설계 문서](.agent/design/README.md)를 함께 갱신하세요. 상대 링크와 제목 앵커도 변경 후
검사해야 합니다.

## 릴리즈 절차

릴리즈는 `0.*` 형태의 태그를 푸시하면
[`.github/workflows/release.yml`](../.github/workflows/release.yml)이 자동으로 처리합니다. 그
전에 다음을 순서대로 합니다.

1. **CHANGELOG 절 작성**: `CHANGELOG.md`의 `## [Unreleased]` 아래 항목을 이번 릴리즈로
   옮기고, `## [x.y.z] - YYYY-MM-DD` 절로 바꿉니다. `### Breaking`/`### Added`/`### Changed`
   같은 [Keep a Changelog](https://keepachangelog.com/ko/1.1.0/) 분류를 유지하세요.
   `release.yml`은 `scripts/extract-changelog-section.sh`로 이 절만 그대로 추출해 GitHub
   릴리즈 노트로 씁니다.
2. **`build.zig.zon` 버전**: `.version` 필드를 같은 `x.y.z`로 올립니다.
3. **커밋과 태그**: 위 변경을 커밋하고 `git tag x.y.z`로 태그한 뒤 `git push && git push
   --tags`로 태그를 푸시합니다. 태그 이름은 `v` 접두어 없이 `CHANGELOG.md`의 절 이름과
   정확히 같아야 `extract-changelog-section.sh`가 절을 찾습니다.
4. **fetch 안내 갱신**: README와 [시작 가이드](getting-started.md)의
   `zig fetch --save git+https://github.com/ironpark/zigo#<태그>` 줄을 새 태그로 바꾸고, 이
   문서 변경도 릴리즈에 포함시킵니다(태그 자체는 재태그하지 않으므로 다음 커밋에 실려도
   됩니다).

태그 푸시가 일으키는 워크플로는 `zig build test --summary all`을 돌리고, 그 절을 추출해
`gh release create`(`GITHUB_TOKEN`, 저장소 기본 권한)로 GitHub 릴리즈를 만듭니다. 실제 태그
없이 워크플로 로직만 확인하려면 GitHub Actions에서 `Release` 워크플로를 `workflow_dispatch`로
수동 실행하세요 — 이미 `CHANGELOG.md`에 절이 있는 버전(예: 현재는 `0.2.0`)을 입력하면 빌드와
절 추출만 검증하고 릴리즈는 만들지 않습니다.
