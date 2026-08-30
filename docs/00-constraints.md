# 제약과 리스크

zigo가 반드시 지켜야 하는 기술적 제약들. 설계의 상당 부분이 이 제약에서 직접 유도된다.

---

## 1. 파라미터 이름은 reflection에 없다

`@typeInfo(@TypeOf(f)).@"fn".params` 는 `is_generic`, `is_noalias`, `type` 만 준다.
**`name` 필드가 없다.** reflection만으로 얻을 수 있는 최선은 이것이다:

```c
int32_t zg_context_process(zg_context*, const float*, size_t, float*, size_t, size_t*);
//                                       ^p0            ^p1     ^p2    ^p3     ^out
```

`Process(input []float32, output []float32)` 같은 의미 있는 Go 시그니처는 여기서 나오지 않는다.

**대응 — 3단계 이름 해석:**

| 우선순위 | 출처 | 신뢰도 |
|---|---|---|
| 1 | `bindings.zig`의 `.params = .{ "input", "output" }` | 권위 |
| 2 | `std.zig.Ast`로 원본 선언부 스캔 (문법 수준만) | 최선 노력 |
| 3 | `p0, p1, …` + 경고 | 폴백 |

2번은 파서만 쓰며 **타입 판단에는 절대 사용하지 않는다.** 이 경계를 넘으면
"Zig 소스를 파싱하지 않는다"는 원칙이 무너진다.

---

## 2. generic 함수는 시그니처가 존재하지 않는다

```zig
pub fn Buffer(comptime T: type) type { ... }
```

`@typeInfo`는 `params[0].is_generic = true`, `type = null`, `return_type = null`을 준다.
**구체화 이전에는 읽을 것이 없다.**

따라서 `bindings.zig`의 명시적 specialization 목록은 편의 기능이 아니라
**generic을 다루는 유일한 수단**이다.

```zig
.{ .name = "FloatBuffer", .type = lib.Buffer(f32) },
```

부수 효과로 설계가 단순해진다: reflector는 항상 이미 구체화된 타입만 본다.
comptime 파라미터가 남아 있는 함수는 하강에서 거부한다.

---

## 3. 일반 Zig struct는 ABI 레이아웃이 정의되어 있지 않다 ★

Zig의 기본 struct는 필드 재정렬·패딩이 **명세되지 않았고 컴파일러 버전에 따라 바뀔 수 있다.**
`@offsetOf`로 현재 레이아웃을 읽어 C 구조체를 만들면, Zig 업그레이드 시 조용히 깨지는
바인딩이 생긴다.

**규칙 (예외 없음):**

| Zig 선언 | 노출 |
|---|---|
| `extern struct` | 값 전달. C/Go struct 미러링 |
| `packed struct` | 정수 백킹으로 전달 + Go 비트 접근자 |
| 일반 `struct` | **opaque only.** 포인터로만 |

값 전달을 원하면 사용자가 `extern struct`로 선언해야 한다. 진단이 이를 안내한다.

이 제약은 §7의 크로스 컴파일 문제도 대부분 해소한다.

---

## 4. 에러 코드에 `@intFromError`를 쓸 수 없다

그 값은 컴파일 단위 전체의 에러 집합에 의존하며 **빌드마다 달라질 수 있다.**
C ABI 에러 코드로 노출하면 라이브러리 재빌드만으로 ABI가 깨진다.

**대응:** 생성기가 소유하는 append-only 테이블 `errors.lock.json`을 커밋한다.

- 코드는 배정 후 **불변**. 삭제된 에러의 코드는 재사용하지 않는다
- `0 = OK`, 음수는 프레임워크 예약 (`-1` unknown, `-2` panic, `-3` callback panic, `-4` invalid handle)
- 기존 매핑을 바꾸려는 시도는 도구가 거부한다

또한 추론된 에러 집합은 경우에 따라 `anyerror`로 넓어진다. `anyerror` 반환은
안정 코드 배정이 불가능하므로 **하강에서 거부**하고 명시적 에러 집합을 요구한다.

---

## 5. Zig panic은 언어 수준에서 복구할 수 없다

에러 유니온은 코드로 변환되지만 `unreachable`, 인덱스 초과, `catch unreachable` 등에는
Go의 `recover`가 통하지 않는다.

**대응:** 생성된 C wrapper가 호출 경계를 만들고, shim의 커스텀 panic 핸들러가
진단 문자열을 저장한 뒤 그 경계로 돌아가 `-2`를 반환한다. 문자열은
`zg_last_error_message()`로 조회한다.

**이는 복구 계약이 아니다.** panic이 발생한 작업과 관련 상태는 신뢰하지 말고 중단해야 한다.
경계의 목적은 로그를 남길 기회를 주고 Go 프로세스 전체의 즉시 종료를 피하는 것이다.

---

## 6. cgo 호출 비용과 Go 포인터 규칙

