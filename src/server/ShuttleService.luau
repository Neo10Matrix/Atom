-- 거대 배드민턴 셔틀콕(여러 개) + 가운데 반투명 네트
-- * 셔틀콕은 헤딩(머리·상체)으로만 친다.
-- * 같은 팀은 최대 3번까지 헤딩할 수 있고 그 안에 네트를 넘겨야 한다.
--   3번째 헤딩에서 셔틀콕이 빨간색으로 바뀌고, 4번째 터치는 반칙(상대 득점).
-- * 땅에 떨어지면 떨어진 진영의 팀이 실점한다.
-- * 천천히 떨어지도록 중력을 줄이고 수평 속도에 공기 저항을 준다.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local CollisionGroups = require(script.Parent.CollisionGroups)
local PlayerService = require(script.Parent.PlayerService)

local L = Config.FIELD_LENGTH
local W = Config.FIELD_WIDTH
local SD = Config.SHUTTLE_DIAMETER
local MAX_TOUCHES = 3
local SERVE_X = 30 -- 서브 때 네트에서 떨어진 거리
local STUCK_TIME = 1.5 -- 땅이 아닌 곳에 멈춰 있어도 이 시간이 지나면 떨어진 것으로 본다

-- 헤딩 횟수별 색 (3번째 = 빨강)
local TOUCH_COLORS = {
	[0] = Color3.fromRGB(255, 255, 255),
	[1] = Color3.fromRGB(255, 240, 150),
	[2] = Color3.fromRGB(255, 170, 60),
	[3] = Color3.fromRGB(255, 40, 40),
}

export type ShuttleEvent = {
	concedingSide: number, -- 실점한 팀의 진영 쪽 (-1 / 1)
	reason: "ground" | "fault",
	scorer: Player?, -- 마지막으로 헤딩한 선수
}

type Shuttle = {
	cork: Part,
	skirt: Part,
	lane: number, -- 서브 위치의 Z 좌표
	enabled: boolean,
	touchTeam: string?,
	touchCount: number,
	lastHeader: Player?,
	lastHeaderTime: { [Player]: number },
	serveAt: number?,
	serveSide: number,
	stillSince: number?,
}

local ShuttleService = {}

local field: Folder
local shuttles: { Shuttle } = {}
local pending: { ShuttleEvent } = {}

local function sideOf(x: number): number
	return if x < 0 then -1 else 1
end

local function setTouches(s: Shuttle, team: string?, count: number)
	s.touchTeam, s.touchCount = team, count
	local color = TOUCH_COLORS[math.min(count, MAX_TOUCHES)]
	s.cork.Color = color
	s.skirt.Color = color
	s.cork.Material = if count >= MAX_TOUCHES then Enum.Material.Neon else Enum.Material.SmoothPlastic
end

local function buildNet()
	local net = Instance.new("Model")
	net.Name = "BadmintonNet"
	local function piece(name: string, size: Vector3, position: Vector3, color: Color3, transparency: number)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.Size = size
		p.Position = position
		p.Color = color
		p.Transparency = transparency
		p.Material = Enum.Material.SmoothPlastic
		p.CanQuery = false
		p.CollisionGroup = CollisionGroups.Net
		p.Parent = net
	end
	local h = Config.NET_HEIGHT
	piece("Mesh", Vector3.new(0.6, h, W), Vector3.new(0, h / 2, 0), Color3.new(1, 1, 1), 0.65)
	piece("Tape", Vector3.new(0.8, 0.8, W), Vector3.new(0, h, 0), Color3.new(1, 1, 1), 0.1)
	for _, zSign in { -1, 1 } do
		piece("Post", Vector3.new(1, h + 2, 1), Vector3.new(0, (h + 2) / 2, zSign * (W / 2 - 0.5)), Color3.fromRGB(70, 70, 70), 0)
	end
	net.Parent = field
end

local function onTouched(s: Shuttle, hit: BasePart)
	if not s.enabled then
		return
	end
	local model = hit:FindFirstAncestorOfClass("Model")
	local player = model and Players:GetPlayerFromCharacter(model)
	if not model or not player then
		return
	end
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local key = PlayerService.teamKeyOf(player)
	if not root or not key then
		return
	end
	-- 헤딩: 머리나 상체에 맞았을 때만 (발·다리는 그냥 튕김)
	if hit.Name ~= "Head" and hit.Position.Y < root.Position.Y + 0.5 then
		return
	end
	local now = os.clock()
	local last = s.lastHeaderTime[player]
	if last and now - last < Config.HEADER_COOLDOWN then
		return
	end
	s.lastHeaderTime[player] = now

	local count = if s.touchTeam == key then s.touchCount + 1 else 1
	if count > MAX_TOUCHES then
		-- 4번째 터치: 반칙
		s.enabled = false
		table.insert(pending, { concedingSide = Config.Teams[key].Side, reason = "fault", scorer = nil })
		s.serveSide = -Config.Teams[key].Side
		s.serveAt = now + Config.SERVE_DELAY
		return
	end
	setTouches(s, key, count)
	s.lastHeader = player

	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zero
	s.cork.AssemblyLinearVelocity = flat * Config.HEADER_FORWARD_SPEED + Vector3.new(0, Config.HEADER_UP_SPEED, 0)
end

