# GOALS

## Problem and the end result from the user's point of view

부모 핸들의 `Close`는 자식이 열려 있으면 기다리지 않고 **거절**합니다.
`src/gen/emit/handles.zig:277`의 in-use 검사가 `children` 카운터를 보고
`*HandleInUseError`를 돌려줍니다. 그래서 `EventQueue`에서 `NewStream`으로 얻은
`Stream`이 열려 있는 동안 `queue.Close()`를 부르면 실패합니다.

올바른 teardown 순서(자식 → 부모)를 지키는 일은 지금 전적으로 소비자 몫입니다.
`defer`를 선언 순서대로 쓰면 자연히 역순이 되지만, 자식이 조건부로 만들어지거나
여러 개이거나 다른 함수에서 만들어지면 곧 손으로 관리하는 코드가 됩니다. 실제로
소비자 쪽에서는 이 순서를 감추는 상위 객체를 매번 직접 씁니다.

이 계획이 끝나면 바인딩 작성자가 선언 한 줄로 그 상위 객체를 생성기에서 받습니다.

```zig
zigo.session(.{
    .name = "Session",
    .primary = EventQueue.typeRef(),
    .children = &.{Stream.typeRef()},
})
```

```go
session := event_queue.NewSession(queue, stream)
defer session.Close() // Stream.Close() 다음 EventQueue.Close()
queue := session.EventQueue()
```

## Measurable goals

- `Session.Close()`가 자식을 먼저, 그 다음 primary를 닫는다. 같은 핸들들을 잘못된
  순서로 직접 닫으면 나던 `*HandleInUseError`가 나지 않는다.
- `Session.Close()`를 여러 번 불러도, 여러 goroutine에서 동시에 불러도 안전하다.
- 자식 `Close`가 실패해도 나머지 멤버를 계속 닫고 모든 오류를 함께 보고한다.
- `var _ io.Closer = (*Session)(nil)`이 생성 코드에서 컴파일된다.
- `zig build abi-check`가 차이를 보고하지 않는다. C 심볼과 shim이 그대로다.
- primary의 dependent child가 아닌 타입을 `children`에 적으면 진단으로 거절된다.

## Supported scope and non-goals

지원 범위는 `.role = .{ .constructor = .{ ..., .parent = .receiver } }`로 선언된
dependent 부모-자식 관계와 Go 출력 target입니다.

non-goal:

- **메서드 포워딩.** `Session`에 `Write`/`Read` 같은 멤버 메서드를 자동으로 달지
  않습니다. 한 번 시작하면 어떤 메서드를 얼마나 올릴지 끝이 없고, 이미 `zigo.interface`와
  `satisfies` 플러그인이 그 축을 맡고 있습니다. `Session`은 수명만 다룹니다.
- **자식 자동 생성.** `Session`은 이미 만들어진 핸들을 입양(adopt)할 뿐, 생성자를
  대신 부르지 않습니다. 생성 인자와 실패 처리를 감추면 오류 경로가 흐려집니다.
- borrowed 결과(`zigo.result.borrowed()`)와 `Ref` 타입. 이들은 `Close` 대상이 아닙니다.
- 여러 패키지에 걸친 Session. 1단계에서는 모든 멤버가 같은 생성 패키지에 있어야 합니다.
- Rust target. 이 선언은 Go 출력에만 반영됩니다.

## Reference source / commit / license

외부 소스를 가져오지 않습니다. 저장소 안의 기존 구현을 참조합니다.

- `src/gen/plugins/interfaces.zig` -- 선언 하나로 합성 Go 파일을 통째로 만드는 유일한
  선례. `zigo.interface` 선언 key, 전용 파일, `ZIGO049` 진단을 갖춘 내장 플러그인이며
  Session이 따라야 할 구조가 그대로 있습니다.
- `src/gen/emit/handles.zig:51`, `:168`, `:188` -- `children` 카운터와
  `zigoAcquireChild`/`zigoDropChild`
- `src/gen/emit/handles.zig:260`, `:277` -- 자식이 남아 있을 때 `Close`가 거절하는 지점
- `src/gen/emit/public_runtime.zig:99`, `:148` -- `ErrHandleInUse`와 `HandleInUseError`
- `plugins/satisfies/src/plugin.zig` -- `var _ io.Closer = (*T)(nil)` 관용구
- `examples/07-event-queue/src/bindings.zig:30` -- `EventQueue.newStream`의 dependent 자식

## Completion criteria for the whole plan

모든 phase가 done이고, `scripts/release.sh`가 실행하는 검사가 통과하며,
`docs/authoring/objects-and-lifetimes.md`와 참조 문서가 `zigo.session`을 설명하고,
`examples/07-event-queue`가 Session을 실제로 쓰는 Go 테스트를 가집니다.
