# 프로젝트 개발

## 기본 검증

저장소 루트에서 Zig 단위 테스트와 스냅샷 하네스를 실행한다.

```bash
zig build test --summary all
```

각 예제는 독립 Zig/Go 프로젝트다. 생성물 동기화, ABI와 Go 동작을 함께 검사한다.

```bash
for example in examples/*; do
  (cd "$example" && zig build test go-check abi-check --summary all)
  (cd "$example/go" && go test ./...)
done
```

## purego 백엔드 검증

purego 바인딩을 가진 예제는 별도 스텝으로 생성하고, C 컴파일러 없이 테스트한다.

```bash
for example in examples/04-callback examples/07-event-queue examples/08-telemetry-hub; do
  (cd "$example" && zig build purego-go purego-go-verify --summary all)
  (cd "$example/go-purego" && CGO_ENABLED=0 go test ./...)
done

(cd examples/10-tagged-union && zig build go go-verify -Dpurego --summary all)
```

두 백엔드를 등록한 예제는 정적 아카이브와 공유 라이브러리가 같은 `zig-out`에 설치되지만
서로를 가리지 않는다. cgo 생성물은 아카이브를 경로로 직접 링크하고 purego 헤더는
별도 이름으로 설치되므로, 두 백엔드를 순서에 상관없이 한 트리에서 검증할 수 있다.
생성된 purego 테스트는 `ZIGO_LIBRARY_PATH`가 있으면 그 경로를 우선 사용한다.

`examples/08-telemetry-hub`의 purego 바인딩은 자동 로딩과 내부 로더 정책을 사용하므로
테스트가 로더를 호출하지 않는다. 라이브러리는 `../../zig-out/lib` search path로 찾으므로
`zig build purego-go-lib` 이후 패키지 디렉터리에서 테스트를 실행해야 한다.

`examples/10-tagged-union`의 purego 테스트는 `ZIGO_TEST_LIBRARY`에 설치된 라이브러리의
절대 경로를 요구하며, `ZIGO_TEST_WRONG_LIBRARY`를 함께 주면 심볼 누락 실패 경로까지
검증한다. 설정하지 않으면 skip한다.

설치된 아티팩트 자체는 저장소 도구로 검사한다.

```bash
tests/inspect_shared_library.sh \
  examples/04-callback/zig-out/lib/libcallback_zigo.dylib zg_last_error_message
zig build shared-library-smoke -- \
  examples/04-callback/zig-out/lib/libcallback_zigo.dylib zg_last_error_message
```

생성된 purego 로더는 플랫폼 파일명을 실행 시점에 고르므로 macOS와 Linux에서 생성물이
동일해야 한다. CI는 두 OS의 amd64·arm64에서 이 동일성과 `CGO_ENABLED=0` 테스트를 함께
검사한다.

## 예제 검증

각 예제가 무엇을 다루는지는 [예제](examples.md)에 정리되어 있다. 저장소를 바꾼 뒤에는
생성물과 ABI가 여전히 일치하는지 예제에서 확인한다.

```bash
cd examples/05-pipeline      # 07-event-queue, 08-telemetry-hub 도 동일하다
zig build test
zig build go
zig build go-check abi-check
cd go && go test -count=1 ./...
```

05-pipeline은 기능 조합의 폭을, 07-event-queue는 애플리케이션 형태의 수명 계약을,
08-telemetry-hub는 51개 함수 규모에서의 reflection·생성 비용을 각각 회귀 검사한다.
09-type-relations와 10-tagged-union은 타입 간 참조와 tagged-union accessor를 담당한다.

## 문서 변경 확인

사용자 문서의 명령과 Zig 예제는 현재 `examples/`와 `build.zig`의 공개 옵션을 기준으로
유지한다. 내부 동작이나 지원 범위를 바꾸면 [사용자 문서](README.md)와
[설계 문서](.agent/design/README.md)를 함께 갱신한다.
