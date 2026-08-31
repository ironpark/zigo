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
zig build test go-check abi-check --summary all
zig build go
(cd go && go test -count=1 ./...)
```

`go-check`를 `go`보다 먼저 실행하면 커밋된 생성물이 변경 전부터 오래되어 있었는지 구분하기
쉽습니다. `go` 실행 후에는 `git status --short`로 의도하지 않은 생성물 변경이 없는지 확인하세요.

## 전체 예제 검증

모든 cgo 예제를 확인하려면 저장소 루트에서 실행합니다.

```bash
for example in examples/*; do
  (cd "$example" && zig build test go-check abi-check --summary all)
  (cd "$example/go" && go test ./...)
done
```

각 예제의 역할은 [예제 선택 가이드](examples.md)에 정리되어 있습니다. 특히 다음 예제는
변경 범위를 넓게 검증합니다.

- `05-pipeline`: 여러 타입과 콜백을 조합한 생성 파이프라인
- `07-event-queue`: 애플리케이션 형태의 수명과 extern struct 값 전달
- `08-telemetry-hub`: 큰 API 자동 발견과 생성 비용
- `09-type-relations`: 타입 간 참조
- `10-tagged-union`: projection과 snapshot 표현

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
`.dylib` 또는 `.so`를 사용합니다.

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
