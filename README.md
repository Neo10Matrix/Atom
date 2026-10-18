# 아미사커 (Army Soccer)

군대 테마의 로블록스 **거대 공 구기 종목** 게임입니다. 한 경기장에서 축구와 배드민턴이 동시에 진행되고, 누구나 두 공을 모두 다룰 수 있습니다. 공 개수는 팀당 4명마다 축구공 1개 + 셔틀콕 1개씩 늘어납니다 (최소 1개씩).

- **축구**: 거대 축구공을 발로 차서(E) 상대 골대에 넣습니다. 골이 나면 다시 킥오프.
- **배드민턴**: 가운데 반투명 네트 너머로 거대 셔틀콕을 **헤딩**으로 넘깁니다. 같은 팀은 3번까지 헤딩할 수 있고, 3번째에 셔틀콕이 빨간색으로 바뀝니다. 4번째 터치는 반칙, 셔틀콕이 땅에 닿으면 그 진영 팀이 실점합니다.
- 경기장은 투명 벽으로 둘러싸여 있어 스로인·코너킥이 없습니다.

## 조작

| 입력 | 동작 |
| --- | --- |
| `E` 길게 눌렀다 떼기 | 축구공 킥 (오래 누를수록 세고 높게) |
| 점프 + 머리에 맞히기 | 셔틀콕 헤딩 (바라보는 방향으로 날아감) |
| `Q` | 돌격 (짧은 대시) |

## 경기 규칙

- **알파 분대**(녹색)와 **브라보 분대**(사막색)로 자동 배정, 인원이 적은 쪽에 들어갑니다.
- 5분 경기. 축구 골과 배드민턴 득점이 같은 점수판에 합산됩니다.
- 최소 2명이 모이면 경기가 시작됩니다 (Studio 테스트에서는 1명).

## 개발 환경 (Rojo)

1. [Rokit](https://github.com/rojo-rbx/rokit) 설치 후 프로젝트 폴더에서 `rokit install` (Rojo 7.4.4 설치)
2. Roblox Studio에 Rojo 플러그인 설치
3. `rojo serve` 실행 후 Studio의 Rojo 플러그인에서 **Connect**
4. Studio에서 플레이 (경기장은 서버가 코드로 자동 생성하므로 맵을 따로 만들 필요가 없습니다)

`.rbxlx` 파일로 바로 만들려면: `rojo build -o ArmySoccer.rbxlx`

## 구조

```
src/
  shared/Config.luau          모든 수치 설정 (경기 시간, 킥 파워, 포격 공 개수, 사격 영향 등)
  server/
    init.server.luau          서버 진입점, 원격 이벤트 생성
    FieldBuilder.luau         경기장/골대/벽/모래주머니/감시탑 생성
    CollisionGroups.luau      충돌 그룹 (네트는 셔틀콕만 막음)
    PlayerService.luau        팀 배정, 헬멧, 리더보드, 킥오프 배치
    BallService.luau          거대 축구공, 킥 처리, 골 판정
    ShuttleService.luau       거대 셔틀콕, 네트, 헤딩, 3번 터치 규칙, 착지 판정
    MatchService.luau         경기 흐름 (대기 → 카운트다운 → 경기 → 종료)
  client/
    init.client.luau          클라이언트 진입점
    HUD.luau                  점수판, 타이머, 안내 문구, 킥 게이지, 조작 안내
    Controls.luau             입력 처리 (킥 차징, 돌격)
```

밸런스 조정은 `src/shared/Config.luau`의 값만 바꾸면 됩니다. 예: `BALL_DIAMETER`(축구공 크기), `PLAYERS_PER_BALL`(공 1개당 팀 인원), `SHUTTLE_GRAVITY_SCALE`(셔틀콕 낙하 속도), `HEADER_UP_SPEED`(헤딩 높이), `NET_HEIGHT`(네트 높이).

모든 판정(킥 거리, 쿨다운, 명중)은 서버에서 검사하므로 클라이언트 조작으로 능력을 남용할 수 없습니다.
