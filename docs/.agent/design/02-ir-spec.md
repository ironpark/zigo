# IR 명세 (v1)

IR은 세 가지 역할을 한다: **reflector ↔ generator 프로세스 경계**,
**ABI diff 기준**, **generator 테스트 픽스처**. 스키마는 Go 생성에 필요한 만큼만 유지한다.

두 개의 파일로 나뉜다.

| 파일 | 타깃 의존 | Git 커밋 | 용도 |
|---|---|---|---|
| `semantic.json` | ✗ | ✅ | 의미 API. diff 기준. generator의 입력 |
| `errors.lock.json` | ✗ | ✅ | 에러명 → 안정 정수 코드 (append-only) |

---

## 1. semantic.json

```jsonc
{
  "ir_version": 1,
  "package": "mylib",
  "prefix": "zg",
  "zig_version": "0.16.0",

  "types": [
    {
      "name": "Context",
      "kind": "opaque",              // opaque | value_struct | enum | error_set
      "zig_path": "mylib.Context"
    },
    {
      "name": "Format",
      "kind": "enum",
      "tag_type": { "kind": "int", "signed": false, "bits": 32 },
      "fields": [ {"name":"pcm","value":0}, {"name":"flac","value":1} ]
    },
    {
      "name": "Rect",
      "kind": "value_struct",
      "layout": "extern",            // extern | packed  (그 외는 IR에 도달 불가)
      "fields": [
        {"name":"x","type":{"kind":"float","bits":32}},
        {"name":"y","type":{"kind":"float","bits":32}}
      ]
    },
    {
      "name": "Value",
      "kind": "tagged_union",
      "tag_type": {"kind":"enum","ref":"ValueTag"},
      "fields": [
        {"name":"none","value":0,"type":{"kind":"void"}},
        {"name":"integer","value":1,"type":{"kind":"int","signed":true,"bits":64}}
      ]
    }
  ],

  "functions": [
    {
      "name": "process",
      "symbol": "zg_context_process",
      "receiver": "Context",         // null이면 자유 함수
      "params": [
        {
          "name": "input",
          "name_source": "sidecar",  // sidecar | ast | fallback
          "type": {
            "kind": "slice", "const": true,
            "element": {"kind":"float","bits":32}
          },
          "direction": "in",
          "retention": "borrowed",
          "semantic": null           // null | utf8_string | c_string | opaque_bytes
        },
        {
          "name": "output",
          "type": {"kind":"slice","const":false,"element":{"kind":"float","bits":32}},
          "direction": "out",
          "retention": "borrowed"
        }
      ],
      "return": {
        "kind": "error_union",
        "error_set": ["OutOfMemory", "InvalidInput"],
        "payload": {"kind":"int","signed":false,"bits":64,"is_usize":true}
      },
      "ownership": "caller",
      "doc": "Processes input samples into output."
    }
  ],

  "constructors": [
    { "type": "Context", "init": "init", "deinit": "deinit" }
  ]
}
```

### 1.1 타입 노드 (`type`)

```jsonc
{"kind":"void"}
{"kind":"bool"}
{"kind":"int",   "signed":true, "bits":32, "is_usize":false}
{"kind":"float", "bits":64}
{"kind":"enum",  "ref":"Format"}
{"kind":"opaque_ptr", "ref":"Context", "const":false, "nullable":false}
{"kind":"value_struct", "ref":"Rect"}
{"kind":"slice", "const":true, "element":<type>}
{"kind":"optional", "child":<type>}
{"kind":"error_union", "error_set":[...], "payload":<type>}
{"kind":"callback", "params":[<type>...], "return":<type>, "has_userdata":true}
```

`is_usize`는 별도 플래그로 둔다. 타깃별 비트폭은 layout 파일에 있으므로
semantic.json은 "usize다"라는 사실만 기록한다 → 타깃 독립성 유지.

