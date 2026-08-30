# 적대적 시스템 검증

검증 기준: 2026-08-30, Zig 0.16.0, Go 1.26.3, macOS arm64.

이 문서는 정상 경로만 재실행하지 않고 입력과 생성물을 의도적으로 변형해 build graph,
generator, ABI 정책과 FFI 수명주기의 실제 실패 동작을 확인한 결과다. 모든 부정 실험은
임시 디렉터리에서 수행하며 추적 중인 fixture를 직접 변형하지 않는다.

## 판정 기준

- 정상 실험은 exit 0과 예상 산출물 또는 상태를 모두 만족해야 한다.
- 부정 실험은 non-zero exit만으로 충분하지 않다. 실패 원인을 식별할 수 있는 진단도 있어야 한다.
- 생성 실패 전후의 기존 출력은 byte-identical이어야 한다.
- 동일 입력의 독립 생성 결과는 파일 집합과 내용이 byte-identical이어야 한다.
- retained callback과 native owner는 명시적 `Close` 및 선택적 cleanup 뒤에 중복 해제나
  handle 누수를 남기지 않아야 한다.

## 실험 결과

| 실험 | 방법 | 기대 | 관측 | 판정 |
|---|---|---|---|---|
| 루트 기준선 | `zig build test --summary all` | 모든 unit/golden 통과 | 22/22 step, 52/52 test 통과 | 통과 |
| 소비자 build graph | 8개 예제에서 `zig build go-check abi-check --summary all` | stale 없음, breaking ABI 없음 | 예제별 16/16 step 통과 | 통과 |
| 생성 Go API 실행 | 8개 Go module에서 `go test -count=1 ./...` | 실제 cgo 호출 통과 | 모든 module 통과 | 통과 |
| 독립 생성 결정성 | complex semantic/lock을 서로 다른 두 디렉터리에 생성 후 recursive diff | 파일 집합과 bytes 동일 | 9개 파일 동일 | 통과 |

독립 생성에서 확인한 파일 집합은 header, shim, panic bridge, errors lock, raw Go 파일과
분리된 public callable/type/error/helper Go 파일이다. 해시는 출력 절대 경로에 영향을 받지
않았고 recursive diff에는 차이가 없었다.

Go 링크 단계는 로컬 macOS deployment target보다 Zig object의 최소 OS 버전이 높다는 linker
warning을 출력했다. 현재 환경에서는 링크와 실행이 모두 성공했으므로 기능 결함으로 판정하지
않지만, 더 낮은 macOS 배포 버전을 지원할 때는 별도 target 설정 검증이 필요하다.

## 남은 실험

- 생성 Go 파일 손상과 semantic ABI 변형에 대한 stale/ABI gate
- invalid semantic, invalid `errors.lock.json`, allocation failure의 출력 원자성
- 자동 discovery, 대형 API, CamelCase와 세 raw package 배치
- `gofmt` 가용/비가용 경로
- retained callback 및 runtime cleanup 반복/race 검증
- host와 Windows 교차 타깃 compile gate

