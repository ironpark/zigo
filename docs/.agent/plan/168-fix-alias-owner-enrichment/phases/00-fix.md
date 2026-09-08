---
perf_phase: false
status: in-progress
---
> DONE-WHEN: `zig build test`가 통과하고 `git status --porcelain examples`가 비어 있다.
> NEXT: none

# Fix and regression tests

## Planned Work

- `Alias`에 `owner_import`를 더하고 `Aliases.put`과 `deinit`이 그 수명을 갖게 한다.
- `collectAliases`가 각 컨테이너의 `const X = @import("path")` 바인딩을 **먼저** 모아
  `recordAlias`에 넘긴다. Zig는 선언 순서가 없어 import가 alias 아래 있을 수 있다.
- `.file` 분기에서 alias로 도달한 매칭을 `owner_import` 경로로 검증한다.
- `.file` 분기가 `function.receiver`를 두 번째 증인으로 인정한다.
- `receiverTypeNames`를 전 파라미터로 넓히고 타입 비교를 `typeNames`로 분리한다.
- 세 결함에 회귀 테스트를 하나씩 붙인다.

## Done When

- `zig build test`가 통과하고 `git status --porcelain examples`가 비어 있다.
- 세 테스트가 각자의 수정을 되돌렸을 때 실패하는 것이 확인된다.
- gostty를 이 트리에 붙여 재생성했을 때 헤더와 `raw_gen.go`가 0.18.0 기준선과 동일하고,
  `go build`·`vet`·테스트·`-race`·예제가 모두 통과한다.
