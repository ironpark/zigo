---
description: "gostty가 우회한 zigo 갭 7건: 멤버 doc, std_options, session plural, returned slice written, must 대체, 다중 생성자, union 자리"
plan_status: in-progress
registered_at: "2026-09-13T07:28:55Z"
---
> NEXT: shim에 `std_options` 전달을 더한다. ([Phase 0](phases/00-shim-std-options.md))

# Phases

- [x] [Phase 00: std_options passthrough](phases/00-shim-std-options.md)
- [x] [Phase 01: Session child plural](phases/01-session-child-plural.md)
- [x] [Phase 02: Member docs from source](phases/02-member-docs-capture.md)
- [ ] [Phase 03: Member doc overrides](phases/03-member-docs-override.md)
- [ ] [Phase 04: Returned slice written hint](phases/04-returned-slice-written.md)
- [ ] [Phase 05: Plugin method replacement](phases/05-plugin-method-replace.md)
- [ ] [Phase 06: Multiple constructors per handle](phases/06-multiple-constructors.md)
- [ ] [Phase 07: Tagged union in slice and error union positions](phases/07-union-slice-and-error-union.md)
- [ ] [Phase 08: Docs, changelog and release](phases/08-docs-and-release.md)

# Shared Verification

`zig build test`, `zig build check`, generator case 골든 비교.
골든 갱신은 실패 출력의 actual 경로로 `zig build snapshot -- <expected> <actual> --update-snapshots`.

# Decisions That Constrain Ordering

0·1·2·4·5·6은 서로 독립이다. 3은 2가 `fields[].doc`을 만든 뒤에만 의미가 있다.
7은 앞의 것들이 끝나고 lowering 경로를 확인한 뒤에만 들어간다.
8은 마지막이며, 7이 미뤄지면 그 사실을 릴리즈 노트에 적는다.

# Next Implementation Target

shim에 `std_options` 전달을 더한다.
