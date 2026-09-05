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
set -eu
for example in examples/*; do
  (cd "$example" && zig build test go-check go-lib abi-check go-coverage --summary all)
  (cd "$example/go" && go test ./...)
done
```

`go-coverage`는 생성물을 바꾸지 않고 공개 Zig 선언 중 bound, excluded, unbound 함수를
출력합니다. 새 예제에는 의도적으로 빠뜨린 public 함수가 없다면 100%가 출력되어야 합니다.
JSON renderer까지 확인할 때는 예제가 `coverage_json`에 연결한
`-Dcoverage-json=zigo/coverage.json`을 함께 넘깁니다.

아래 purego 검증까지 실행해 모든 모듈의 생성물과 라이브러리를 준비한 다음,
생성된 Go package에 참조되지 않는 내부 helper가 남지 않았는지는 CI와 같은 `U1000`
검사로 확인합니다. 현재 CI 버전은 `staticcheck` v0.8.1입니다.

```bash
go install honnef.co/go/tools/cmd/staticcheck@v0.8.1
set -eu
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
set -eu
for example in examples/03-opaque examples/04-callback examples/07-event-queue examples/08-telemetry-hub \
  examples/11-io-streams examples/12-materialized; do
  (cd "$example" && zig build purego-go purego-go-verify --summary all)
  (cd "$example/go-purego" && CGO_ENABLED=0 go test ./...)
done

(cd examples/10-tagged-union && zig build go go-verify -Dpurego --summary all)
(cd examples/10-tagged-union/go-purego && CGO_ENABLED=0 go test ./...)
```

`08-telemetry-hub`는 자동 내부 로더가 설정된 `zig-out/purego-layout/lib`의
`telemetry_native` 공유 라이브러리를 찾습니다.
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

## 코드 구조

생성기는 `semantic.json`을 읽어 `lower`가 `abi.Program`으로 낮추고, emit이 그 프로그램만 읽어
파일을 씁니다. 함수 하나에 대한 결정은 낮추는 단계에서 한 번 내리고 emit과 validate는 읽기만
합니다. 예를 들어 `Must` 변형을 낼지(`AbiFn.must_variant`), 콜백이 Go error를 낼 수
있는지(`AbiFn.reaches_callback_errors`), materialized 결과가 어느 layout인지는 모두
`src/gen/lower.zig`와 `src/gen/lower/`가 정합니다. 같은 사실을 emit이나 validate에서 다시 계산하지 마세요.

- `src/gen/emit/`: 출력 대상과 책임별로 나뉩니다. `emit.zig`가 emitter 표와 파일
  이름을 가지고, `shim.zig`(Zig shim), `header.zig`(C 헤더), `raw.zig`(cgo raw 패키지),
  `purego.zig`(purego raw 패키지), `callbacks.zig`, `public.zig`(공개 함수 wrapper와 파일
  배선), `public_types.zig`, `public_runtime.zig`, `public_writers.zig`, `must.zig`,
  `materialized.zig`, `interfaces.zig`, `docs.zig`가 각 출력을 맡습니다. `common.zig`는 타입 철자와 이름,
  프로그램 전체 predicate처럼 여러 출력이 공유하는 helper입니다.
- 핸들의 생성자·해제 함수 연결과 소유권 판정은 `lower/ownership.zig`가 담당합니다.
  `lower.zig`는 기존 진입점을 유지하고, `emit/handles.zig`는 판정 결과로 Go 핸들 타입과
  호출·종료·정리 런타임을 생성합니다. 일반 공개 타입 출력은 `emit/public_types.zig`에 둡니다.
- Materialized의 레이아웃과 ABI 출력 슬롯은 `lower/materialized.zig`, Zig 직렬화는
  `emit/materialized_encoder.zig`, Go 디코딩은 `emit/materialized_decoder.zig`가 담당합니다.
  `emit/materialized.zig`는 native 호출과 이 직렬화기를 연결합니다. 버퍼 형식 상수는
  `ir/abi.zig`의 `MaterializedLayout`을 기준으로 유지합니다.
- 스트림 콜백의 공통 읽기 처리와 cgo·purego 진입점은 `emit/stream_callbacks.zig`에
  모읍니다. 콜백 등록·수명 관리는 `callbacks.zig`, Zig I/O 어댑터는 `stream_adapter.zig`에
  남겨 각 책임을 분리합니다.
- `tool_probe.zig`는 명령 구성·실행과 결과 버퍼의 소유권을 담당하고, `doctor.zig`는
  결과 해석과 표시를 담당합니다. `Result`는 실행 여부, 오류, 종료 상태, stdout·stderr를
  보존하며 `deinit`으로 해제합니다. 명령 테스트에는 주입 가능한 `Runner`를 사용해 전체
  argv를 검사하고, 실제 `CC="zig cc"` 검증도 유지합니다.
- 공개 패키지의 helper(`zigo<T>ToRaw`, `boolToUint8`, materialized decoder 등)는 렌더링한
  본문에서 참조된 식별자를 읽어 낼지 정합니다(`emit/references.zig`). import 블록과 같은
  방식이므로 emit 지점을 추가할 때 별도의 "사용 여부" predicate를 만들 필요가 없습니다.
- `src/gen/validate/`: `validate.zig`의 `rules` 표가 진단 우선순위입니다. 먼저 나열된 규칙이
  먼저 이깁니다. 규칙과 helper는 `packages`, `names`, `functions`, `callbacks`, `types`,
  `ownership`, `materialized`, `interfaces`, `site`로 나뉘고, 전체 진단 스냅샷 테스트는
  `snapshot_tests.zig`에 있습니다.
- `build.zig`는 소비자가 쓰는 `Options`, `GoBindings`, `addGoBindings`만 가집니다. 이 저장소의
  테스트와 `check`/`snapshot`/`shared-library-smoke` 단계는 `build/tests.zig`, 생성기 모듈
  그래프는 `build/modules.zig`, `addGoBindings`가 배선하는 custom step은 `build/steps.zig`에
  있습니다.

### 백엔드 공통 계약 테스트

`tests/runtime_contracts`는 생성 코드에 의존하지 않는 Go 테스트 모듈입니다. 스트림의 빈 읽기·
오류·대용량 처리, Materialized 디코더 범위 검사, 핸들의 동시 호출과 `Close` 경합을
한곳에서 정의합니다. 예제 04·10·11·12의 cgo·purego 테스트는 각 백엔드의 함수를
이 테스트에 연결합니다. 콜백 등록 해제나 유니온 projection처럼 타입별로 다른 검증은
각 예제에 유지합니다.

예제의 `go.mod`는 로컬 `replace`로 이 모듈을 참조하므로 테스트할 때 저장소의 디렉터리
구조를 유지하세요. 일반 `go test ./...`가 공통 테스트를 함께 실행하며, 공통 모듈만 따로
실행하는 것은 네이티브 바인딩 검증을 대신하지 않습니다.

구조만 바꾸는 리팩토링에서는 먼저 `zig build test`와 각 예제의 `go-check`를 실행하세요.
스냅샷을 갱신해야 한다면 단순 구조 변경이 아닌 이유를 별도로 확인해야 합니다.

## 문서 변경

사용자 문서의 옵션과 명령은 `build.zig`, `examples/`와 CI를 기준으로 확인합니다. 공개 동작이나
지원 범위를 바꾸면 [사용자 문서 목차](README.md)와 관련
[설계 문서](.agent/design/README.md)를 함께 갱신하세요. 상대 링크와 제목 앵커도 변경 후
검사해야 합니다.

가독성과 서식은 다음 기준으로 맞춥니다.

- 문서 첫머리에 대상 독자와 완료할 작업을 적고, 기본 사용법을 선택 기능보다 먼저 설명합니다.
- 표에는 짧은 비교값을 넣습니다. 긴 조건·예외는 표 아래 문단이나 별도 소제목으로 분리합니다.
- 생성 API의 시그니처는 `text`, 호출 코드는 `go`, 부분 선언은 `zig` 코드 블록으로 구분합니다.
  실행 가능한 예제라면 파일 위치·실행 명령·기대 결과를 함께 제시합니다.
- 본문은 존댓말로 쓰고, API 식별자는 원래 철자를 유지합니다. 강조를 소제목 대신 쓰지 않습니다.
- 내부 구현 설명은 참조 문서로 연결합니다. 제목 앵커를 바꾸면 기존 링크도 함께 갱신합니다.

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
3. **fetch 안내 갱신**: README와 [시작 가이드](getting-started.md)의
   `zig fetch --save git+https://github.com/ironpark/zigo#<태그>` 줄을 새 태그로 바꿉니다.
   버전·변경 기록·설치 안내가 같은 릴리즈 커밋에 포함되어야 합니다.
4. **검증과 커밋**: 위 테스트와 생성물 검사를 마친 뒤 변경을 검토하고 커밋합니다.
5. **태그와 푸시**: 검증한 커밋에 `git tag x.y.z`로 태그합니다. `git push origin HEAD`로
   브랜치를, `git push origin x.y.z`로 해당 태그만 푸시합니다. 태그 이름은 `v` 접두어 없이
   `CHANGELOG.md`의 절 이름과 정확히 같아야 합니다. 원격 이름이 다르면 `origin`을 바꾸세요.

태그 푸시가 일으키는 워크플로는 `zig build test --summary all`을 돌리고, 그 절을 추출해
`gh release create`(`GITHUB_TOKEN`, 저장소 기본 권한)로 GitHub 릴리즈를 만듭니다. 실제 태그
없이 워크플로 로직만 확인하려면 GitHub Actions에서 `Release` 워크플로를 `workflow_dispatch`로
수동 실행하세요 — 이미 `CHANGELOG.md`에 절이 있는 버전(예: 현재는 `0.2.0`)을 입력하면 빌드와
절 추출만 검증하고 릴리즈는 만들지 않습니다.
