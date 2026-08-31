# SCOPE

일반 test와 purego job을 `ubuntu-latest` 단일 runner로 고정하고 Windows compile job을
삭제한다. Linux shared library suffix는 `.so`로 고정한다.

# CONTEXT

## Current implementation and bottlenecks

`test`는 Ubuntu/macOS 2개, `purego`는 Ubuntu x64·arm64와 macOS x64·arm64 4개,
`windows-compile`은 Windows 1개로 총 7개 runner가 같은 커밋에서 실행된다.

## Target structure and invariants

`test`와 `purego` 두 job만 남기고 모두 `ubuntu-latest`에서 실행한다. 각 job 내부의 검증
범위와 실패 조건은 유지하며 macOS용 suffix와 플랫폼 matrix 설명만 제거한다.
