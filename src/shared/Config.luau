-- 아미사커 공용 설정값 (서버/클라이언트 공용)
local Config = {}

-- 네트워크 / 상태 폴더 이름 (ReplicatedStorage 아래에 서버가 생성)
Config.NET_FOLDER = "ArmySoccerNet"

-- 경기 흐름
Config.MIN_PLAYERS = 2 -- Studio에서는 1명으로도 시작
Config.MATCH_DURATION = 300 -- 초
Config.COUNTDOWN = 3
Config.GOAL_CELEBRATION = 4
Config.END_SCREEN = 8

-- 경기장 (길이 방향 = X축)
Config.FIELD_LENGTH = 220
Config.FIELD_WIDTH = 140
Config.WALL_HEIGHT = 110 -- 투명 벽/천장 높이
Config.GOAL_WIDTH = 48 -- 거대 축구공이 들어가도록 크게
Config.GOAL_HEIGHT = 20
Config.GOAL_DEPTH = 14
Config.PENALTY_BOX_DEPTH = 30 -- 페널티 박스 라인 (표시용)
Config.PENALTY_BOX_WIDTH = 80

-- 이동
Config.WALK_SPEED = 20

-- 공 개수: 팀당 이 인원마다 축구공 1개 + 셔틀콕 1개 (최소 1개씩). 킥오프마다 다시 계산
-- 예) 4:4 → 각 1개, 8:8 → 각 2개
Config.PLAYERS_PER_BALL = 4

-- 거대 축구공 (발로만)
Config.BALL_DIAMETER = 12
Config.KICK_RANGE = 13 -- 캐릭터 중심 ~ 공 중심 거리
Config.KICK_COOLDOWN = 0.35
Config.KICK_MIN_SPEED = 35
Config.KICK_MAX_SPEED = 110
Config.KICK_MIN_LIFT = 0.1 -- 방향 벡터의 수직 성분
Config.KICK_MAX_LIFT = 0.5
Config.MAX_CHARGE_TIME = 1

-- 거대 셔틀콕 (배드민턴, 헤딩으로만)
Config.SHUTTLE_DIAMETER = 8
Config.SHUTTLE_GRAVITY_SCALE = 0.3 -- 보통 공보다 천천히 떨어짐
Config.SHUTTLE_DRAG = 0.6 -- 수평 속도 감속 (초당 비율)
Config.SERVE_HEIGHT = 40 -- 서브 때 셔틀콕이 떨어지기 시작하는 높이
Config.SERVE_DELAY = 2 -- 득점 후 다음 서브까지 (초)
Config.HEADER_UP_SPEED = 60
Config.HEADER_FORWARD_SPEED = 45
Config.HEADER_COOLDOWN = 0.3
Config.NET_HEIGHT = 16 -- 가운데 반투명 네트 높이

-- 돌격 (대시)
Config.DASH_SPEED = 70
Config.DASH_DURATION = 0.2
Config.DASH_COOLDOWN = 3

-- 팀. Side = 자기 골대(자기 진영)가 있는 X 방향 (-1 이면 x < 0 쪽)
Config.Teams = {
	Alpha = { Name = "알파 분대", Color = BrickColor.new("Earth green"), Side = -1 },
	Bravo = { Name = "브라보 분대", Color = BrickColor.new("Burlap"), Side = 1 },
}
Config.TEAM_ORDER = { "Alpha", "Bravo" }

return Config
