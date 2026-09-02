---
completed_at: "2026-09-02T13:48:19Z"
perf_phase: false
status: done
---
> DONE-WHEN: 예제에서 `zig build` 후 `zig-out/lib`에 라이브러리가 있고 `go test`가 바로 통과, 커밋.
> NEXT: none

# 기본 install에 바인딩 라이브러리

## Planned Work

- `addStandardSteps`에서 `b.getInstallStep().dependOn(&self.install_library.step)`; `StandardStepOptions`에 끄는 옵션 추가.
- `docs/configuration.md` 갱신, CHANGELOG.

## Done When

- 예제에서 `zig build` 후 `zig-out/lib`에 라이브러리가 있고 `go test`가 바로 통과, 커밋.
