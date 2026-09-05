# IR 명세

zigo는 외부 파일인 semantic IR과 오류 코드 잠금 파일, 생성기 내부의 ABI IR을 구분합니다.
이 문서는 각 표현의 책임을 설명합니다. 필드 전체와 기본값은 연결된 Zig 자료구조가 기준이며,
새 필드를 추가할 때 문서에 축약 스키마를 복제하지 않습니다.

## 표현별 역할

| 표현 | 저장 형태 | 역할 |
|---|---|---|
| semantic IR | `semantic.json` | reflector 출력, generator 입력, ABI 비교 기준 |
| 오류 코드 잠금 | `errors.lock.json` | 오류 이름에 배정한 정수 코드 보존 |
| ABI IR | 메모리의 `abi.Program` | 모든 emitter가 공유하는 하강 결과 |

생성·커밋 정책은 [생성물과 CI 관리](../../generated-code.md)를 참고하세요.
별도의 `layout.json` 파일은 사용하지 않습니다.

## Semantic IR

[semantic.zig](../../../src/gen/ir/semantic.zig)는 문서, 등록 타입, 함수와 타입 노드를
정의합니다. 함수에는 Go 이름과 패키지, receiver, 매개변수·반환 타입, 소유권, release와
콜백·스트림 등의 메타데이터가 포함됩니다. 주석과 파라미터 이름의 출처도 보존합니다.

타입 노드는 다음 범주를 구분합니다.

| 범주 | 노드 |
|---|---|
| 기본값 | `void`, `bool`, `int`, `float`, `enum` |
| 등록 타입 | `opaque_ptr`, `value_struct`, `materialized` |
| 조합 | `optional`, `error_union`, `slice` |
| 호출 지원 | `callback`, `atomic_ptr`, `cancel_flag`, `io_stream` |

정수의 `is_usize`는 포인터 크기 정수임을 표시하고 `signed`가 `usize`와 `isize`를
구분합니다. slice의 const·sentinel 정보는 원래 Zig 타입의 재구성에 사용합니다.
문자열 의미는 단순 byte slice와 별도로 보존합니다.

semantic 파일을 타깃에서 그대로 사용할 수 있는 메모리 레이아웃 명세로 해석해서는
안 됩니다. reflector는 호스트에서 실행되고, 타깃 표현은 하강과 shim의 레이아웃 검사에서
확인합니다.

등록 타입 참조, 생성자·소멸자와 release 함수의 관계는 검증 대상입니다. release 선언은
semantic 단계에서 함수 이름을 가리키며, lowering에서 해당 ABI 함수와 연결합니다.
materialized 결과의 release는 직렬화 버퍼를 해제하므로 일반 slice와 같은 원소 타입을
요구하는 규칙을 그대로 적용하지 않습니다.

실제 출력 예시는 [01-scalar의 메타데이터](../../../examples/01-scalar/) 등
[예제](../../examples.md)의 `zigo/` 디렉터리에서 확인할 수 있습니다.

## 오류 코드 잠금 파일

[errors_lock.zig](../../../src/gen/ir/errors_lock.zig)가 읽기·검증·추가 규칙을 정의합니다.

```json
{
  "ir_version": 1,
  "next_code": 4,
  "codes": { "OutOfMemory": 1, "InvalidInput": 2, "Timeout": 3 },
  "reserved": {
    "0": "OK",
    "-1": "Unknown",
    "-2": "PanicCaught",
    "-3": "CallbackPanic",
    "-4": "InvalidHandle"
  }
}
```

오류 코드는 한 번 배정하면 바꾸거나 재사용하지 않습니다. 삭제된 오류의 코드도 보존하며,
새 오류는 `next_code`부터 추가합니다. 스키마 버전, 예약 코드, 양수 코드의 중복·빈자리를
검증합니다. 콜백 호출 ABI의 별도 상태값을 이 파일의 예약 코드와 혼동하지 마세요.

## ABI IR

[abi.zig](../../../src/gen/ir/abi.zig)의 `Program`이 emitter 입력입니다.
[lower.zig](../../../src/gen/lower.zig)는 함수의 C 매개변수, 반환 표현, 공개 Go 호출에
필요한 정보와 수명 정책을 함께 결정합니다.

반환 소유권은 `none`, `borrowed_view`, `borrowed_copy`, `handle`, `buffer`로
구분합니다. buffer 레코드의 `release`는 심볼 문자열이 아니라 `Program.functions`의
인덱스입니다. handle 레코드는 destructor, boxing, 부모 관계와 retained 슬롯 등을 담습니다.
매개변수는 `transient`, `retained_token`, `staged_copy`, `stream` 정책을 구분합니다.

이 정보는 C 표현만으로 알 수 없는 Go 쪽 복사·해제·호출 보호에도 쓰입니다. emitter에서
semantic 정보를 다시 해석해 다른 소유권 결정을 만들지 않습니다. 구체적인 변환은
[ABI 하강 규칙](03-lowering-rules.md)을 참고하세요.
