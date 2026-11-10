-- 아미사커 공용 설정값 (서버/클라이언트 공용)
local Config = {}

-- 게임 모드
-- "Classic": 4:4 축구 + 배드민턴 (킥·헤딩·드리블 + 무기)
-- "War": 전쟁 모드. 5종목 공을 총으로만 다룬다 (킥·헤딩·드리블 없음). 경기장이 더 크고 인원이 많다
Config.GAME_MODE = "War"

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

-- 무기: 누구나 소총·저격총·로켓탄을 쓸 수 있다 (1/2/3 또는 R 로 바꾸고 클릭으로 사격)
-- 사람은 맞지 않고, 축구공·셔틀콕의 궤적만 바뀐다. 드리블 중인 공을 맞히면 소유권이 풀린다
-- Push = 명중한 공에 더해지는 속도
-- Lift = 총알 방향에 더하는 위쪽 성분 (땅에 있는 공을 위에서 쏴도 살짝 뜨게)
Config.Weapons = {
	Rifle = { Name = "소총", Cooldown = 0.25, Range = 150, Push = 12, Lift = 0.2 },
	Sniper = { Name = "저격총", Cooldown = 2, Range = 400, Push = 45, Lift = 0.3 },
	-- 로켓탄은 날아가는 탄이고, 터지면 Radius 안의 공을 바깥쪽으로 밀어낸다 (가까울수록 세게)
	Rocket = { Name = "로켓탄", Cooldown = 4, Range = 200, Push = 60, Speed = 90, Radius = 14 },
}
Config.WEAPON_ORDER = { "Rifle", "Sniper", "Rocket" }
Config.SHUTTLE_PUSH_SCALE = 0.6 -- 셔틀콕은 공보다 덜 밀린다

-- 테스트용 봇: 킥오프 때마다 각 팀을 이 인원까지 봇으로 채운다 (실제 플레이어가 오면 그만큼 빠짐)
Config.BOTS_ENABLED = true
Config.BOT_TEAM_SIZE = 4

-- 돌격 (대시)
Config.DASH_SPEED = 70
Config.DASH_DURATION = 0.2
Config.DASH_COOLDOWN = 3

-- 전쟁 모드 ------------------------------------------------------------------
-- 종목별 공 1개씩. 득점 방식(Goal):
--   "pocket" = 당구처럼 경기장 구멍 6개 중 아무 데나 넣으면, 마지막으로 쏜 선수의 팀 득점
--   "hoop"   = 양쪽 끝 벽 위의 농구 링에 위에서 넣으면 득점 (상대 쪽 링)
--   "net"    = 공중 네트를 넘겨서 상대 진영 바닥에 떨어뜨리면 득점. 네트 밑으로 빠지면 마지막으로 쏜 팀 실점
-- Push = 총에 맞았을 때 밀리는 배율, Up = 맞을 때마다 위로 더 띄우는 정도, Gravity = 중력 배율 (작을수록 천천히 떨어짐)
Config.WAR_BALLS = {
	{ Key = "Soccer", Name = "축구공", Goal = "pocket", Diameter = 4, Color = Color3.fromRGB(255, 255, 255), Gravity = 1, Push = 1, Up = 0.1 },
	{ Key = "Football", Name = "미식축구공", Goal = "pocket", Diameter = 3.5, Stretch = 1.6, Color = Color3.fromRGB(130, 75, 40), Gravity = 1, Push = 1, Up = 0.15 },
	{ Key = "Basketball", Name = "농구공", Goal = "hoop", Diameter = 3.5, Color = Color3.fromRGB(235, 120, 30), Gravity = 0.35, Push = 1, Up = 1 },
	{ Key = "Volleyball", Name = "배구공", Goal = "net", Diameter = 7, Color = Color3.fromRGB(250, 235, 170), Gravity = 0.3, Push = 1.2, Up = 1 },
	{ Key = "Shuttle", Name = "셔틀콕", Goal = "net", Shuttle = true, Gravity = Config.SHUTTLE_GRAVITY_SCALE, Push = 1.2, Up = 1 },
}
Config.WAR_FIELD_LENGTH = 140
Config.WAR_FIELD_WIDTH = 90
Config.WAR_BOT_TEAM_SIZE = 6
Config.WAR_RESPAWN_DELAY = 2 -- 구멍·링에 들어간 공이 다시 나오기까지 (초)
Config.NET_BOTTOM = 8 -- 공중 네트 아랫단 높이 (사람과 축구공은 밑으로 지나감)
Config.POCKET_RADIUS = 5
Config.HOOP_HEIGHT = 16
Config.HOOP_RADIUS = 2.8

Config.IS_WAR = Config.GAME_MODE == "War"
if Config.IS_WAR then
	Config.FIELD_LENGTH = Config.WAR_FIELD_LENGTH
	Config.FIELD_WIDTH = Config.WAR_FIELD_WIDTH
	Config.BOT_TEAM_SIZE = Config.WAR_BOT_TEAM_SIZE
	Config.NET_HEIGHT = 20
end

-- 전쟁 모드 구멍 6개: 네 모서리 + 긴 벽 가운데 (당구대처럼)
Config.POCKETS = {}
do
	local px, pz = Config.FIELD_LENGTH / 2 - 3, Config.FIELD_WIDTH / 2 - 3
	for _, x in { -px, 0, px } do
		for _, z in { -pz, pz } do
			table.insert(Config.POCKETS, Vector3.new(x, 0, z))
		end
	end
end

-- 농구 링 중심: 양쪽 끝 벽 위. 키 = 그 링이 붙은 쪽 (-1 / 1)
Config.HOOPS = {
	[-1] = Vector3.new(-(Config.FIELD_LENGTH / 2 - 4), Config.HOOP_HEIGHT, 0),
	[1] = Vector3.new(Config.FIELD_LENGTH / 2 - 4, Config.HOOP_HEIGHT, 0),
}

-- 팀. Side = 자기 골대(자기 진영)가 있는 X 방향 (-1 이면 x < 0 쪽)
Config.Teams = {
	Alpha = { Name = "알파 분대", Color = BrickColor.new("Earth green"), Side = -1 },
	Bravo = { Name = "브라보 분대", Color = BrickColor.new("Burlap"), Side = 1 },
}
Config.TEAM_ORDER = { "Alpha", "Bravo" }

return Config
