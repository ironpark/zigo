# SCOPE

두 가지 접근 중 하나를 고르고 CONTEXT에 기록한다.

1. **호스트 변형 라이브러리(권장)**: 버리던 `.other_step` 정적 라이브러리의 `root_module`을 같은 함수로 호스트용 복제하고 `b.addLibrary`로 호스트 변형을 만들어 복제본에 `linkLibrary`한다. 아티팩트가 들고 오던 include, libc/libc++, 심볼이 모두 보존된다. `.static_path`(미리 빌드된 archive)는 여전히 버린다. 재귀·순환은 기존 `clones` 맵으로 처리하고, Compile 단위 캐시 맵을 하나 더 둔다.
2. **설정 전파(대안)**: `.other_step`을 버리되 그 Compile의 module 그래프를 걸어 `link_libc`/`link_libcpp`가 켜져 있으면 복제본에 켜고, 그 module들의 `include_dirs`/`c_macros`를 복제본에 합친다. 심볼은 여전히 없다.

- 예제: 01-scalar의 `scalar_support`를 C++로 바꾸거나(`support.cpp` + `linkLibCpp`) 별도 지원 라이브러리를 추가해 회귀를 고정한다.
- CI: 이미 있는 크로스 빌드 스텝이 그 예제를 포함하는지 확인하고, 아니면 추가한다.
- 문서: `docs/configuration.md`의 reflection 복제 설명, `docs/limitations.md` 갱신, CHANGELOG.

# CONTEXT

## Current implementation and bottlenecks

- `hostReflectionModule`은 `root_source_file`, target=host, optimize, `link_libc`, `link_libcpp`, `single_threaded`, `sanitize_c`, `no_builtin`, imports(재귀), `c_macros`, `include_dirs`, `lib_paths`, frameworks(darwin host만), `.system_lib`/`.c_source_file`/`.c_source_files` link object를 복제하고 `.other_step`/`.static_path`/`.assembly_file`/`.win32_resource_file`은 버린다.
- Zig에서 `linkLibrary(lib)`는 `link_objects.other_step`과 `include_dirs.other_step`을 추가하고, 링크 시 그 lib의 libc/libc++ 요구가 소비자에게 전파된다. 복제본은 이 전파를 잃는다.
- 사용자 module 자체의 `link_libcpp`는 null일 수 있다(ghostty는 아티팩트에만 켠다).

## Target structure and invariants

- 복제본은 "호스트에서 컴파일·링크 가능한, 같은 타입 표면을 가진 module"이어야 한다. 심볼 존재는 reflection에 필요 없지만 헤더·언어 런타임 설정은 컴파일에 필요하다.
- 접근 1을 택하면 `.other_step` 중 `isStaticLibrary()`인 것만 호스트 변형을 만들고, 동적 라이브러리는 버린다(호스트에서 로드하지 않음). Compile 옵션 중 복제할 것: name, root_module(복제), linkage static, `linkLibC`/`linkLibCpp`는 module 값으로 따라온다. `installed_headers`(installHeader로 붙은 것)는 `include_dirs.other_step`가 원본 Compile을 가리키므로 원본의 헤더 트리를 그대로 쓴다.
- 크로스 컴파일 시 호스트 변형이 target 변형과 별도로 빌드되며, 이는 허용되는 비용이다.
