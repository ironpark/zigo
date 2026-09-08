# SCOPE

- `src/reflect/names.zig`: `Alias`, `Aliases.put`, `collectAliases`, `recordAlias`,
  `enrichMatches`의 `.file` 분기, `receiverTypeNames`.
- `CHANGELOG.md`의 `## [Unreleased]` 절.
- 릴리즈 산출물: `build.zig.zon` 버전, README와 시작 가이드의 fetch 줄(release.sh가 처리).

# CONTEXT

## Current implementation and bottlenecks

`enrichMatches`의 `.file` scope는 root 프로토타입을 바인딩에 붙일지 판단합니다. 세 지점이
막혀 있습니다.

1. `declaration.owner`는 alias를 거치면 **재노출한 파일의 import 이름**이 됩니다.
   `pub const setTabstop = config_.setTabstop;`은 owner를 `config_`로 만드는데, 대상 파일의
   프로토타입은 `self: *Terminal`이라 그 이름으로 증명될 수 없습니다.
2. `receiverTypeNames`가 첫 파라미터만 봅니다. 주입된 allocator가 앞서는
   `newStream(gpa: Allocator, terminal: *Terminal, ...)`에서 receiver를 놓칩니다.
3. receiver가 없는 자유 함수는 증인 검사가 통째로 생략되고 "파일을 자기 말대로" 믿습니다.
   ghostty의 `input`은 `encodeFocus = focus.encode`와 `encodePaste = paste.encode`를 함께
   두는데 대상 이름이 둘 다 `encode`라, `input/paste.zig`가 focus 인코더까지 가져갑니다.

## Target structure and invariants

- alias로 도달한 `.file` 매칭은 alias owner가 `@import`일 때 그 경로가 현재 스캔 중인
  파일과 맞아야만 통과한다. 아니면 그 파일은 대상을 주장할 수 없다.
- 메서드는 바인딩이 묶은 receiver 타입도 증인으로 인정한다. 프로토타입이 실제로 적어 둔
  이름이기 때문이다.
- 증인은 "프로토타입이 그 타입을 어딘가에 적었다"이고, 이름과 arity 검사는 그대로 별도로
  유지되므로 매칭이 느슨해지지 않는다.
