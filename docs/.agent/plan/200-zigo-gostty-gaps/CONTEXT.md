# SCOPE

declare/author/normalize DSL, reflect walk·names, semantic IR, lowering, validation,
shim·public Go 에미터, plugin contract, docs, generator case 골든.

# CONTEXT

## Current implementation and bottlenecks

- `renderShim`(src/gen/emit/shim.zig:15)이 `panic`만 선언한다. shim.zig가 컴파일 root이므로
  타겟의 `std_options`는 읽히지 않는다.
- `SessionChild`(src/gen/ir/semantic.zig:1382)의 `base()`에 `s`를 붙이는 자리가
  src/gen/plugins/session.zig:201과 src/plugin/session.zig:208 둘이다.
- `semantic.TypeField`(src/gen/ir/semantic.zig:1112)에 `doc`이 없다. `names.zig`의
  `scanMembers`(src/reflect/names.zig:601)는 함수만 enrich하고 컨테이너 필드는 지나친다.
  에미터는 public_types.zig:149와 :896에서 플레이스홀더 문장을 찍는다.
- `semantic.Written`(src/gen/ir/semantic.zig:455)은 `all`과 `@"return"` 둘뿐이고,
  validate/functions.zig가 `.@"return"`에 `usize` 결과를 요구한다(ZIGO017).
- `Plugin`(src/plugin.zig:571)의 `method_hook`은 생성된 메서드 뒤에 덧붙이기만 한다.
- `reflectBinding`(src/reflect/walk.zig:172)이 한 타입에 `.constructs`가 둘이면 거절한다.
- `containsTaggedUnionValue`(validate/functions.zig:172, :271)가 slice 원소와 중첩 자리의
  union 값을 ZIGO006으로 막는다.

## Target structure and invariants

멤버 문서는 함수 문서와 같은 경로로 흐른다: 리플렉션이 자리를 비워 두고 `names.zig`가
소스에서 채우며, 바인딩이 쓴 `.doc`은 소스보다 우선한다. 이름 복수화는 `base()` 옆의
`plural()` 하나로 모인다. `.returned_slice`는 shim에서만 길이를 읽으므로 C ABI는
`.all`과 같다. 플러그인 대체는 checked 메서드를 비공개 이름으로 내려보낼 뿐이므로
C 심볼과 shim은 움직이지 않는다. 생성자 여러 개는 `constructors` 목록의 중복 `type`으로
표현되고, 짝지어진 destructor는 그대로 하나다.