**비용:** cgo 호출 오버헤드는 순수 Go 호출의 수십 배다. 호출당 작업량이 작은 API를
1:1로 노출하면 바인딩이 실용성을 잃는다. 배치 지향 API 설계를 권장하고,
호출 오버헤드 벤치마크를 CI에 기록해 회귀를 감지한다.

**포인터 규칙:** Go 메모리를 가리키는 포인터는 호출 동안만 유효하며,
**Go 포인터를 담고 있는 Go 메모리**는 넘길 수 없다.

- `[]f32`, `[]u8` 같은 스칼라 슬라이스 → 안전
- 포인터를 품은 원소 타입의 슬라이스 → **하강에서 거부**

**보관:** Zig가 넘겨받은 포인터를 호출 이후까지 보관하면 GC와 충돌한다.
IR의 `retention: borrowed | retained`를 필수 필드로 두고 기본값을 `borrowed`로 한다.
`retained`인데 대응 해제 함수가 없으면 거부한다.

---

## 7. 크로스 컴파일 — reflector는 실행되어야 한다

reflector는 컴파일만 되는 것이 아니라 실행되어 IR을 stdout으로 뱉는다.
타깃용 reflector는 호스트에서 돌지 않는다.

- `semantic.json` — 타깃 독립. 호스트 빌드로 한 번 얻으면 된다. **문제 없음**
- `layout.<target>.json` — `@sizeOf`/`@alignOf`/`@offsetOf` 결과. **타깃별로 다름**

**v1 방침:** layout 정보를 생성 입력으로 쓰지 않는다.
값 전달을 `extern struct`로 제한했으므로(§3) C 컴파일러가 헤더로부터 동일 레이아웃을 도출한다.
layout.json은 *네이티브 빌드의 검증용*이며, 크로스 빌드에서는 생략한다.

v2에서 레이아웃 상수를 타깃별 컴파일 산출물에서 추출하는 방식으로 강화한다.

---

## 8. 콜백의 실제 제약

`Go func → cgo.Handle → C 트램폴린 → Zig` 경로 자체는 성립하지만:

- Zig 콜백 타입은 반드시 `callconv(.c)`. 그 외는 ABI 보장이 없어 거부한다
- Go 콜백에서 panic이 나면 cgo 경계를 넘어가며 프로세스가 죽는다 →
  생성된 트램폴린이 `defer recover()`로 감싸고 `-3`으로 변환한다
- 콜백이 Zig 쪽에 **저장**되면(`retained`) `cgo.Handle` 수명 관리가 필요하다 →
  Go 래퍼에 `Close()`를 **강제 생성**하고 미호출 시 누수임을 문서화한다

---

## 9. 하강이 실패해야 하는 경우

조용히 잘못된 바인딩을 만드는 것보다 빌드 실패가 낫다.

| 코드 | 조건 | 근거 |
|---|---|---|
| ZIGO001 | `anyerror` 반환 | §4 |
| ZIGO002 | non-exhaustive enum | 정수 매핑 불안정 |
| ZIGO003 | 값 전달 대상이 `extern`/`packed`가 아닌 struct | §3 |
| ZIGO004 | `callconv(.c)`가 아닌 함수 포인터 | §8 |
| ZIGO005 | 포인터를 포함하는 원소 타입의 슬라이스 | §6 |
| ZIGO006 | tagged union (v1) | 표현 미정 |
| ZIGO007 | 심볼 이름 충돌 | 자동 번호 부여는 ABI 불안정 |
| ZIGO008 | comptime 파라미터가 남은 함수 | §2 |
| ZIGO009 | `retained` 포인터에 대응 해제 함수 부재 | §6 |

진단은 **선언 위치 + 수정 방법**을 포함한다.

```
error[ZIGO003]: cannot pass `mylib.Config` by value
  --> src/bindings.zig: functions[2] (mylib.configure)
  Zig struct layout is unspecified for non-extern structs.
  hint: declare it as `extern struct`, or expose it as
        .{ .type = mylib.Config, .repr = .@"opaque" }
```

---

## 10. 리스크 등록부

| 리스크 | 영향 | 확률 | 완화 |
|---|---|---|---|
| Zig `@typeInfo` 구조 변경 | 높음 | 높음 | reflector를 얇게 격리, `minimum_zig_version` 고정, JSON 골든 테스트 |
| `std.Build` API 변경 | 중간 | 높음 | `addGoBindings` 한 함수에 격리, 예제 저장소 CI |
| 파라미터 이름 부재로 API 품질 저하 | 중간 | 확실 | §1의 3단계 해석 |
| 일반 struct 레이아웃 파손 | 치명적 | 중간 | §3 opaque 강제 |
| cgo 오버헤드로 실용성 부족 | 중간 | 중간 | 배치 API 권장, 벤치마크 CI 기록 |
| Go GC와 retained 포인터 충돌 | 치명적 | 중간 | §6 `retention` 필수 필드 + 검증 |
| 크로스 컴파일 미지원 | 중간 | 확실 | §7 v1 네이티브 한정, v2 강화 |
