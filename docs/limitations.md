# 제한사항과 운영 주의사항

## 지원 환경

- 현재 지원 범위는 Zig 0.16.0, Go 1.23 이상, cgo가 활성화된 네이티브 macOS/Linux다.
  선택적인 `auto_cleanup`은 Go 1.24 이상이 필요하다.
- opt-in `.backend = .purego`는 Go 빌드에서 C 컴파일러와 cgo를 제거하지만, 지원 범위는
  네이티브 macOS/Linux의 amd64·arm64로 더 좁고 `.link_mode = .dynamic`을 요구한다.
  Windows, 모바일, purego Tier 2 타깃은 후속 작업이다. 정적 링크는 cgo 전용이다.
- purego는 v1 이전 베타 소프트웨어다. zigo는 `github.com/ebitengine/purego v0.10.2`를
  고정해 생성·검증하며 사용을 생성된 raw 파일에만 격리한다. 다른 버전을 요구하는
  `go.mod`는 `go-doctor`가 경고로 보고한다.
- 공유 라이브러리는 타깃별 아티팩트다. purego는 Go 애플리케이션 빌드에서 C 컴파일러를
  없앨 뿐 하나의 Zig 아티팩트를 여러 타깃에 이식해 주지 않으므로, 배포하는 OS·아키텍처
  조합마다 해당 호스트에서 빌드하고 CI 잡도 조합마다 필요하다.
- Go race detector는 여전히 cgo를 요구하므로 `CGO_ENABLED=0` 테스트에는 사용할 수 없다.
- reflector 실행이 빌드에 포함되므로 v1은 크로스 컴파일을 지원하지 않는다.
- zigo는 Go 바인딩만 생성한다. IR은 다른 언어용 범용 IDL을 목표로 하지 않는다.

## Zig 타입과 ABI

- 일반 Zig `struct`의 메모리 배치는 안정된 C ABI가 아니다. 값으로 노출하려면
  `extern struct`를 사용하고, 일반 struct는 opaque 포인터로 노출한다.
- tagged union은 `.repr = .tagged_union`으로 등록한 뒤 포인터로만 노출한다. 생성된
  `Tag`/`As*`가 active tag를 검사하며 union 레이아웃은 C로 전달하지 않는다. nested
  aggregate, optional, error union, callback 또는 pointer 원소 slice payload는 지원하지 않는다.
- generic 함수는 구체화 전에는 시그니처가 없으므로 직접 노출할 수 없다. generic 타입은
  `specializations`에 구체화된 타입을 등록한다.
- `anyerror`, C 호출 규약이 아닌 함수 포인터, Go 포인터를 포함할 수 있는 슬라이스처럼
  안전한 계약을 만들 수 없는 선언은 생성 단계에서 거부한다.
- 지원 타입과 정확한 하강 규칙은 [ABI 하강 규칙](.agent/design/03-lowering-rules.md)을 참고한다.

## 이름과 메타데이터

Zig reflection에는 함수 파라미터 이름이 없다. zigo는 `bindings.zig`의 `params`, Zig AST
스캔, `p0`, `p1` 형식의 fallback 순으로 이름을 결정한다. `source_root`를 지정하면 실제
대상 모듈 루트에서 owner-qualified 선언을 찾는다. AST 정보는 타입 판단에 사용하지 않는다.
공개 Go 파라미터 이름을 Zig 소스와 독립적으로 고정하려면 `params`를 명시한다.

AST 보강에 사용하는 기본 `bindings.zig`를 읽지 못하면 reflection이 실패한다. 선택적인
같은 디렉터리의 `root.zig`가 없는 경우만 정상적으로 건너뛰며, 발견된 `.zig` import를
읽지 못하거나 AST를 파싱하지 못하면 오류 경로와 원인을 출력하고 생성을 중단한다.

문자열, 반환 포인터 소유권, retained 포인터와 콜백 수명은 타입만으로 결정할 수 없다.
`semantic`, `returns`, `param_meta.retention`을 통해 계약을 명시해야 한다.

`.discover = .public`은 공개 Zig API와 바인딩 API가 같은 프로젝트를 위한 opt-in 정책이다.
공개 helper나 지원하지 않는 generic 함수까지 발견될 수 있으므로 `exclude`로 의도를
명시한다. 일부 함수만 안정적으로 노출해야 하는 라이브러리는 명시적인 `functions` 목록을
유지한다.

