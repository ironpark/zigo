# zigo에 기여하기

이 문서는 zigo 자체를 수정하고 검증하는 방법을 설명합니다. zigo를 라이브러리에서 사용하는
방법은 [사용자 문서](docs/README.md)를 참고하세요.

## 기본 검증

저장소 루트에서 Zig 단위 테스트와 generator snapshot 테스트를 실행합니다.

```bash
zig build test --summary all
```

generator 출력이 의도적으로 달라졌다면 필요한 case만 갱신하고 diff를 검토합니다.

```bash
scripts/update-generator-cases.sh [case ...]
git diff -- tests/generator_cases
```

snapshot 변경은 공개 생성 코드의 변경입니다. 단순 refactor에서 snapshot이 바뀌었다면 먼저
원인을 확인하세요.

## 예제 검증

변경과 가장 가까운 예제에서 커밋된 생성물을 먼저 검사한 뒤 다시 생성합니다.

```bash
cd examples/05-pipeline
zig build test go-check abi-check go-coverage --summary all
zig build go
(cd go && go test -count=1 ./...)
```

전체 cgo 예제는 저장소 루트에서 확인할 수 있습니다.

```bash
set -eu
for example in examples/*; do
  (cd "$example" && zig build test go-check go-lib abi-check go-coverage --summary all)
  (cd "$example/go" && go test ./...)
done
```

purego를 제공하는 예제는 공유 library를 만든 뒤 cgo를 끄고 테스트합니다.

```bash
set -eu
for example in examples/03-opaque examples/04-callback examples/07-event-queue \
  examples/08-telemetry-hub examples/11-io-streams examples/12-materialized; do
  (cd "$example" && zig build purego-go purego-go-verify --summary all)
  (cd "$example/go-purego" && CGO_ENABLED=0 go test ./...)
done

(cd examples/10-tagged-union && zig build go go-verify -Dpurego --summary all)
(cd examples/10-tagged-union/go-purego && CGO_ENABLED=0 go test ./...)
```

CI의 전체 플랫폼과 환경 변수 구성은 [`.github/workflows/ci.yml`](.github/workflows/ci.yml)이
정본입니다.

## 코드 구조

```text
build.zig                 public build API
build/                    repository build wiring and tests
src/reflect/              Zig declarations → semantic model
src/gen/lower/            semantic model → ABI program
src/gen/validate/         diagnostics and contract validation
src/gen/emit/             Zig, C and Go output
src/gen/plugins/          built-in generator plugins
src/plugin.zig            external plugin contract
tests/generator_cases/    generated-output snapshots
tests/runtime_contracts/  backend-independent Go contracts
examples/                 end-to-end projects
```

함수 하나의 ABI, ownership과 결과 표현은 lowering 단계에서 한 번 결정합니다. emitter와
validator에서 같은 결정을 다시 추론하지 마세요. 생성된 public helper는 렌더링한 본문에서
참조될 때만 출력되어야 합니다.

## 문서 변경

공개 옵션과 step은 `build.zig`, binding 문법은 `src/author.zig`·`src/declare.zig`와 예제,
지원 동작은 테스트와
CI를 기준으로 확인합니다.

- 사용자 문서는 존댓말로 씁니다.
- 첫 문단에 대상과 완료할 작업을 적습니다.
- 실행 가능한 코드는 파일 위치, 명령과 기대 결과를 함께 적습니다.
- 옵션, 타입 대응과 지원 여부는 정본 reference에서만 완전하게 나열합니다.
- 제목을 바꾸거나 파일을 옮기면 Markdown link와 anchor를 함께 검사합니다.
- 내부 구현 설명은 `docs/internals/` 또는 `docs/.agent/`에 둡니다.

## 릴리스

릴리스 전 `CHANGELOG.md`의 `Unreleased` 내용을 새 버전 절로 옮긴 뒤 다음 script를 깨끗한
작업 트리에서 실행합니다.

```bash
scripts/release.sh 0.21.2
```

script는 검사, `build.zig.zon` 버전 갱신, 문서의 fetch version 갱신, commit과 tag 생성을
수행합니다. 검토 후 원격까지 보낼 때만 `--push`를 사용합니다.

```bash
scripts/release.sh 0.21.2 --push
```

tag에는 `v` 접두어를 붙이지 않습니다. `.github/workflows/release.yml`은 `0.*` tag를 받아
검증하고 해당 changelog 절로 GitHub release를 만듭니다.
