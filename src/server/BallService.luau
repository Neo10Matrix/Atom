-- 공 관리: 메인 공 + 전차 포탄 보너스 공 + 골키퍼 스페셜 슛 공
-- 킥/사격/포격/스페셜 슛 처리와 골 판정
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PlayerService = require(script.Parent.PlayerService)
local ZoneService = require(script.Parent.ZoneService)

local L = Config.FIELD_LENGTH
local W = Config.FIELD_WIDTH
local D = Config.BALL_DIAMETER
local CENTER = Vector3.new(0, D / 2 + 0.5, 0)
-- 클라이언트/서버 시간 차이로 정상 입력이 거부되지 않도록 쿨다운을 조금 느슨하게 검사
local COOLDOWN_LENIENCY = 0.9
-- 소총 지연 보정: 클라이언트가 본 공 위치는 과거이므로 최대 이만큼 되감아서도 판정
local MAX_REWIND = 0.4

export type BallKind = "main" | "bonus" | "special"

export type BallEvent = {
	kind: "goal" | "out",
	isMain: boolean,
	ballKind: BallKind,
	side: number?, -- 공이 들어간 골대 쪽 (-1 / 1)
	scorer: Player?,
}

local BallService = {}

local ballsFolder: Folder
local mainBall: Part
local bonusExpiry: { [Part]: number } = {}
local lastToucher: { [Part]: Player } = {}
local lastAction: { [Player]: { [string]: number } } = {}
local ballKind: { [Part]: BallKind } = {}
local charging: { [Player]: boolean } = {}
local enabled = false
local round = 0 -- 킥오프마다 증가: 충전 중이던 스페셜 슛 취소용
local announceEvent: RemoteEvent

local BALL_STYLE: { [BallKind]: { name: string, color: Color3, material: Enum.Material } } = {
	main = { name = "Ball", color = Color3.new(1, 1, 1), material = Enum.Material.SmoothPlastic },
	bonus = { name = "BonusBall", color = Color3.fromRGB(255, 170, 60), material = Enum.Material.SmoothPlastic },
	special = { name = "SpecialBall", color = Color3.fromRGB(255, 60, 60), material = Enum.Material.Neon },
}

local function makeBall(kind: BallKind): Part
	local style = BALL_STYLE[kind]
	local ball = Instance.new("Part")
	ball.Name = style.name
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * D
	ball.Material = style.material
	ball.Color = style.color
	ball.CustomPhysicalProperties = PhysicalProperties.new(0.3, 0.4, 0.6, 1, 1)
	if kind == "special" then
		ball.CollisionGroup = ZoneService.Groups.SpecialBall
	end
	ballKind[ball] = kind

	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, D * 0.3, 0)
	a0.Parent = ball
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -D * 0.3, 0)
	a1.Parent = ball
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = if kind == "special" then 0.6 else 0.25
	trail.Color = ColorSequence.new(ball.Color)
	trail.Transparency = NumberSequence.new(0.4, 1)
	trail.Parent = ball

	ball.Touched:Connect(function(hit)
		if kind == "special" then
			return -- 스페셜 슛은 선수 몸에 영향을 받지 않으므로 득점자도 바뀌지 않는다
		end
		local model = hit:FindFirstAncestorOfClass("Model")
		local player = model and Players:GetPlayerFromCharacter(model)
		if player then
			lastToucher[ball] = player
		end
	end)
	ball.Parent = ballsFolder
	return ball
end

-- Destroying 신호는 지연 실행될 수 있으므로 추적 테이블은 여기서 바로 정리한다
local function destroyBall(ball: Part)
	lastToucher[ball] = nil
	bonusExpiry[ball] = nil
	ballKind[ball] = nil
	ball:Destroy()
end

local function tryUse(player: Player, action: string, cooldown: number): boolean
	local now = os.clock()
	local times = lastAction[player]
	if not times then
		times = {}
		lastAction[player] = times
	end
	local last = times[action]
	if last and now - last < cooldown * COOLDOWN_LENIENCY then
		return false
	end
	times[action] = now
	return true
end

