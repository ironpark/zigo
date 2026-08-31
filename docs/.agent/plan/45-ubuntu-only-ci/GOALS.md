# GOALS

## Problem and the end result from the user's point of view

현재 CI는 일반 테스트를 Ubuntu와 macOS에서, purego를 네 가지 OS·아키텍처에서, compile
검사를 Windows에서 별도로 실행해 비용이 크다. 모든 CI job을 Ubuntu 한 환경에서만 실행해
중복 비용을 줄이면서 기존 핵심 검증 내용은 유지한다.

## Measurable goals

- GitHub Actions의 모든 job이 `ubuntu-latest`에서만 실행된다.
- OS·아키텍처 matrix와 Windows 전용 job을 제거한다.
- Zig test, 모든 cgo 예제, purego 생성·검증·로드 테스트는 그대로 남는다.

## Supported scope and non-goals

`.github/workflows/ci.yml`의 runner 구성과 플랫폼별 분기만 변경한다. 지원 플랫폼 자체나
라이브러리 구현, 생성물, Go/Zig 버전은 변경하지 않는다.

## Reference source / commit / license

현재 `main`의 `.github/workflows/ci.yml`과 로컬 Ubuntu 호환 명령을 기준으로 한다.

## Completion criteria for the whole plan

workflow에 Ubuntu 외 runner나 OS matrix가 없고 YAML이 유효하며, 유지한 핵심 명령이 로컬에서
성공한다. 변경과 plan 상태가 커밋되어 있다.