`semantic`/`return_semantic`의 `c_string`은 reflector가 발견한
`[*:0]const u8`를 표시한다. 타입 노드는 byte slice 모양을 유지하되 이 힌트가 있으면
하강 시 길이 없는 `const char*`로 바뀐다. 따라서 이 힌트가 붙은 slice에는 별도의
`*_len` ABI 인자가 없다.

function의 선택적 `release`는 `.returns = "caller"` slice 반환을 해제하는 함수의 이름을
담는다. 그 이름은 같은 문서의 `functions`에 있어야 하고, 반환 slice와 같은 원소 타입의
slice 하나만 받는 void 함수여야 한다. 하강 단계가 이 이름을 상대 함수의 심볼로 바꾼다.

slice 노드의 선택적 `sentinel`/`sentinel_many`는 문자열 slice 매개변수의 element 원형을
보존한다. `sentinel=0`과 `sentinel_many=false`는 `[:0]const u8`, `true`는
`[*:0]const u8`를 뜻하고, 두 필드가 없으면 `[]const u8`이다. 이 정보는 하강된 C ABI
모양을 바꾸지 않고 shim이 원래 Zig element 타입을 다시 만들 때만 사용한다.

모든 `ref`는 같은 문서의 `types`에서 정확히 한 번 선언되어야 하며 노드 종류와 선언
종류가 일치해야 한다. `enum`은 유효한 정수 `tag_type`을 가져야 한다. constructor의
`type`은 opaque 또는 tagged-union handle 선언이어야 하고, `init`은 해당 namespace에서 caller-owned non-null
handle pointer를 error union으로 반환하며, `deinit`은 인자 없이 `void`를 반환하는
해당 타입의 receiver 함수여야 한다. 이 무결성 조건은 lowering 전에 `ZIGO010`으로
검사한다.

### 1.2 왜 doc 필드가 있는가

`@typeInfo`는 doc comment를 주지 않는다. `name_source: "ast"` 경로에서
파라미터 이름을 뽑을 때 doc comment도 함께 수집한다. 없으면 `null`.
생성된 Go 코드의 주석 품질을 좌우하므로 선택적이지만 가치가 크다.

---

## 2. errors.lock.json

```jsonc
{
  "ir_version": 1,
  "next_code": 4,
  "codes": { "OutOfMemory": 1, "InvalidInput": 2, "Timeout": 3 },
  "reserved": { "0": "OK", "-1": "Unknown", "-2": "PanicCaught",
                "-3": "CallbackPanic", "-4": "InvalidHandle" }
}
```

규칙:
- 코드는 배정 후 **불변**. 삭제된 에러의 코드는 재사용하지 않는다 (`next_code`만 증가).
- 도구가 기존 매핑을 바꾸려 하면 즉시 실패한다.
- 음수는 프레임워크 예약이며 사용자 에러에 배정되지 않는다.
- `ir_version`과 예약 매핑은 정확히 일치해야 하며, 양수 코드는 `1..next_code-1`을
  중복이나 빈자리 없이 보존한다. 새 이름 배정은 overflow와 메모리 확보를 먼저 검사한
  뒤 한 번에 append한다.

---

## 3. ABI IR (내부 표현, 파일로 쓰지 않음)

validate/lower 단계의 결과. emitter가 소비하는 유일한 자료구조.
semantic IR과의 차이는 **모든 타입이 C ABI 표현으로 평탄화되어 있다**는 점이다.

```zig
pub const AbiFn = struct {
    symbol: []const u8,
    params: []const AbiParam,      // 슬라이스 → ptr+len 2개로 이미 분해됨
    ret: AbiScalar,                // 항상 스칼라 (에러코드 i32 또는 void)
    origin: *const SemanticFn,     // 상위 계층 생성용 역참조
};
```

emitter가 하강 규칙을 다시 구현하지 않도록, **분해는 전부 lower 단계에서 끝낸다.**
Go emitter, C 헤더 emitter, Zig shim emitter가 서로 다른 하강을 하면 세 산출물의 ABI가
어긋난다. 이 셋은 반드시 동일한 `AbiFn`을 읽어야 하며, 이는 정확성 요구사항이다.
