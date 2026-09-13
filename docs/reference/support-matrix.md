# 지원 범위

이 문서는 zigo가 지원하는 도구 모음, 플랫폼, ABI와 수명 제약의 정본입니다.

## 도구와 플랫폼

| 항목 | 지원 범위 |
|---|---|
| Zig | 0.16.0 |
| Go | 1.24 이상 |
| cgo 검증 플랫폼 | macOS·Linux amd64/arm64, Windows amd64 GNU ABI |
| purego | macOS·Linux·Windows amd64/arm64 |
| Windows cgo 컴파일러 | `CC="zig cc"` |
| purego 모듈 | `github.com/ebitengine/purego v0.10.2` |
| 미지원 | MSVC ABI, 32 bit 대상, mobile |

현재 저장소의 [CI 설정](../../.github/workflows/ci.yml)은 Zig 0.16.0과 Go 1.26.x를 사용합니다.
Go 1.24는 생성 코드의 최소 요구 버전이며, CI가 모든 Go 버전을 실행 검증한다는 뜻은 아닙니다.

Go race detector는 cgo가 필요하므로 `CGO_ENABLED=0` purego 테스트에서는 사용할 수 없습니다.

## 크로스 컴파일

- reflection은 빌드 호스트에서 실행하고 네이티브 라이브러리는 대상용으로 빌드합니다.
- `c_long`처럼 호스트와 대상에서 폭이 달라지는 타입 대신 고정 폭 타입을 사용합니다.
- 대상별 조건부 공개 선언은 대상 호스트에서도 생성·검증합니다.
- 미리 빌드한 archive는 `targets` mode에서 다른 대상용으로 재빌드할 수 없습니다.
- 다른 플랫폼의 대상에 대한 doctor 로드 검사는 실패가 아니라 `SKIP`일 수 있습니다.
- 최종 산출물은 반드시 대상 환경에서 실행합니다.

## 값과 ABI

- 정수는 64 bit 이하, float는 `f32`와 `f64`를 지원합니다.
- `anyerror` 대신 명시적 오류 집합을 사용합니다.
- 제네릭 함수는 구체적인 타입으로 특수화한 래퍼를 공개합니다.
- value 구조체는 적격 `extern struct` 또는 integer-backed `packed struct`입니다.
- functional options의 대상 필드는 `.flatten`과 같은 집합(bool, 정수, float, 등록 enum,
  optional 스칼라)이고 모두 Zig 기본값을 가져야 합니다.
- 중첩된 포인터·슬라이스 결과 tree는 materialized 또는 핸들로 표현합니다.
- 일반 슬라이스 원소에 Go 포인터가 포함될 수 없습니다.
- tagged union의 value, 스냅샷과 projection은 서로 다른 페이로드 제한을 가집니다.
- 값 tagged union은 매개변수, 결과, 그리고 결과를 감싼 error union 자리에 올 수 있습니다.
  optional 안이나 slice 원소 자리는 아직 지원하지 않습니다.

전체 형태는 [타입 대응](type-mapping.md)을 확인하세요.

## 메모리와 수명

- Go 문자열과 슬라이스 입력은 호출 동안만 빌립니다.
- 네이티브가 입력 포인터를 보관해야 하면 Zig 메모리로 복사합니다.
- native-owned slice/string 결과는 Go로 복사한 뒤 등록한 해제 함수으로 해제합니다.
- owned 핸들은 사용 후 명시적으로 `Close`합니다.
- borrowed 핸들과 union projection은 owner보다 오래 사용할 수 없습니다.
- dependent child를 닫기 전에 parent를 닫지 않습니다.
- 자동 정리는 실행 시점이나 프로세스 종료 전 실행을 보장하지 않습니다.

## 동시성

생성 핸들 런타임은 메서드 호출과 `Close` 사이의 포인터 수명을 보호합니다. Zig 객체의
여러 메서드를 자동으로 serialize하지는 않습니다. 원래 라이브러리가 동시 호출에 안전하지 않다면 Go
호출자가 별도 잠금을 사용합니다.

retained 콜백의 스레드와 재진입 옵션은 계약 정보입니다. arbitrary 네이티브 스레드에서
호출되는 콜백이 접근하는 Go 상태는 애플리케이션이 동기화합니다.

## panic과 복구

- error를 반환할 수 있는 호출 경계의 Zig panic은 `*NativePanicError`가 될 수 있습니다.
- error 결과가 없는 호출 경계의 panic은 프로세스를 종료할 수 있습니다.
- Go 콜백 panic은 호출 경계 밖에서 `*CallbackPanicError`로 다시 panic합니다.
- Zig panic에 참여한 핸들은 poison되어 다시 사용할 수 없을 수 있습니다.
- poison 핸들의 소멸자는 실행하지 않아 네이티브 할당이 남을 수 있습니다.
- 메모리 corruption과 hardware fault는 복구 대상으로 보지 않습니다.

## 콜백과 스트림

- 콜백은 C 호출 규약 함수 포인터여야 합니다.
- purego 콜백 결과는 `void`, `bool` 또는 `i32`입니다.
- 스트림과 cancel 포인터는 호출 뒤까지 보관할 수 없습니다.
- 스트림은 optional, retained 필드 또는 콜백 페이로드로 지원하지 않습니다.
- cancellation은 Zig 코드가 flag를 읽는 cooperative 방식입니다.

## ABI 호환성

다음 변경은 독립 배포된 네이티브 라이브러리 사용자와 호환성을 깨뜨릴 수 있습니다.

- C 심볼, 접두사 또는 패키지 소유자 변경
- extern/packed 구조체 배치 변경
- 열거형과 tagged-union value 배치 변경
- optional, 스칼라 width 또는 signedness 변경
- 결과 소유권과 해제 함수 변경
- 콜백 시그니처, userdata 또는 retention 변경
- error 태그 code 재배치

`zigo.param.options`의 functional options는 Go 표면에만 나타나고 C 심볼과 shim 시그니처는
`.flatten`과 같으므로, 이 목록의 ABI 변경에 해당하지 않습니다.

호환성을 유지해야 하면 `abi_base`와 `zig build abi-check`를 사용하세요. 내부 C 표현은
[ABI 문서](../internals/abi.md)에서 설명합니다.
