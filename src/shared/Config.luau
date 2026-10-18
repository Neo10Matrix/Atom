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
Config.WALL_HEIGHT = 110 -- 투명 벽/천장 높이 (전차 포물선이 넘지 않도록 높게)
Config.GOAL_WIDTH = 32
Config.GOAL_HEIGHT = 12
Config.GOAL_DEPTH = 8

-- 공
Config.BALL_DIAMETER = 4
Config.BONUS_BALL_LIFETIME = 20 -- 전차 포탄으로 생긴 공이 사라지기까지 (초)
Config.MAX_BONUS_BALLS = 9

-- 킥 (모든 병과 공통)
Config.KICK_RANGE = 7
Config.KICK_COOLDOWN = 0.35
Config.KICK_MIN_SPEED = 35
Config.KICK_MAX_SPEED = 110
Config.KICK_MIN_LIFT = 0.1 -- 방향 벡터의 수직 성분
Config.KICK_MAX_LIFT = 0.5
Config.MAX_CHARGE_TIME = 1

-- 돌격 (대시, 모든 병과 공통)
Config.DASH_SPEED = 70
Config.DASH_DURATION = 0.2
Config.DASH_COOLDOWN = 3

-- 소총수: 날아가는 공을 쏴서 궤적을 미세하게 바꾼다
Config.RIFLE_RANGE = 250
Config.RIFLE_NUDGE = 10 -- 명중 시 공에 더해지는 속도 (studs/s)
Config.RIFLE_HIT_TOLERANCE = 2 -- 지연 보정용 판정 여유 (studs)

-- 전차병: 포탄 한 발에 공 여러 개가 포물선을 그리며 날아간다
Config.TANK_BALLS = 3
Config.TANK_RANGE = 180
Config.TANK_SPREAD = 14 -- 착탄 지점 흩어짐 반경
Config.TANK_MIN_FLIGHT = 0.9 -- 비행 시간 (초). 길수록 포물선이 높아짐 (최고점 ≈ 중력 × 시간² / 8)
Config.TANK_MAX_FLIGHT = 1.9
Config.TANK_FLIGHT_PER_STUD = 1 / 90
Config.MAX_TANKS_PER_TEAM = 1

Config.Classes = {
	Rifleman = {
		Name = "소총수",
		WalkSpeed = 20,
		Cooldown = 0.6,
		Description = "클릭: 사격 — 맞은 공의 궤적을 살짝 바꿈",
	},
	Tank = {
		Name = "전차병",
		WalkSpeed = 16,
		Cooldown = 8,
		Description = "클릭: 포격 — 공 여러 개를 포물선으로 발사",
	},
}
Config.CLASS_ORDER = { "Rifleman", "Tank" }
Config.DEFAULT_CLASS = "Rifleman"

-- 팀. Side = 자기 골대가 있는 X 방향 (-1 이면 x < 0 쪽 골대를 지킴)
Config.Teams = {
	Alpha = { Name = "알파 분대", Color = BrickColor.new("Earth green"), Side = -1 },
	Bravo = { Name = "브라보 분대", Color = BrickColor.new("Burlap"), Side = 1 },
}
Config.TEAM_ORDER = { "Alpha", "Bravo" }

return Config
