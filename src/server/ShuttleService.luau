-- 거대 배드민턴 셔틀콕 + 가운데 반투명 네트
-- * 배드민턴 선수만 건드릴 수 있고, 헤딩(머리·상체)으로만 친다.
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
	scorer: Player?, -- 득점한 팀에서 마지막으로 헤딩한 선수
}

local ShuttleService = {}

local cork: Part
local skirt: Part
local enabled = false
local touchTeam: string? = nil
local touchCount = 0
local lastHeader: Player? = nil
local lastHeaderTime: { [Player]: number } = {}
local pending: { ShuttleEvent } = {}
local serveAt: number? = nil
local serveSide = 1
local stillSince: number? = nil

local function sideOf(x: number): number
	return if x < 0 then -1 else 1
end

local function setTouches(team: string?, count: number)
	touchTeam, touchCount = team, count
	local color = TOUCH_COLORS[math.min(count, MAX_TOUCHES)]
	cork.Color = color
	skirt.Color = color
	cork.Material = if count >= MAX_TOUCHES then Enum.Material.Neon else Enum.Material.SmoothPlastic
end

local function buildNet(field: Folder)
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

local function onTouched(hit: BasePart)
	if not enabled then
		return
	end
	local model = hit:FindFirstAncestorOfClass("Model")
	local player = model and Players:GetPlayerFromCharacter(model)
	if not player or PlayerService.sportOf(player) ~= "Badminton" then
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
	if lastHeaderTime[player] and now - lastHeaderTime[player] < Config.HEADER_COOLDOWN then
		return
	end
	lastHeaderTime[player] = now

	local count = if touchTeam == key then touchCount + 1 else 1
	if count > MAX_TOUCHES then
		-- 4번째 터치: 반칙
		enabled = false
		table.insert(pending, {
			concedingSide = Config.Teams[key].Side,
			reason = "fault",
			scorer = nil,
		})
		return
	end
	setTouches(key, count)
	lastHeader = player

	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zero
	cork.AssemblyLinearVelocity = flat * Config.HEADER_FORWARD_SPEED + Vector3.new(0, Config.HEADER_UP_SPEED, 0)
end

local function makeShuttle(field: Folder)
	cork = Instance.new("Part")
	cork.Name = "Shuttle"
	cork.Shape = Enum.PartType.Ball
	cork.Size = Vector3.one * SD
	cork.CustomPhysicalProperties = PhysicalProperties.new(0.1, 0.5, 0.3, 1, 1)
	cork.CollisionGroup = CollisionGroups.Shuttle
	cork.Anchored = true
	cork.Position = Vector3.new(SERVE_X, Config.SERVE_HEIGHT, 0)

	-- 깃털(치마) 부분: 보이기만 하고 충돌하지 않는다
	skirt = Instance.new("Part")
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

	cork.Touched:Connect(onTouched)
	cork.Parent = field
	lift.Force = Vector3.new(0, cork.AssemblyMass * workspace.Gravity * (1 - Config.SHUTTLE_GRAVITY_SCALE), 0)
	setTouches(nil, 0)
end

local function placeForServe(side: number)
	cork.Anchored = true
	cork.CFrame = CFrame.new(side * SERVE_X, Config.SERVE_HEIGHT, 0)
	cork.AssemblyLinearVelocity = Vector3.zero
	cork.AssemblyAngularVelocity = Vector3.zero
	setTouches(nil, 0)
	lastHeader = nil
	stillSince = nil
end

local function serve()
	serveAt = nil
	cork.Anchored = false
	cork:SetNetworkOwner(nil)
	enabled = true
end

local function landed(concedingSide: number)
	enabled = false
	table.insert(pending, {
		concedingSide = concedingSide,
		reason = "ground",
		scorer = lastHeader,
	})
end

function ShuttleService.init(field: Folder)
	buildNet(field)
	makeShuttle(field)
	Players.PlayerRemoving:Connect(function(player)
		lastHeaderTime[player] = nil
	end)
end

-- 킥오프 준비: 셔틀콕을 서브 위치에 고정
function ShuttleService.reset()
	enabled = false
	serveAt = nil
	pending = {}
	placeForServe(serveSide)
end

function ShuttleService.release()
	serve()
end

-- 매 프레임 호출: 공기 저항, 네트 넘김, 착지/반칙 판정, 다음 서브. 발생한 득점 이벤트를 돌려준다
function ShuttleService.step(dt: number): { ShuttleEvent }
	local now = os.clock()

	if serveAt then
		if now >= serveAt then
			serve()
		end
	elseif enabled then
		local p = cork.Position
		local v = cork.AssemblyLinearVelocity
		local damping = math.max(0, 1 - Config.SHUTTLE_DRAG * dt)
		cork.AssemblyLinearVelocity = Vector3.new(v.X * damping, v.Y, v.Z * damping)

		-- 상대 진영으로 넘어가면 헤딩 횟수 초기화
		if touchTeam and sideOf(p.X) == -Config.Teams[touchTeam].Side then
			setTouches(nil, 0)
		end

		if v.Magnitude < 0.5 then
			stillSince = stillSince or now
		else
			stillSince = nil
		end

		if math.abs(p.X) > L / 2 + 5 or math.abs(p.Z) > W / 2 + 5 or p.Y > Config.WALL_HEIGHT + 5 or p.Y < -20 then
			-- 경기장 밖: 점수 없이 같은 쪽에서 다시 서브
			placeForServe(sideOf(p.X))
			serveAt = now + Config.SERVE_DELAY
		elseif p.Y <= SD / 2 + 0.6 or (stillSince and now - stillSince > STUCK_TIME) then
			landed(sideOf(p.X))
		end
	end

	-- 득점이 나면 득점한 팀 쪽에서 다음 서브
	local events = pending
	pending = {}
	for _, event in events do
		serveSide = -event.concedingSide
		placeForServe(serveSide)
		serveAt = now + Config.SERVE_DELAY
	end
	return events
end

return ShuttleService