local function makeShuttle(): Shuttle
	local cork = Instance.new("Part")
	cork.Name = "Shuttle"
	cork.Shape = Enum.PartType.Ball
	cork.Size = Vector3.one * SD
	cork.CustomPhysicalProperties = PhysicalProperties.new(0.1, 0.5, 0.3, 1, 1)
	cork.CollisionGroup = CollisionGroups.Shuttle
	cork.Anchored = true

	-- 깃털(치마) 부분: 보이기만 하고 충돌하지 않는다
	local skirt = Instance.new("Part")
	skirt.Name = "Feathers"
	skirt.Shape = Enum.PartType.Cylinder
	skirt.Size = Vector3.new(SD * 1.1, SD * 1.4, SD * 1.4)
	skirt.CFrame = cork.CFrame * CFrame.new(0, SD * 0.75, 0) * CFrame.Angles(0, 0, math.pi / 2)
	skirt.Transparency = 0.15
	skirt.Massless = true
	skirt.CanCollide = false
	skirt.CanQuery = false
	skirt.CanTouch = false
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = cork
	weld.Part1 = skirt
	weld.Parent = skirt
	skirt.Parent = cork

	-- 항상 코르크(공)가 아래를 향하도록 세운다
	local attachment = Instance.new("Attachment")
	attachment.Parent = cork
	local upright = Instance.new("AlignOrientation")
	upright.Mode = Enum.OrientationAlignmentMode.OneAttachment
	upright.Attachment0 = attachment
	upright.CFrame = CFrame.new()
	upright.MaxTorque = 1e7
	upright.Responsiveness = 40
	upright.Parent = cork

	-- 중력 일부를 상쇄해서 천천히 떨어지게 한다
	local lift = Instance.new("VectorForce")
	lift.Attachment0 = attachment
	lift.RelativeTo = Enum.ActuatorRelativeTo.World
	lift.ApplyAtCenterOfMass = true
	lift.Parent = cork

	cork.Parent = field
	lift.Force = Vector3.new(0, cork.AssemblyMass * workspace.Gravity * (1 - Config.SHUTTLE_GRAVITY_SCALE), 0)

	local s: Shuttle = {
		cork = cork,
		skirt = skirt,
		lane = 0,
		enabled = false,
		touchTeam = nil,
		touchCount = 0,
		lastHeader = nil,
		lastHeaderTime = {},
		serveAt = nil,
		serveSide = if math.random() < 0.5 then -1 else 1,
		stillSince = nil,
	}
	cork.Touched:Connect(function(hit)
		onTouched(s, hit)
	end)
	setTouches(s, nil, 0)
	return s
end

local function placeForServe(s: Shuttle)
	s.cork.Anchored = true
	s.cork.CFrame = CFrame.new(s.serveSide * SERVE_X, Config.SERVE_HEIGHT, s.lane)
	s.cork.AssemblyLinearVelocity = Vector3.zero
	s.cork.AssemblyAngularVelocity = Vector3.zero
	setTouches(s, nil, 0)
	s.lastHeader = nil
	s.stillSince = nil
end

local function serve(s: Shuttle)
	placeForServe(s)
	s.serveAt = nil
	s.cork.Anchored = false
	s.cork:SetNetworkOwner(nil)
	s.enabled = true
end

local function landed(s: Shuttle, concedingSide: number, now: number)
	s.enabled = false
	table.insert(pending, { concedingSide = concedingSide, reason = "ground", scorer = s.lastHeader })
	-- 득점한 팀 쪽에서 다음 서브
	s.serveSide = -concedingSide
	s.serveAt = now + Config.SERVE_DELAY
end

function ShuttleService.init(fieldFolder: Folder)
	field = fieldFolder
	buildNet()
	Players.PlayerRemoving:Connect(function(player)
		for _, s in shuttles do
			s.lastHeaderTime[player] = nil
		end
	end)
end

-- 킥오프 준비: 셔틀콕을 count 개로 맞추고 서브 위치에 고정
function ShuttleService.reset(count: number)
	pending = {}
	while #shuttles < count do
		table.insert(shuttles, makeShuttle())
	end
	while #shuttles > count do
		local s = table.remove(shuttles) :: Shuttle
		s.cork:Destroy()
	end
	for i, s in shuttles do
		s.enabled = false
		s.serveAt = nil
		s.lane = (i - (count + 1) / 2) * (W / (count + 1))
		placeForServe(s)
	end
end

function ShuttleService.release()
	for _, s in shuttles do
		serve(s)
	end
end

-- 매 프레임 호출: 공기 저항, 네트 넘김, 착지 판정, 다음 서브. 발생한 득점 이벤트를 돌려준다
function ShuttleService.step(dt: number): { ShuttleEvent }
	local now = os.clock()
	for _, s in shuttles do
		if s.serveAt then
			if now >= s.serveAt then
				serve(s)
			end
		elseif s.enabled then
			local p = s.cork.Position
			local v = s.cork.AssemblyLinearVelocity
			local damping = math.max(0, 1 - Config.SHUTTLE_DRAG * dt)
			s.cork.AssemblyLinearVelocity = Vector3.new(v.X * damping, v.Y, v.Z * damping)

			-- 상대 진영으로 넘어가면 헤딩 횟수 초기화
			if s.touchTeam and sideOf(p.X) == -Config.Teams[s.touchTeam].Side then
				setTouches(s, nil, 0)
			end

			if v.Magnitude < 0.5 then
				s.stillSince = s.stillSince or now
			else
				s.stillSince = nil
			end

			if math.abs(p.X) > L / 2 + 5 or math.abs(p.Z) > W / 2 + 5 or p.Y > Config.WALL_HEIGHT + 5 or p.Y < -20 then
				-- 경기장 밖: 점수 없이 다시 서브
				s.enabled = false
				s.serveAt = now + Config.SERVE_DELAY
			elseif p.Y <= SD / 2 + 0.6 or (s.stillSince and now - s.stillSince > STUCK_TIME) then
				landed(s, sideOf(p.X), now)
			end
		end
	end

	local events = pending
	pending = {}
	return events
end

return ShuttleService
