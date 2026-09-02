---
perf_phase: true
status: in-progress
---
> DONE-WHEN: `bytes.Buffer` 입력에서 콜백 0회 테스트 통과.
> NEXT: none

# `[]byte` 무콜백 Reader 경로

## Planned Work

- 70의 스트림 ABI에 슬라이스 변형 추가(70이 아직 진행 전이면 70에 합쳐 breaking 회피). shim `Reader.fixed` 분기, Go 타입 단정.
- 11-io-streams에 콜백 0회 테스트. 문서.

## Implementation Notes

계획 70이 reader의 C 시그니처에 `(<name>_data, <name>_data_len)`을 미리 넣어 두었고 shim도
이미 `if (r_data != null) .fixed(...)`로 분기하고 있었다. 그래서 이 phase는 Go 쪽만 바뀌었고
C 헤더·shim·`semantic.json`·`errors.lock.json`은 한 바이트도 바뀌지 않았다. ABI 변경 없음.

**자격 있는 타입.** `zigoBytes() []byte`(공개 훅, 우선순위 높음)와 `Bytes() []byte`
(`*bytes.Buffer`)만이다. `*bytes.Reader`는 내부 슬라이스를 내주는 메서드가 없어 CONTEXT의
예상대로 제외했다. 널 슬라이스는 "빠른 경로 없음", 널이 아닌 빈 슬라이스는 "빈 스트림"이며,
후자는 raw 계층의 `zigoEmptyStreamData` 주소를 넘겨 포인터가 널이 되지 않게 한다.

**CONTEXT에서 벗어난 점.** 이 경로를 타면 Go reader가 전진하지 않는다. C ABI에 소비한
바이트 수를 되돌릴 자리가 없고, 그 자리를 만드는 것은 ABI 변경이라 이 phase의 "ABI 불변"
전제와 충돌한다. 추측으로 `Reset`/`Next`를 부르는 대신 동작을 그대로 두고
`docs/bindings.md`와 `docs/limitations.md`에 명시했다. 소비 위치가 중요한 호출자는
`bytes.NewReader(...)`처럼 빠른 경로에 들어가지 않는 타입을 쓰면 된다.

## Done When

- `bytes.Buffer` 입력에서 콜백 0회 테스트 통과.