local function aliveRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return root
end

local function flatLook(root: BasePart): Vector3?
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		return nil
	end
	return flat.Unit
end

local function isFiniteVector(v: unknown): boolean
	if typeof(v) ~= "Vector3" then
		return false
	end
	local vec = v :: Vector3
	for _, n in { vec.X, vec.Y, vec.Z } do
		if n ~= n or math.abs(n) == math.huge then
			return false
		end
	end
	return true
end

-- 킥: 가장 가까운 공을 캐릭터가 바라보는 방향으로 찬다
local function onKick(player: Player, power: unknown)
	if not enabled or typeof(power) ~= "number" or power ~= power then
		return
	end
	local root = aliveRoot(player)
	local direction = root and flatLook(root)
	if not root or not direction then
		return
	end

	local target: Part? = nil
	local bestDistance = Config.KICK_RANGE
	for _, child in ballsFolder:GetChildren() do
		local ball = child :: Part
		local distance = (ball.Position - root.Position).Magnitude
		if distance <= bestDistance and not ball.Anchored and ballKind[ball] ~= "special" then
			target, bestDistance = ball, distance
		end
	end
	if not target or not tryUse(player, "Kick", Config.KICK_COOLDOWN) then
		return
	end

	local alpha = math.clamp(power :: number, 0, 1)
	local speed = Config.KICK_MIN_SPEED + (Config.KICK_MAX_SPEED - Config.KICK_MIN_SPEED) * alpha
	local lift = Config.KICK_MIN_LIFT + (Config.KICK_MAX_LIFT - Config.KICK_MIN_LIFT) * alpha
	target.AssemblyLinearVelocity = (direction + Vector3.new(0, lift, 0)).Unit * speed
	lastToucher[target] = player
	ZoneService.onKick(player, direction)
end

local function tracer(from: Vector3, to: Vector3)
	local length = (to - from).Magnitude
	if length < 0.1 then
		return
	end
	local beam = Instance.new("Part")
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.Material = Enum.Material.Neon
	beam.Color = Color3.fromRGB(255, 220, 120)
	beam.Size = Vector3.new(0.15, 0.15, length)
	beam.CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -length / 2)
	beam.Parent = workspace
	Debris:AddItem(beam, 0.08)
end

-- 소총수: 조준선과 가장 가까운 공을 맞히면 그 방향으로 살짝 밀어 궤적을 바꾼다
local function rifleShot(player: Player, root: BasePart, target: Vector3)
	local head = player.Character and player.Character:FindFirstChild("Head") :: BasePart?
	local origin = if head then head.Position else root.Position + Vector3.new(0, 1.5, 0)
	local offset = target - origin
	if offset.Magnitude < 1e-3 then
		return
	end
	local direction = offset.Unit

	-- 현재 위치와, 플레이어 지연만큼 되감은 위치 둘 다 판정 (빠른 공도 맞힐 수 있도록)
	local rewind = math.clamp(player:GetNetworkPing() * 2, 0, MAX_REWIND)
	local hitBall: Part? = nil
	local hitDistance = Config.RIFLE_RANGE
	for _, child in ballsFolder:GetChildren() do
		local ball = child :: Part
		if not ball.Anchored then
			for _, position in { ball.Position, ball.Position - ball.AssemblyLinearVelocity * rewind } do
				local toBall = position - origin
				local along = toBall:Dot(direction)
				if along > 0 and along < hitDistance then
					local miss = (toBall - direction * along).Magnitude
					if miss <= D / 2 + Config.RIFLE_HIT_TOLERANCE then
						hitBall, hitDistance = ball, along
					end
				end
			end
		end
	end

	tracer(origin, origin + direction * math.min(hitDistance, offset.Magnitude, Config.RIFLE_RANGE))
	if hitBall then
		hitBall.AssemblyLinearVelocity += direction * Config.RIFLE_NUDGE
		lastToucher[hitBall] = player
	end
end

