# GOALS

## Problem and the end result from the user's point of view

0.4.1의 `hostReflectionModule`(`build.zig:1299`)은 reflection을 위해 사용자 module을 호스트용으로 복제하면서 `.other_step`(다른 Compile 아티팩트)을 버린다. ghostty는 `m.linkLibrary(simdutf_dep.artifact("simdutf"))`로 simdutf를 붙이고 자기 C++ 소스(`c_source_files`)가 그 아티팩트를 통해 libc++와 include를 얻는다. 복제본은 C++ 소스는 유지하고 libc++ 연결은 잃어 `simdutf.h: 'cstring' file not found`로 컴파일이 깨진다. 0.3.x(복제 도입 전)에서는 통과했으므로 회귀다. 현재 우회는 `-Dsimd=false`로 성능 손실이 있다.

끝난 뒤: `.other_step`으로 붙은 라이브러리가 C++이거나 libc를 요구하면 복제본도 같은 설정을 갖고, reflection이 SIMD를 켠 ghostty-vt에서 통과한다. 크로스 컴파일(0.4.1이 고친 것)은 계속 동작한다.

## Measurable goals

- 회귀 테스트: 예제 하나에 C++ 정적 라이브러리(`addLibrary` + `linkLibCpp` + `.cpp` 소스)를 `linkLibrary`로 붙이고, 사용자 module의 C 소스(또는 C++ 소스)가 그 라이브러리의 header를 include하는 형태에서 `zig build go-lib`가 통과.
- 같은 예제가 `-Dtarget=x86_64-windows-gnu`, `x86_64-linux-gnu`, `aarch64-linux-musl` 크로스 `go-lib`를 통과.
- CI `test` job의 크로스 빌드 스텝이 계속 통과.

## Supported scope and non-goals

- 범위: `build.zig` `hostReflectionModule`, 예제/CI, 문서, CHANGELOG.
- 비범위: reflection을 host 실행 없이 하는 구조 변경.

## Reference source / commit / license

`build.zig:1299-1340`(`hostReflectionModule`), `build.zig` `staticLibraryInputs`, 0.4.1 커밋 `6f9f5b0`. gostty `docs/zigo-findings.md` D 항목. 라이선스 변경 없음.

## Completion criteria for the whole plan

모든 phase done, `zig build test`·`zig fmt --check`·전 예제 cgo+purego 녹색, 크로스 `go-lib` 3종 통과, CHANGELOG Unreleased Fixed.
