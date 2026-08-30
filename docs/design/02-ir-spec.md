# IR 명세 (v1)

IR은 세 가지 역할을 한다: **reflector ↔ generator 프로세스 경계**,
**ABI diff 기준**, **generator 테스트 픽스처**. 스키마는 Go 생성에 필요한 만큼만 유지한다.

두 개의 파일로 나뉜다.

| 파일 | 타깃 의존 | Git 커밋 | 용도 |
|---|---|---|---|
| `semantic.json` | ✗ | ✅ | 의미 API. diff 기준. generator의 입력 |
| `layout.<target>.json` | ✅ | ✗ | 크기/정렬/오프셋. **검증 전용**, 네이티브 빌드에서만 생성 |
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

### 1.2 왜 doc 필드가 있는가

`@typeInfo`는 doc comment를 주지 않는다. `name_source: "ast"` 경로에서
파라미터 이름을 뽑을 때 doc comment도 함께 수집한다. 없으면 `null`.
생성된 Go 코드의 주석 품질을 좌우하므로 선택적이지만 가치가 크다.

---

## 2. layout.\<target\>.json

```jsonc
{
  "ir_version": 1,
  "target": "aarch64-macos",
  "pointer_bits": 64,
  "usize_bits": 64,
  "structs": {
    "Rect": { "size": 8, "align": 4,
              "fields": {"x": 0, "y": 4} }
  }
}
```

용도는 **검증 전용**이다. 생성된 C 헤더를 컴파일해 얻은 레이아웃과 이 파일이
불일치하면 빌드를 실패시킨다. Go 코드 생성에는 사용하지 않는다 (cgo가 헤더로 해결).

**크로스 컴파일 시에는 생성되지 않는다.** reflector는 실행되어야 하므로 타깃용
레이아웃을 뽑을 수 없다. 값 전달을 `extern struct`로 제한했기 때문에 이 파일 없이도
정확성이 유지된다 — 상세는 [`00-constraints.md` §7](00-constraints.md).

---

## 3. errors.lock.json

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

## 4. ABI IR (내부 표현, 파일로 쓰지 않음)

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