-- 보너스 공이 최대 개수에 도달했으면 가장 오래된 것부터 제거
local function makeRoomForBonus()
	while #ballsFolder:GetChildren() - 1 >= Config.MAX_BONUS_BALLS do
		local oldest: Part? = nil
		for ball, expiry in bonusExpiry do
			if not oldest or expiry < bonusExpiry[oldest] then
				oldest = ball
			end
		end
		if not oldest then
			return
		end
		destroyBall(oldest)
	end
end

local function blastEffect(position: Vector3, radius: number)
	local blast = Instance.new("Explosion")
	blast.Position = position
	blast.BlastRadius = radius
	blast.BlastPressure = 0
	blast.DestroyJointRadiusPercent = 0
	blast.Parent = workspace
end

-- start 에서 출발해 flight 초 뒤 landing 에 도착하는 포물선 초기 속도
-- (start + v·t - ½g·t² = landing)
local function launchVelocity(start: Vector3, landing: Vector3, flight: number): Vector3
	return (landing - start) / flight + Vector3.new(0, 0.5 * workspace.Gravity * flight, 0)
end

-- 전차병: 포탄 한 발 → 보너스 공 여러 개가 조준 지점 주변으로 포물선을 그리며 떨어진다
local function tankShot(player: Player, root: BasePart, target: Vector3)
	local forward = flatLook(root)
	if not forward then
		return
	end
	local origin = root.Position + forward * 3 + Vector3.new(0, 5, 0)

	local horizontal = Vector3.new(target.X - root.Position.X, 0, target.Z - root.Position.Z)
	if horizontal.Magnitude > Config.TANK_RANGE then
		horizontal = horizontal.Unit * Config.TANK_RANGE
	end
	local aimPoint = Vector3.new(root.Position.X, D / 2, root.Position.Z) + horizontal

	blastEffect(origin, 4)

	local right = forward:Cross(Vector3.yAxis)
	for i = 1, Config.TANK_BALLS do
		makeRoomForBonus()

		local angle = math.random() * math.pi * 2
		local radius = math.sqrt(math.random()) * Config.TANK_SPREAD
		local landing = aimPoint + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		local start = origin + right * ((i - (Config.TANK_BALLS + 1) / 2) * (D + 0.5))

		local distance = Vector3.new(landing.X - start.X, 0, landing.Z - start.Z).Magnitude
		local flight =
			math.clamp(distance * Config.TANK_FLIGHT_PER_STUD, Config.TANK_MIN_FLIGHT, Config.TANK_MAX_FLIGHT)

		local ball = makeBall("bonus")
		ball.Position = start
		ball:SetNetworkOwner(nil)
		ball.AssemblyLinearVelocity = launchVelocity(start, landing, flight)
		bonusExpiry[ball] = os.clock() + Config.BONUS_BALL_LIFETIME
		lastToucher[ball] = player
	end
end

-- 골키퍼: 오래 충전(이동 불가)한 뒤 상대 골문으로 스페셜 슛.
-- 스페셜 공은 모든 선수를 통과하므로 상대 소총수 사격이나 전차 포탄 공으로만 막을 수 있다.
local function specialShot(player: Player)
	local key = PlayerService.teamKeyOf(player)
	local character = player.Character
	if charging[player] or not key or not character then
		return
	end
	local team = Config.Teams[key]
	local chargeRound = round
	charging[player] = true
	PlayerService.setRooted(player, true)

	local glow = Instance.new("Highlight")
	glow.FillColor = team.Color.Color
	glow.OutlineColor = Color3.new(1, 1, 1)
	glow.FillTransparency = 0.3
	glow.Parent = character
	announceEvent:FireAllClients(
		string.format("%s 골키퍼 스페셜 슛 충전 중! 소총수·전차병 대비!", team.Name),
		Config.SPECIAL_CHARGE_TIME
	)

	task.wait(Config.SPECIAL_CHARGE_TIME)

	glow:Destroy()
	charging[player] = nil
	PlayerService.setRooted(player, false)
	local root = aliveRoot(player)
	if chargeRound ~= round or not enabled or not root or PlayerService.classOf(player) ~= "Goalkeeper" then
		return
	end

	-- 상대 골대 쪽 = -side. 골문 안쪽 낮은 곳을 노린다
	local start = root.Position + Vector3.new(-team.Side * 4, 3, 0)
	local landing = Vector3.new(
		-team.Side * (L / 2 + Config.GOAL_DEPTH / 2),
		Config.GOAL_HEIGHT / 3,
		(math.random() * 2 - 1) * (Config.GOAL_WIDTH / 2 - 4)
	)
	makeRoomForBonus()
	blastEffect(start, 6)
	local ball = makeBall("special")
	ball.Position = start
	ball:SetNetworkOwner(nil)
	ball.AssemblyLinearVelocity = launchVelocity(start, landing, Config.SPECIAL_FLIGHT_TIME)
	bonusExpiry[ball] = os.clock() + Config.SPECIAL_LIFETIME
	lastToucher[ball] = player
