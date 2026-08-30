# 제한사항과 운영 주의사항

## 지원 환경

- 현재 지원 범위는 Zig 0.16.0, Go 1.23 이상, cgo가 활성화된 네이티브 macOS/Linux다.
- reflector 실행이 빌드에 포함되므로 v1은 크로스 컴파일을 지원하지 않는다.
- zigo는 Go 바인딩만 생성한다. IR은 다른 언어용 범용 IDL을 목표로 하지 않는다.

## Zig 타입과 ABI

- 일반 Zig `struct`의 메모리 배치는 안정된 C ABI가 아니다. 값으로 노출하려면
  `extern struct`를 사용하고, 일반 struct는 opaque 포인터로 노출한다.
- generic 함수는 구체화 전에는 시그니처가 없으므로 직접 노출할 수 없다. generic 타입은
  `specializations`에 구체화된 타입을 등록한다.
- `anyerror`, C 호출 규약이 아닌 함수 포인터, Go 포인터를 포함할 수 있는 슬라이스처럼
  안전한 계약을 만들 수 없는 선언은 생성 단계에서 거부한다.
- 지원 타입과 정확한 하강 규칙은 [ABI 하강 규칙](../design/03-lowering-rules.md)을 참고한다.

## 이름과 메타데이터

Zig reflection에는 함수 파라미터 이름이 없다. zigo는 `bindings.zig`의 `params`, Zig AST
스캔, `p0`, `p1` 형식의 fallback 순으로 이름을 결정한다. 공개 API의 안정성을 위해
`params`를 명시하는 편이 좋다.

문자열, 반환 포인터 소유권, retained 포인터와 콜백 수명은 타입만으로 결정할 수 없다.
`semantic`, `returns`, `param_meta.retention`을 통해 계약을 명시해야 한다.

## 런타임 주의사항

- Zig panic은 C 경계에서 오류 코드 `-2`와 마지막 오류 메시지로 변환되지만 정상 복구를
  뜻하지 않는다. 메시지를 수집한 뒤 현재 작업을 중단한다.
- cgo 호출 비용은 무시할 수 없다. 호출당 작업이 작은 API를 그대로 노출하기보다 배치
  지향 함수를 제공하는 편이 낫다.
- retained Go 콜백과 포인터는 생성된 `Close` 경로에서 해제될 때까지 유효해야 한다.
  소유 객체는 사용 후 반드시 닫고, 콜백에서 발생한 panic의 전달 규칙도 테스트한다.
- `errors.lock.json`의 정수 코드는 append-only 계약이다. 삭제된 에러의 코드를 다른
  에러에 재사용하지 않는다.

## 생성물 관리

생성된 Go 파일과 ABI 메타데이터는 커밋하고 CI에서 `go-check`와 `abi-check`를 실행한다.
raw 패키지 모드나 경로를 변경하면 zigo는 이전 위치의 파일을 자동 삭제하지 않는다.
새 바인딩 생성 후 오래된 `_gen.go` 파일을 한 번 직접 제거해야 한다.

제약의 설계 근거와 전체 리스크 목록은 [제약과 리스크](../design/00-constraints.md)에 있다.
