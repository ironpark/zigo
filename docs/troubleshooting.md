# 문제 해결

명령은 문제가 발생한 프로젝트 루트에서 실행합니다. 아래는
`bindings.addStandardSteps(b, .{})`의 기본 단계 이름과 `go_dir = b.path("go")`를
사용합니다. 접두사를 지정한 프로젝트는 `go-doctor` 대신 `admin-go-doctor`처럼 해당 이름을
사용하세요. 등록된 단계는 `zig build --help`에서 확인할 수 있습니다.

## 증상으로 찾기

| 증상 | 먼저 확인할 항목 |
|---|---|
| Zig 컴파일 오류 또는 `error[ZIGO...]` | 아래의 생성 실패 |
| `go-check` 또는 `go-verify`가 오래된 파일을 보고 | 아래의 생성물 불일치 |
| C 컴파일러, 헤더, `library not found`, 미해결 심볼 오류 | 아래의 cgo 빌드·링크 실패 |
| 공유 라이브러리를 찾지 못하거나 호출 전 panic | 아래의 실행 시 로드 실패 |
| 생성 이름·반환값·소유권이 예상과 다름 | `zig build go-report`, [생성 Go API](reference/generated-go-api.md) |
| 새 Zig 함수가 Go에 없음 | `zig build go-coverage`, [함수 선택](authoring/functions-and-packages.md) |

## 생성 실패

```bash
zig version
go version
zig build go-doctor
zig build go
```

도구 버전을 [지원 범위](reference/support-matrix.md)와 비교합니다. `go-doctor` 자체가 Zig
컴파일 오류로 끝나면 도구 진단까지 도달하지 못한 것이므로 먼저 해당 컴파일 오류를 고칩니다.

purego로 전환한 뒤 빌드 그래프 생성 시 의존성 오류가 나면, 기존 Go 모듈 디렉터리에서
`go get github.com/ebitengine/purego@v0.10.2`를 먼저 실행합니다. 그다음 `zig build go`로
재생성하고 Go 모듈 디렉터리에서 `go mod tidy`를 실행합니다.

`ZIGO...` 진단은 첫 오류의 선언 위치(`-->`)와 `hint:`부터 읽습니다. 바인딩의 선언 경로,
원래 Zig 함수의 매개변수 인덱스, 타입 등록과 해제 계약을 확인하세요.
코드별 수정 방향은 [진단 참조](reference/diagnostics.md)에 있습니다.
선언을 고친 다음 `zig build go-report`와 `zig build go`로 결과를 확인합니다.

검증·렌더링 실패는 기존 생성물을 유지합니다. 파일 쓰기가 중단된 경우에는 다시 생성하고
전체 diff를 검토하세요. 이전 생성물이 남아 있다는 사실만으로 새 선언이 유효한 것은 아닙니다.

## 생성물 불일치

`go-check`는 현재 선언으로 만들 결과와 커밋된 생성물을 비교합니다.
사용자 코드를 수정하는 작업 환경에서는 다음 순서로 갱신합니다.

```bash
zig build go
(cd go && go test ./...)
git diff
zig build go-check
```

의도한 변경인지 확인한 뒤 생성 Go 소스와 메타데이터를 함께 커밋합니다.
CI에서는 `go`로 차이를 덮어쓰지 말고 실패 원인을 작성자 작업 환경에서 수정합니다.
생성기의 버전, 바인딩 설정과 플러그인 설정도 동일해야 합니다.
정확한 커밋 범위는 [생성물과 CI](build-and-ship/generated-files-and-ci.md)를 참고하세요.

## cgo 빌드·링크 실패

```bash
go env CGO_ENABLED GOOS GOARCH CC
zig build go-lib go-doctor
(cd go && go test ./...)
```

- `CGO_ENABLED`가 `1`인지, C 컴파일러를 실행할 수 있는지 확인합니다.
- `zig-out`에 현재 Go 대상 플랫폼의 라이브러리와 헤더가 설치되어 있는지 확인합니다.
- 생성 raw 패키지의 `#cgo` 경로와 `zigo_link_inputs_gen.go`에 기록된 추가 링크 입력을 확인합니다.
  다른 머신에서 복사한 절대 경로는 재빌드하여 갱신합니다.
- `pkg-config`, 시스템 라이브러리, 프레임워크 또는 추가 정적 아카이브가 필요하면 소비자
  환경에도 준비합니다. 사용자 지정 `cflags`·`ldflags`가 기본 경로를 교체했는지도 확인합니다.

생성 파일을 직접 수정하지 말고 [빌드 설정](build-and-ship/configuration-and-backends.md)을
고친 뒤 다시 생성합니다. Windows cgo는 지원하는 GNU ABI에서 `CC="zig cc"`를 사용할 수
있습니다. Go 모듈을 받는 `go get`은 네이티브 라이브러리를 빌드하지 않습니다.

## 실행 시 로드 실패

cgo 동적 링크는 OS 로더가 공유 라이브러리와 그 의존성을 찾을 수 있어야 합니다.
개발 환경에서는 macOS의 `DYLD_LIBRARY_PATH`, Linux의 `LD_LIBRARY_PATH`, Windows의 DLL
검색 경로를 확인합니다. 제품 배포 경로는 [패키징과 배포](build-and-ship/packaging-and-distribution.md)에
맞춰 설정하세요.

purego의 기본 설정은 명시적 로딩입니다. 첫 API 호출 전에 생성된 공개 패키지의
`LoadLibrary`를 호출하고 반환 오류를 처리합니다.

```go
if err := mylib.LoadLibrary(libraryPath); err != nil {
    return err
}
```

`libraryPath`에는 현재 OS·아키텍처에 맞는 공유 라이브러리의 파일 경로를 전달합니다.
경로가 맞는데 심볼을 찾지 못하면 Go 코드와 네이티브 라이브러리가 같은 선언·버전에서
생성되었는지 확인하고 함께 재빌드합니다. 공유 라이브러리의 추가 의존성도 필요합니다.
`CGO_ENABLED=0`은 네이티브 라이브러리 배포를 생략한다는 뜻이 아닙니다.
다른 플랫폼용 빌드에서 doctor의 로드 검사가 `SKIP`되면 해당 플랫폼에서 실행 검증합니다.

[문서 홈](README.md) · [지원 범위](reference/support-matrix.md)