## 런타임 주의사항

- Zig panic은 C 경계에서 오류 코드 `-2`와 마지막 오류 메시지로 변환되지만 정상 복구를
  뜻하지 않는다. 메시지를 수집한 뒤 현재 작업을 중단한다.
- 모든 public opaque receiver와 handle 인자는 cgo 진입 전에 nil·closed 상태를 검사한다.
  오류 반환이 없는 일반 메서드는 `*HandleError`로 panic한다. Tagged-union의 `TryTag`와
  `TryAs*`는 같은 상태를 error로 반환하며, 편의 메서드 `Tag`와 `As*`만 typed error로
  panic한다.
- tagged-union projection은 별도 status `3`으로 실제 Zig panic을 구분해
  `*NativePanicError`로 반환한다. null handle과 필수 out 파라미터는 status `2`로
  거부하지만, `SIGSEGV` 같은 하드웨어 fault나 손상된 native 메모리까지 복구하지는 않는다.
- cgo 호출 비용은 무시할 수 없다. 호출당 작업이 작은 API를 그대로 노출하기보다 배치
  지향 함수를 제공하는 편이 낫다.
- retained Go 콜백과 포인터는 생성된 `Close` 경로에서 해제될 때까지 유효해야 한다.
  소유 객체는 사용 후 반드시 닫고, 콜백에서 발생한 panic의 전달 규칙도 테스트한다.
- 동일 handle의 `Close`, tagged-union variant 변경, projection 호출을 여러 goroutine에서
  동시에 실행하지 않는다. 생성된 `runtime.KeepAlive`는 명시적 lifecycle 작업의 동기화
  장치가 아니다.
- `auto_cleanup`은 실행 시점과 프로그램 종료 전 실행을 보장하지 않는다. callback이 소유
  객체를 캡처하는 강한 참조 순환과 특정 thread에서만 가능한 해제를 해결하지 않으므로
  명시적 `Close`의 대체로 사용하지 않는다.
- `errors.lock.json`의 정수 코드는 append-only 계약이다. 삭제된 에러의 코드를 다른
  에러에 재사용하지 않는다.
- purego 백엔드는 기본적으로 바인딩 호출 전에 `LoadLibrary`가 성공해야 한다.
  `library_loading.automatic`을 켜면 첫 호출에서 한 번 자동으로 시도하지만, 모든 후보가
  실패하면 panic한다. 공개 API가 오류를 반환하지 않는 형태이므로 다른 선택지가 없다. 로드는 원자적이라
  실패해도 부분적으로 호출 가능한 패키지를 남기지 않지만, 성공한 라이브러리는 프로세스
  수명 동안 언로드하지 않는다. `LoadLibrary`는 임의의 네이티브 코드를 로드하므로
  애플리케이션이 통제하는 경로만 넘긴다.
- purego 콜백은 고유 시그니처마다 영구 dispatcher를 만든다. 콜백 panic은 부호 있는
  32비트 콜백 결과에서 `-3`, 이미 해제된 토큰 호출은 `-4`로 변환된다. 세부 사항은
  [공유 라이브러리와 purego 백엔드](purego.md)에 있다.

## 생성물 관리

생성된 Go 파일과 ABI 메타데이터는 커밋하고 CI에서 `go-check`를 실행한다. 독립 배포
버전과의 호환성을 보증하는 프로젝트는 `abi_base`를 설정하고 `abi-check`도 실행한다.
raw 패키지 모드나 경로를 변경하면 zigo는 이전 위치의 파일을 자동 삭제하지 않는다.
`go-check`가 zigo marker를 가진 오래된 파일을 obsolete로 보고하므로 새 바인딩 생성 후 해당
`_gen.go` 파일을 직접 제거해야 한다.

생성기는 모든 산출물을 메모리에서 준비한 뒤 쓰므로 검증·렌더링·메모리 실패에는 기존
트리가 유지된다. 다만 최종 파일 쓰기 중 전원 차단이나 파일시스템 장애가 발생했을 때
여러 파일을 하나의 filesystem transaction으로 복구하는 것까지는 보장하지 않는다.

제약의 설계 근거와 전체 리스크 목록은 [제약과 리스크](.agent/design/00-constraints.md)에 있다.