end

local function onAbility(player: Player, target: unknown)
	if not enabled or not isFiniteVector(target) then
		return
	end
	local root = aliveRoot(player)
	if not root then
		return
	end
	local class = PlayerService.classOf(player)
	if not tryUse(player, "Ability", Config.Classes[class].Cooldown) then
		return
	end
	if class == "Tank" then
		tankShot(player, root, target :: Vector3)
	elseif class == "Goalkeeper" then
		task.spawn(specialShot, player)
	else
		rifleShot(player, root, target :: Vector3)
	end
end

function BallService.init(field: Folder, net: Folder)
	ballsFolder = field:WaitForChild("Balls") :: Folder
	announceEvent = net:WaitForChild("Announce") :: RemoteEvent
	mainBall = makeBall("main")
	BallService.reset()

	local kick = net:WaitForChild("Kick") :: RemoteEvent
	kick.OnServerEvent:Connect(onKick)
	local ability = net:WaitForChild("Ability") :: RemoteEvent
	ability.OnServerEvent:Connect(onAbility)
	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
	end)
end

local function placeMainAtCenter()
	mainBall.CFrame = CFrame.new(CENTER)
	mainBall.AssemblyLinearVelocity = Vector3.zero
	mainBall.AssemblyAngularVelocity = Vector3.zero
	lastToucher[mainBall] = nil
end

-- 킥오프 준비: 보너스/스페셜 공 제거, 메인 공을 중앙에 고정, 조작 비활성화
function BallService.reset()
	enabled = false
	round += 1
	for ball in bonusExpiry do
		destroyBall(ball)
	end
	mainBall.Anchored = true
	placeMainAtCenter()
end

function BallService.release()
	mainBall.Anchored = false
	mainBall:SetNetworkOwner(nil)
	enabled = true
end

function BallService.lock()
	enabled = false
end

-- 매 프레임 호출: 골/아웃/수명 만료를 처리하고 발생한 이벤트 목록을 돌려준다
function BallService.step(): { BallEvent }
	local events: { BallEvent } = {}
	local now = os.clock()
	for _, child in ballsFolder:GetChildren() do
		local ball = child :: Part
		local isMain = ball == mainBall
		local p = ball.Position
		if math.abs(p.Z) < Config.GOAL_WIDTH / 2 and p.Y < Config.GOAL_HEIGHT and math.abs(p.X) > L / 2 + D / 2 then
			table.insert(events, {
				kind = "goal",
				isMain = isMain,
				ballKind = ballKind[ball],
				side = if p.X < 0 then -1 else 1,
				scorer = lastToucher[ball],
			})
			if isMain then
				enabled = false
			else
				destroyBall(ball)
			end
		elseif
			p.Y < -20
			or p.Y > Config.WALL_HEIGHT + 20
			or math.abs(p.X) > L / 2 + Config.GOAL_DEPTH + 10
			or math.abs(p.Z) > W / 2 + 10
		then
			if isMain then
				placeMainAtCenter()
				table.insert(events, { kind = "out", isMain = true, ballKind = "main" })
			else
				destroyBall(ball)
			end
		elseif bonusExpiry[ball] and now > bonusExpiry[ball] then
			destroyBall(ball)
		end
	end
	return events
end

return BallService
