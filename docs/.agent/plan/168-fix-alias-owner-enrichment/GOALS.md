# GOALS

## Problem and the end result from the user's point of view

0.19.1은 파일이 곧 struct인 소스의 root 선언을 되살렸지만, 그 소스가 **다른 파일에서
재노출된** 경우는 여전히 놓칩니다. gostty를 0.19.1로 재생성하면 C 헤더 74줄의 파라미터
이름이 `p0`으로 떨어지고 공개 Go 문서 242줄이 사라집니다. 같은 패스가 반대 방향으로도
틀려서, ghostty의 `input` 네임스페이스에서 `EncodeFocus`가 `encodePaste`의 문서를 받습니다.
문서가 없는 것보다 나쁩니다.

수정 뒤 gostty의 C ABI는 0.18.0 기준선과 바이트 단위로 같고, 남는 Go 차이는 0.18이 엉뚱한
동명 선언에서 긁어 오던 문서의 교정뿐입니다.

## Measurable goals

- gostty 재생성 시 `libs/include/zigo_gostty.h`와 `internal/raw/raw_gen.go`가 0.18.0 커밋
  기준선과 바이트 동일하고, 헤더의 `p0`류 이름이 0건.
- `EncodeFocus`가 다른 함수의 문서를 받지 않고, `IsSafePaste`는 자기 문서를 받는다.
- 세 결함마다 회귀 테스트가 하나씩 있고, 해당 수정을 되돌리면 그 테스트가 실패한다.
- zigo 자체 테스트 전부 통과, 13개 예제 생성물 무변화.

## Supported scope and non-goals

범위는 `src/reflect/names.zig`의 AST 이름·문서 보강 패스입니다. semantic IR, 생성 코드,
C ABI, 플러그인 계약은 건드리지 않습니다. `focus = terminal.focus`처럼 import가 아닌
재-alias를 여러 단계 따라가는 것은 비목표입니다 — 그런 owner는 파일을 지목할 수 없으므로
매칭을 거부하고 문서를 비워 두는 쪽이 맞습니다.

## Reference source / commit / license

gostty(github.com/ironpark/gostty, MIT) 커밋 f231bd5의 생성물이 기준선입니다. 오매칭
사례는 ghostty 1.3.2-dev의 `src/lib_vt.zig` `input` 네임스페이스입니다.

## Completion criteria for the whole plan

수정과 회귀 테스트가 커밋되고, CHANGELOG 절이 채워지고, `scripts/release.sh`로 0.19.2가
태그·푸시되어 gostty가 그 태그를 핀으로 잡고 재생성·검증까지 통과한 상태.
