# GOALS

## Problem and the end result from the user's point of view

0.19.0의 `owner_generic` 게이트가 파일이 곧 struct/namespace인 소스의 root 선언까지 막아 gostty
생성물이 `p0`·문서 없음으로 퇴화했다. 고친 뒤 0.19.1로 낸다.

## Measurable goals

- file-as-struct 메서드와 namespace 함수가 root 선언에서 이름·문서를 얻는 테스트 통과.
- 무관한 struct의 같은 이름 root 메서드는 receiver 타입으로 거부.
- 0.19.1 태그 푸시.

## Supported scope and non-goals

names.zig scope 정리, 문서, CHANGELOG, 릴리스. 새 기능 없음.

## Reference source / commit / license

src/reflect/names.zig. MIT.

## Completion criteria for the whole plan

테스트·예제 검사 통과, 0.19.1 공개.
