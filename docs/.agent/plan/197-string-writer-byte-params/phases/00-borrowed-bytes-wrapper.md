---
completed_at: "2026-09-12T07:42:50Z"
perf_phase: false
status: done
---
> DONE-WHEN: `zig build test`가 통과한다.
> NEXT: none

# 바이트 매개변수 허용과 빌려 넘기는 래퍼

## Planned Work

- `src/gen/plugins/implements.zig`의 `.string_writer` `shape_ok`에서 `isTextHint` 요구를
  없앱니다. 조건은 `.in` 방향의 바이트 슬라이스 하나로 남습니다. 기대 shape 문구
  (`expected`)도 그에 맞게 고칩니다.
- `byte_hinted` 분기와 그 hint를 지웁니다. 이제 그 조합은 유효한 선언입니다. `.writer`에
  string semantic을 붙였을 때의 `text_hinted` hint는 그대로 둡니다.
- `renderImplementsWrapper`의 `.string_writer` 가지를 두 갈래로 나눕니다. 매개변수가 string
  semantic을 가지면 지금처럼 `s`를 넘기고, 아니면 먼저
  `zigoBytes := unsafe.Slice(unsafe.StringData(s), len(s))`를 쓰고 그것을 넘깁니다. 지역
  이름은 수신자 이름·매개변수 이름과 부딪히지 않는 생성기 접두사를 씁니다.
- 두 갈래 모두에 대해 주석을 정확하게 씁니다. 빌리는 쪽은 복사 없이 문자열의 바이트를
  호출 동안만 빌린다는 것을 한 줄로 적습니다.
- `implements.zig`에 단위 테스트를 더합니다. 바이트 매개변수 `.string_writer`가 진단을 내지
  않는 것, string semantic `.writer`가 여전히 `ZIGO058`인 것을 각각 확인합니다.
- `src/gen/validate/functions.zig`의 `string_writer_bytes` 케이스가 이제 통과 케이스임을
  반영해 그 테스트를 옮기거나 고칩니다.

## Done When

- `zig build test`가 통과한다.
- 바이트 매개변수에 붙은 `.string_writer`가 진단 없이 통과하고, string semantic이 붙은
  `.writer`는 여전히 `ZIGO058`을 받는다.
- 생성된 `WriteString`이 바이트 매개변수에서는 `unsafe.Slice(unsafe.StringData(...), len(...))`로
  빌린 슬라이스를 넘기고, string 매개변수에서는 인자를 그대로 넘긴다.
- 빌리는 래퍼가 있는 파일에만 `unsafe` import가 추가된다.
