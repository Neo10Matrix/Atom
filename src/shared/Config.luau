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

-- 경기장 (길이 방향 = X축). 플러그인(Generate Arena) 경기장처럼 4:4 에 맞는 촘촘한 크기
Config.FIELD_LENGTH = 100
Config.FIELD_WIDTH = 70
Config.WALL_HEIGHT = 110 -- 투명 벽/천장 높이 (셔틀콕이 밖으로 못 나가도록 높게)
Config.GLASS_WALL_HEIGHT = 10 -- 눈에 보이는 유리벽 높이
Config.GOAL_WIDTH = 20
Config.GOAL_HEIGHT = 10
Config.GOAL_DEPTH = 6
Config.PENALTY_BOX_DEPTH = 16 -- 페널티 박스 라인 (표시용)
Config.PENALTY_BOX_WIDTH = 40
Config.STAND_ROWS = 3 -- 양쪽 관중석 줄 수

-- 이동
Config.WALK_SPEED = 20

-- 공 개수: 팀당 이 인원마다 축구공 1개 + 셔틀콕 1개 (최소 1개씩). 킥오프마다 다시 계산
-- 예) 4:4 → 각 1개, 8:8 → 각 2개
Config.PLAYERS_PER_BALL = 4

-- 한 사람은 공 두 개를 동시에 다룰 수 없다:
-- 축구공 드리블 중에도 헤딩은 되지만, 헤딩하면 축구공을 놓치고 이 시간 동안 다시 못 잡는다
Config.CONTROL_LOCK_TIME = 1.5

-- 자석 드리블: 축구공에 닿으면 공이 발 앞에 붙어서 따라온다
Config.DRIBBLE_OFFSET = 3.5 -- 캐릭터 중심에서 공까지 앞쪽 거리
Config.DRIBBLE_GAIN = 10 -- 공이 목표 위치로 끌려가는 세기
Config.DRIBBLE_BREAK = 10 -- 이보다 멀어지면 소유권을 잃음
Config.STEAL_PROTECT = 0.5 -- 공을 잡은 직후 이 시간 동안은 뺏기지 않음 (초)
Config.STEAL_RANGE = 4 -- 드리블 중인 공에 상대가 이만큼 가까이 오면 뺏음
Config.HEADER_DROP_SPEED = 25 -- 헤딩할 때 놓친 축구공이 굴러가는 속도

-- 축구공 (일반 크기, 발로만)
Config.BALL_DIAMETER = 4
Config.KICK_RANGE = 10 -- 캐릭터 중심 ~ 공 중심 거리
Config.KICK_COOLDOWN = 0.35
Config.KICK_MIN_SPEED = 35
Config.KICK_MAX_SPEED = 80
Config.KICK_MIN_LIFT = 0.1 -- 방향 벡터의 수직 성분
Config.KICK_MAX_LIFT = 0.5
Config.MAX_CHARGE_TIME = 1

-- 거대 셔틀콕 (배드민턴, 헤딩으로만)
Config.SHUTTLE_DIAMETER = 14 -- 거대 셔틀콕 (코르크 부분 지름)
Config.SHUTTLE_GRAVITY_SCALE = 0.3 -- 보통 공보다 천천히 떨어짐
Config.SHUTTLE_DRAG = 0.6 -- 수평 속도 감속 (초당 비율)
Config.SERVE_HEIGHT = 40 -- 서브 때 셔틀콕이 떨어지기 시작하는 높이
Config.SERVE_DELAY = 2 -- 득점 후 다음 서브까지 (초)
Config.HEADER_UP_SPEED = 60
Config.HEADER_FORWARD_SPEED = 28
Config.HEADER_COOLDOWN = 0.3
Config.NET_HEIGHT = 18 -- 가운데 반투명 네트 높이

-- 테스트용 봇: 킥오프 때마다 각 팀을 이 인원까지 봇으로 채운다 (실제 플레이어가 오면 그만큼 빠짐)
Config.BOTS_ENABLED = true
Config.BOT_TEAM_SIZE = 4

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
