# 제네릭 타입 문맥을 이용한 바인딩 작성 연구

기준 커밋: 755501c0. Zig 0.16.0에서 검증했습니다.
이 디렉터리의 코드는 **연구용 시제품**입니다. 공개 API와 실제 예제 파일은 변경하지 않았습니다.

## 결론

기존 타입 선언에 `.context()`를 추가해, **타입 이름·표현 옵션·원본 scope·참조를 담은 제네릭 타입**을 만드는 방식을 권장합니다.

`Entry → Context 타입 → Entry → 기존 normalizer`로 구성합니다.
새 schema나 두 번째 normalizer가 필요하지 않습니다. 기존 타입 helper의 반환값을 전부 바꾸는 것보다 적용 범위가 작습니다.

제네릭 함수가 반환하는 struct 내부의 `const Self = @This();`는 그 구체적인 Context를 가리킵니다.
`Self.select()` 같은 조합 메서드가 자신의 함수 선택과 선언 생성을 재사용할 수 있습니다.
이는 Zig 공식 문서의 제네릭 List 예제와 같은 방식입니다:
[Zig 0.16.0 @This 문서](https://ziglang.org/documentation/0.16.0/#This).

반면 사용자 작성 factory struct 안의 `@This()`는 그 factory입니다.
Context의 메서드에서 factory를 호출한다고 lexical 문맥이 바뀌지는 않습니다.
두 경우를 테스트로 구분했습니다.

## 권장 작성 형태

아래의 `.context()`는 **제안 API**이며 아직 구현된 공개 API가 아닙니다.
실행 가능한 시제품에서는 `ctx.context(entry)`로 씁니다.

현재:

```zig
const document = api.in("Document");

const declaration = api.handle("Document", .{}).members(&.{
    document.function("create", .{}),
    document.function("readInto", .{
        .params = &.{zigo.param.output(1, .result)},
    }),
    document.function("deinit", .{}),
});
```

제안:

```zig
const Document = api.handle("Document", .{}).context();

const declaration = Document.define(&.{
    Document.function("create", .{}),
    Document.function("readInto", .{
        .params = &.{zigo.param.output(1, .result)},
    }),
    Document.function("deinit", .{}),
});
```

`Document`는 타입이므로 대문자 이름을 사용하면 기존 소문자 Entry 값과 구분됩니다.
대상 이름을 한 번만 적고, 별도 scope 변수가 없어집니다.
각 함수에서 `Document.function`을 적는 부분까지 없어지는 것은 아닙니다.

## Context가 보관하고 제공하는 것

| 항목 | 의미 |
|---|---|
| `Self = @This()` | 제네릭이 만든 바인딩 Context 타입 |
| `Target` | 실제 library.Document 같은 Zig 타입 |
| 원본 TypeRef | root, 원본 경로, 실제 타입을 보존 |
| 원본 Entry | 표현별 옵션, Go 이름, 문서, plugin, 기존 members를 보존 |
| `source` | 기존 Scope. 중첩 namespace를 탐색할 때 사용 |
| `function(name, options)` | 기존 Scope.function과 같은 함수 Entry |
| `functions(selector)` | 기존 명시적 선택 API |
| `ref(name)` | 원본 함수 참조 |
| `typeRef()` | 이름을 다시 적지 않는 현재 대상 타입 참조 |
| `define(entries)` | 기존 members를 전체 교체한 타입 Entry 반환 |
| `select(selector)` | `Self.define(Self.functions(selector))` |

Context는 runtime 필드를 갖지 않습니다. 시제품에서는 크기가 0임을 확인했습니다.
이는 runtime 할당이 필요 없다는 의미이며, 컴파일 비용이 없다는 의미는 아닙니다.
서로 다른 타입·옵션 조합마다 제네릭 타입이 생길 수 있으므로 컴파일 비용은 별도 측정 대상입니다.

시제품의 `contextType()`는 `@This()`의 정체성을 검사하기 위한 메서드이며 공개 API 제안에 포함하지 않습니다.

## 실제로 유지해야 하는 네 가지 정체성

1. 원본 root와 source container
2. 바인딩할 실제 Zig 타입
3. 함수의 receiver 및 생성되는 타입
4. 공개 Go 이름

이들을 `@This()` 하나로 합치면 안 됩니다. Context는 이 정보를 보관하는 타입입니다.

예를 들어:

```zig
const Queue = api.handle("EventQueue", .{}).named("Queue").context();
const Stream = api.handle("Stream", .{}).context();

const queue = Queue.define(&.{
    Queue.function("newStream", .{
        .role = .{ .constructor = .{
            .type = Stream.typeRef(),
            .receiver = .member,
            .parent = .receiver,
        } },
    }),
});

const stream = Stream.define(&.{
    api.function("freeStream", .{
        .role = .{ .destructor = Stream.typeRef() },
    }),
});
```

- newStream의 source는 EventQueue, receiver도 EventQueue, 생성 대상은 Stream입니다.
- freeStream은 root에 있지만 Stream의 멤버로 배치할 수 있습니다.
- Go 이름을 Queue로 바꿔도 원본 참조는 root.EventQueue입니다.
- 정적 생성자의 `.receiver = .none`은 계속 명시적으로 유지합니다.
- 다른 타입의 receiver를 가진 함수를 잘못 묶으면 기존 normalizer가 거부합니다.

`Context.function()` 자체에 receiver를 강제로 심지 않는 것이 중요합니다.
정적 source 함수가 handle을 첫 인자로 받지 않는 경우도 있고, `.free`도 지원해야 합니다.
실제 멤버 문맥은 `.define()`이 만든 Entry.members에서 결정하게 합니다.

## 제네릭 인스턴스와 공통 선택

```zig
const FloatBuffer = api.handle("FloatBuffer", .{}).context();
const IntBuffer = api.handle("IntBuffer", .{}).context();
const exports: zigo.Selector = .{
    .names = &.{ "create", "push", "len", "deinit" },
};

const declarations = &[_]zigo.Entry{
    FloatBuffer.select(exports),
    IntBuffer.select(exports),
};
```

이 경우 Context도 제네릭 타입이고, Target도 Buffer(f32)/Buffer(i32)가 만든 타입입니다.
둘은 다른 타입입니다. 원본 공개 alias와 source 경로를 보존하므로 `@typeName(Target)`에서
이름을 역추정할 필요가 없습니다. 중첩 namespace의 alias도 검증했습니다.

같은 Zig 타입을 서로 다른 alias로 두 번 등록하는 기존 오류도 유지됩니다.
Context의 타입 정체성이 서로 다르다고 중복 등록을 허용하면 안 됩니다.

## 플러그인과 타입별 옵션

```zig
const Document = api.handle("Document", .{})
    .use(satisfies.plugin, .{ .interfaces = &.{"io.ReadWriteCloser"} })
    .context();

const entry = Document.define(&.{
    Document.function("readInto", .{
        .params = &.{zigo.param.output(1, .result)},
    }).use(zigo.features.implements, .{ .kind = .reader }),
});
```

handle/value/enum/union/materialized 등록의 기존 옵션 타입을 그대로 사용합니다.
플러그인은 context 생성 전의 Entry 또는 define 후의 Entry에 붙일 수 있으므로
Context에 named/use/replacePlugin 같은 메서드를 모두 복제할 필요가 없습니다.

`.define()`은 매번 캡처한 Entry를 기반으로 멤버 목록만 전체 교체합니다.
이름 변경·명시 null·plugin 교체 규칙은 현재 Entry API와 같습니다.

콜백 타입은 원본이 함수 포인터이며 자체 메서드 namespace가 없으므로 초기 Context 대상에서
제외하는 것을 권장합니다. 콜백 등록과 계약 자체는 기존 api.callback으로 충분합니다.
enum/value/materialized Context가 존재한다고 지원하지 않던 receiver 방식이 새로 생기지는 않습니다.

## 비교한 설계

| 설계 | 이점 | 비용과 판단 |
|---|---|---|
| 기존 Entry에 `.context()` 추가 | 표현별 검증·plugin·Entry schema 재사용, opt-in 적용 | Context를 만드는 호출 한 번 추가. 권장 |
| api.handle 등이 곧바로 Context 타입 반환 | `.context()` 생략 | 기존 declarations가 Entry와 type의 혼합이 됨. 모든 소비자에 변환 규칙 필요 |
| 사용자 struct의 pub 선언 자동 수집 | 선언 항목에 지역 이름을 줄 수 있음 | helper 포함 여부, 순서, 자기 참조와 수집 규칙을 새로 정의해야 함. 이번 단계에서는 제외 |
| factory에 Context 타입을 인자로 전달 | 재사용 가능한 계약 묶음 작성 | 작은 예제에서는 factory 문법이 더 길어짐. 선택적 후속 기능 |

factory 방식도 실제로 컴파일했습니다:

```zig
const Factory = struct {
    pub fn members(comptime C: type) []const zigo.Entry {
        return &.{
            C.function("create", .{}),
            C.function("deinit", .{}),
        };
    }
};

// 시제품에서만 제공하는 비교용 build 메서드
const entry = FloatBuffer.build(Factory.members);
```

여기서는 타입 매개변수 C를 사용합니다. factory 내부의 @This가 FloatBuffer가 된다고 기대하지 않습니다.
권장 최소 API에는 build를 넣지 않고, 일반 제네릭 함수와 define/select만으로 시작할 수 있습니다.

## 실제 예제 비교 결과

원본 예제 파일을 고치지 않고 임시 복사본에서 Context 방식으로 바꿨습니다.
양쪽을 기존 zigo.define에 전달한 뒤 **전체 정규화 결과를 comptime deep equality로 비교**했습니다.

| 예제 | Context 개수 | api.in/api.handle 호출 합계 |
|---|---:|---:|
| 04-callback | 3 | 6 → 3 |
| 07-event-queue | 7 | 13 → 7 |
| 11-io-streams | 3 | 6 → 3 |
| 12-materialized | 2 | 4 → 2 |

네 예제 모두 정규화 결과가 완전히 같습니다. 순서나 이름 출처를 무시하는 비교가 아닙니다.
실제 satisfies plugin 설정, allocator 인덱스, callback 계약, child constructor,
하위 package, release와 borrowed 계약이 비교에 포함됩니다.

확인한 테스트:

- 7개 양성 테스트: Context/Target 정체성, generic alias, root 함수, child/static 생성자,
  표현별 선언, plugin과 교체 규칙, factory lexical 문맥, 실제 예제 비교.
- 7개 컴파일 실패 검사: 함수 Entry, callback Entry, 없는 멤버, 다른 receiver, 다른 root,
  Context 타입을 Entry 목록에 직접 넣는 경우, 동일 실제 타입의 alias 중복 등록.

전체 runtime suite나 새 생성물 검증은 실행하지 않았습니다.
이번 연구는 기존 normalizer 입력/출력이 동일함을 확인한 것이며, 공개 API 구현과 성능 검증은 별도 작업입니다.

## 구현으로 옮길 때의 범위

1. author.zig의 Entry.context()에서 기존 Scope(root, type, path)와 원본 Entry를 캡처합니다.
2. Context에는 function/functions/ref/typeRef/define/select와 명시적 source 접근만 제공합니다.
3. 기존 Entry helper, normalizer, plugin 옵션 타입을 유지합니다.
4. 대표 예제를 Context 방식으로 옮기고 정규화·Go 생성물·ABI·cgo/purego 회귀 검사를 합니다.
5. .define 호출에서 멤버 목록 전체 교체, 이름 변경 후 source identity, generic alias,
   여러 package, 기존 역할 충돌에 대한 진단을 회귀 테스트로 고정합니다.
6. 도입 전후 컴파일 시간과 메모리를 비교합니다. 반복 Context 생성이 비용을 키우면
   지역 const로 재사용하도록 예제를 작성합니다.

시제품의 sourceScope는 공개 scope().in()으로 원본 경로를 따라가는 검증용 연결 코드입니다.
본 구현은 author.zig 내부의 기존 Scope를 직접 재사용하면 되므로 이 경로 파서를 추가할 필요가 없습니다.

이 방향으로도 userdata/cancel을 이름으로 연결하는 문제는 해결되지 않습니다.
그 문제는 내부 파라미터 identity를 이름 결정 단계까지 보존하는 별도 개선입니다.

## 재현

저장소 루트에서:

```sh
python3 docs/.agent/research/generic-binding-context/verify.py
```

Python 표준 라이브러리와 PATH의 Zig만 사용합니다. 임시 디렉터리에 변환 예제를 만들고 지웁니다.
[context.zig](context.zig)는 실제 시제품, [tests.zig](tests.zig)는 검증 fixture,
[verify.py](verify.py)는 실제 예제 변환 및 컴파일 실패 검사를 포함한 실행기입니다.
