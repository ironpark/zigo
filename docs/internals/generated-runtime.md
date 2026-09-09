# 생성 Go runtime

이 문서는 생성 파일을 review하거나 zigo emitter를 수정할 때 필요한 public package 내부 구조를
설명합니다. application에서 의존할 API는 [생성 Go API](../reference/generated-go-api.md)입니다.

## 파일 역할

실제 파일은 필요한 declaration이 있을 때만 생성됩니다.

| pattern | 역할 |
|---|---|
| `<package>_gen.go` | public function과 method |
| `<package>_enums_gen.go` | enum type, constant와 text method |
| `<package>_structs_gen.go` | value struct와 값 union 변환 |
| `<package>_handles_gen.go` | owned/borrowed handle과 lifecycle |
| `<package>_runtime_gen.go` | package-private 변환과 runtime support |
| `<package>_union_<name>_gen.go` | projection, snapshot과 sealed variant |
| `<package>_errors_gen.go` | sentinel과 structured error |
| raw `*_gen.go` | cgo call 또는 purego symbol table |
| `internal/lifecycle` | 여러 public package가 공유하는 lifecycle |

모든 Go source는 기록 전에 `gofmt`를 통과합니다. public declaration은 Zig source doc 또는
binding override를 사용하고 없으면 ownership/failure를 설명하는 기본 GoDoc을 만듭니다.

## handle state

public handle은 native pointer와 closed/poison state, active call, child와 retained callback
관계를 관리합니다.

method 시작은 handle을 acquire하고 반환 시 release합니다. `Close`가 동시에 실행되어도 active
method가 사용하는 pointer가 먼저 해제되지 않습니다. 이 보호는 native object의 method끼리
serialize하는 mutex가 아닙니다.

| handle | `Close` 동작 |
|---|---|
| owned | destructor를 한 번 예약·실행 |
| dependent child | destructor 뒤 parent reservation 해제 |
| borrowed view | owner에서 detach; native destructor 없음 |
| union `Ref` | 별도 `Close` 없음 |

parent는 열린 dependent child가 있으면 `ErrHandleInUse`를 반환합니다. borrowed view 호출은
owner lifecycle도 acquire하여 owner가 먼저 파괴되지 않게 합니다.

panic이 native frame을 비정상적으로 끝내면 참여 handle을 poison합니다. 이후 호출은 실패하고
안전하지 않은 destructor는 건너뛸 수 있습니다.

## callback registry

borrowed callback token은 call 종료 후 해제합니다. retained callback token은 이를 소유한 handle
slot에 저장하고 교체 또는 `Close` 때 해제합니다.

cgo에서는 native registration call의 반환을 이전 callback에 새 호출이 오지 않는 경계로
사용합니다. purego registry는 이미 진행 중인 callback 호출이 끝날 때까지 해제를 조정합니다.

callback panic은 trampoline이 value와 stack을 저장합니다. public native call이 돌아온 뒤
runtime이 이를 꺼내 `*CallbackPanicError`로 다시 panic합니다. 정상 fast path는 pending panic
count를 확인한 뒤 slot 순회를 건너뜁니다.

## package 분할

public package가 여러 개면 `internal/lifecycle`이 공통 handle contract와 error identity를
소유합니다. 각 public package는 type alias와 sentinel variable로 같은 identity를 다시
노출합니다. 따라서 서로 다른 생성 package의 같은 runtime sentinel도 `errors.Is`로 연결됩니다.

raw cgo package와 purego loader/registry는 설정한 raw package에 남습니다.

## purego loader

platform primitive는 build tag별 파일로 나뉩니다.

```text
raw_load_posix_gen.go    //go:build !windows
raw_load_windows_gen.go  //go:build windows
```

POSIX는 purego의 dynamic loader, Windows는 standard `syscall` loader를 사용합니다. 공통
파일이 candidate path, symbol table과 `LibraryError`를 관리합니다. 필요한 symbol을 모두
찾은 뒤에만 loaded state가 됩니다.

Windows shared library는 loader가 찾는 entry point에 `__declspec(dllexport)`가 필요합니다.
생성 header의 `ZIGO_EXPORT`가 Windows에서만 이 annotation으로 확장됩니다.

## 이름과 helper

- Zig snake_case parameter는 Go camelCase가 됩니다.
- keyword와 local collision은 suffix 또는 대체 이름으로 피합니다.
- receiver 이름은 type의 모든 method에서 일관되게 선택합니다.
- public free function에는 Zig namespace가 자동으로 붙지 않습니다.
- package-private helper는 `zigo` prefix를 사용합니다.
- 실제로 public body에서 참조된 helper만 출력합니다.

emitter 구조는 [`src/gen/emit`](../../src/gen/emit)을 참고하세요.
