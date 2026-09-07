# GOALS

## Problem and the end result from the user's point of view

gostty 바인딩을 쓰면서 zigo에 없어 우회한 다섯 가지: 필드 접근자에 플러그인을 못 붙임,
필드 leaf가 optional·slice를 거부함, alias 재노출 시 문서와 파라미터 이름이 사라짐,
namespace 자유 함수의 C 심볼에 컨테이너 이름이 중복됨, AST 이름 보강이 무관한 익명 컨테이너의
파라미터 이름을 가져옴. 끝나면 gostty에서 손으로 쓴 래퍼 Zig 함수와 `.go_name`·`.params` 우회를 걷어낼 수 있다.

## Measurable goals

- `HandleField.extend(P, opts)`가 getter/setter `SemanticFn.ext`로 전달되어 method_hook에서 읽힌다.
- `?T`(scalar leaf)와 `[]const T` 필드가 getter로 생성되고 shim이 기존 optional/slice 반환 규약을 쓴다.
- `pub const alias = Container.fn;` 재노출에서 대상 선언의 doc과 파라미터 이름이 채워진다.
- `.symbol` 오버라이드가 C 심볼을 대체하고 충돌은 기존 ZIGO036으로 잡힌다.
- 익명 컨테이너 fallback은 owner가 generic 인스턴스이거나 없을 때만 적용된다.

## Supported scope and non-goals

지원: 위 다섯 항목과 문서·CHANGELOG. 비지원: slice 필드 setter, optional slice 필드, receiver 없는 함수의
기본 심볼 규칙 변경(기존 ABI 유지), alias 체인 다단 해석.

## Reference source / commit / license

src/declare.zig, src/reflect/walk.zig, src/reflect/names.zig, src/gen/emit/shim.zig, src/gen/naming.zig. MIT.

## Completion criteria for the whole plan

`zig build test` 통과, generator case 스냅샷 갱신, docs 반영, CHANGELOG Unreleased 항목.
