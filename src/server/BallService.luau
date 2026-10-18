-- 공 관리: 메인 공 + 전차 포탄으로 생기는 보너스 공, 킥/사격/포격 처리, 골 판정
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PlayerService = require(script.Parent.PlayerService)

local L = Config.FIELD_LENGTH
local W = Config.FIELD_WIDTH
local D = Config.BALL_DIAMETER
local CENTER = Vector3.new(0, D / 2 + 0.5, 0)
-- 클라이언트/서버 시간 차이로 정상 입력이 거부되지 않도록 쿨다운을 조금 느슨하게 검사
local COOLDOWN_LENIENCY = 0.9

export type BallEvent = {
	kind: "goal" | "out",
	isMain: boolean,
	side: number?, -- 공이 들어간 골대 쪽 (-1 / 1)
	scorer: Player?,
}

local BallService = {}

local ballsFolder: Folder
local mainBall: Part
local bonusExpiry: { [Part]: number } = {}
local lastToucher: { [Part]: Player } = {}
local lastAction: { [Player]: { [string]: number } } = {}
local enabled = false

local function makeBall(isBonus: boolean): Part
	local ball = Instance.new("Part")
	ball.Name = if isBonus then "BonusBall" else "Ball"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * D
	ball.Material = Enum.Material.SmoothPlastic
	ball.Color = if isBonus then Color3.fromRGB(255, 170, 60) else Color3.new(1, 1, 1)
	ball.CustomPhysicalProperties = PhysicalProperties.new(0.3, 0.4, 0.6, 1, 1)

	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, D * 0.3, 0)
	a0.Parent = ball
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -D * 0.3, 0)
	a1.Parent = ball
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.25
	trail.Color = ColorSequence.new(ball.Color)
	trail.Transparency = NumberSequence.new(0.4, 1)
	trail.Parent = ball

	ball.Touched:Connect(function(hit)
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
	for _, ball in ballsFolder:GetChildren() do
		local distance = ((ball :: Part).Position - root.Position).Magnitude
		if distance <= bestDistance and not (ball :: Part).Anchored then
			target, bestDistance = ball :: Part, distance
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

	local hitBall: Part? = nil
	local hitDistance = Config.RIFLE_RANGE
	for _, child in ballsFolder:GetChildren() do
		local ball = child :: Part
		local toBall = ball.Position - origin
		local along = toBall:Dot(direction)
		if along > 0 and along < hitDistance and not ball.Anchored then
			local miss = (toBall - direction * along).Magnitude
			if miss <= D / 2 + Config.RIFLE_HIT_TOLERANCE then
				hitBall, hitDistance = ball, along
			end
		end
	end

	tracer(origin, origin + direction * math.min(hitDistance, offset.Magnitude, Config.RIFLE_RANGE))
	if hitBall then
		hitBall.AssemblyLinearVelocity += direction * Config.RIFLE_NUDGE
		lastToucher[hitBall] = player
	end
end

local function removeOldestBonus()
	local oldest: Part? = nil
	for ball, expiry in bonusExpiry do
		if not oldest or expiry < bonusExpiry[oldest] then
			oldest = ball
		end
	end
	if oldest then
		destroyBall(oldest)
	end
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

	local blast = Instance.new("Explosion")
	blast.Position = origin
	blast.BlastRadius = 4
	blast.BlastPressure = 0
	blast.DestroyJointRadiusPercent = 0
	blast.Parent = workspace

	local gravity = workspace.Gravity
	local right = forward:Cross(Vector3.yAxis)
	for i = 1, Config.TANK_BALLS do
		while #ballsFolder:GetChildren() - 1 >= Config.MAX_BONUS_BALLS do
			removeOldestBonus()
		end

		local angle = math.random() * math.pi * 2
		local radius = math.sqrt(math.random()) * Config.TANK_SPREAD
		local landing = aimPoint + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		local start = origin + right * ((i - (Config.TANK_BALLS + 1) / 2) * (D + 0.5))

		local distance = Vector3.new(landing.X - start.X, 0, landing.Z - start.Z).Magnitude
		local flight =
			math.clamp(distance * Config.TANK_FLIGHT_PER_STUD, Config.TANK_MIN_FLIGHT, Config.TANK_MAX_FLIGHT)

		local ball = makeBall(true)
		ball.Position = start
		ball:SetNetworkOwner(nil)
		-- 포물선: start + v·t - ½g·t² 가 flight 초 뒤 landing 에 도달하도록 초기 속도 계산
		ball.AssemblyLinearVelocity = (landing - start) / flight + Vector3.new(0, 0.5 * gravity * flight, 0)
		bonusExpiry[ball] = os.clock() + Config.BONUS_BALL_LIFETIME
		lastToucher[ball] = player
	end
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
	else
		rifleShot(player, root, target :: Vector3)
	end
end

function BallService.init(field: Folder, net: Folder)
	ballsFolder = field:WaitForChild("Balls") :: Folder
	mainBall = makeBall(false)
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

-- 킥오프 준비: 보너스 공 제거, 메인 공을 중앙에 고정, 조작 비활성화
function BallService.reset()
	enabled = false
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
				table.insert(events, { kind = "out", isMain = true })
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
