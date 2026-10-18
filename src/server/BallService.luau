-- 축구공(일반 크기): 킥오프 때 인원에 맞춰 놓이는 공들, 킥 처리, 골 판정
-- 축구공은 발로만 찬다
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local CollisionGroups = require(script.Parent.CollisionGroups)
local PlayerService = require(script.Parent.PlayerService)

local L = Config.FIELD_LENGTH
local W = Config.FIELD_WIDTH
local D = Config.BALL_DIAMETER
-- 킥오프 때 공들이 놓이는 간격: 센터 서클 안에 Z축으로 나란히
local START_SPACING = D + 6
-- 클라이언트/서버 시간 차이로 정상 입력이 거부되지 않도록 쿨다운을 조금 느슨하게 검사
local COOLDOWN_LENIENCY = 0.9

export type BallEvent = {
	kind: "goal" | "out",
	side: number?, -- 공이 들어간 골대 쪽 (-1 / 1)
	scorer: Player?,
}

local BallService = {}

local folder: Instance
local balls: { Part } = {}
local startPosition: { [Part]: Vector3 } = {}
local lastToucher: { [Part]: Player } = {}
local lastKick: { [Player]: number } = {}
local enabled = false

local function makeBall(): Part
	local ball = Instance.new("Part")
	ball.Name = "Ball"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * D
	ball.Material = Enum.Material.SmoothPlastic
	ball.Color = Color3.new(1, 1, 1)
	ball.CustomPhysicalProperties = PhysicalProperties.new(0.3, 0.4, 0.6, 1, 1)
	ball.CollisionGroup = CollisionGroups.SoccerBall

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
	trail.Transparency = NumberSequence.new(0.4, 1)
	trail.Parent = ball

	ball.Touched:Connect(function(hit)
		local model = hit:FindFirstAncestorOfClass("Model")
		local player = model and Players:GetPlayerFromCharacter(model)
		-- 몸에 닿으면 드리블 중으로 기록 (헤딩 직후라면 드리블로 치지 않음)
		if player and PlayerService.markControl(player, "Soccer") then
			lastToucher[ball] = player
		end
	end)
	return ball
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

-- 킥 (축구는 발로만): 가장 가까운 공을 캐릭터가 바라보는 방향으로 찬다
local function onKick(player: Player, power: unknown)
	if not enabled or typeof(power) ~= "number" or power ~= power then
		return
	end
	local root = aliveRoot(player)
	if not root or not PlayerService.canControl(player, "Soccer") then
		return
	end
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		return
	end
	local direction = flat.Unit

	local target: Part? = nil
	local bestDistance = Config.KICK_RANGE
	for _, ball in balls do
		local distance = (ball.Position - root.Position).Magnitude
		if distance <= bestDistance then
			target, bestDistance = ball, distance
		end
	end
	local now = os.clock()
	local last = lastKick[player]
	if not target or (last and now - last < Config.KICK_COOLDOWN * COOLDOWN_LENIENCY) then
		return
	end
	lastKick[player] = now
	PlayerService.markControl(player, "Soccer")

	local alpha = math.clamp(power :: number, 0, 1)
	local speed = Config.KICK_MIN_SPEED + (Config.KICK_MAX_SPEED - Config.KICK_MIN_SPEED) * alpha
	local lift = Config.KICK_MIN_LIFT + (Config.KICK_MAX_LIFT - Config.KICK_MIN_LIFT) * alpha
	target.AssemblyLinearVelocity = (direction + Vector3.new(0, lift, 0)).Unit * speed
	lastToucher[target] = player
end

local function placeAtStart(ball: Part)
	ball.CFrame = CFrame.new(startPosition[ball])
	ball.AssemblyLinearVelocity = Vector3.zero
	ball.AssemblyAngularVelocity = Vector3.zero
	lastToucher[ball] = nil
end

function BallService.init(field: Folder, net: Folder)
	folder = field:WaitForChild("Balls")
	BallService.reset(1)

	local kick = net:WaitForChild("Kick") :: RemoteEvent
	kick.OnServerEvent:Connect(onKick)
	Players.PlayerRemoving:Connect(function(player)
		lastKick[player] = nil
	end)
end

-- 킥오프 준비: 공을 count 개로 맞추고 시작 자리에 고정, 킥을 막는다
function BallService.reset(count: number)
	enabled = false
	while #balls < count do
		local ball = makeBall()
		ball.Parent = folder
		table.insert(balls, ball)
	end
	while #balls > count do
		local ball = table.remove(balls) :: Part
		startPosition[ball] = nil
		lastToucher[ball] = nil
		ball:Destroy()
	end
	for i, ball in balls do
		local z = (i - (count + 1) / 2) * START_SPACING
		startPosition[ball] = Vector3.new(0, D / 2 + 0.5, z)
		ball.Anchored = true
		placeAtStart(ball)
	end
end

function BallService.release()
	for _, ball in balls do
		ball.Anchored = false
		ball:SetNetworkOwner(nil)
	end
	enabled = true
end

-- 매 프레임 호출: 골/아웃을 처리하고 발생한 이벤트 목록을 돌려준다
function BallService.step(): { BallEvent }
	local events: { BallEvent } = {}
	for _, ball in balls do
		local p = ball.Position
		if math.abs(p.Z) < Config.GOAL_WIDTH / 2 and p.Y < Config.GOAL_HEIGHT and math.abs(p.X) > L / 2 + D / 2 then
			enabled = false
			table.insert(events, {
				kind = "goal",
				side = if p.X < 0 then -1 else 1,
				scorer = lastToucher[ball],
			})
			-- 한 프레임에 두 골이 동시에 들어가도 킥오프는 한 번
			break
		elseif
			p.Y < -20
			or p.Y > Config.WALL_HEIGHT + 20
			or math.abs(p.X) > L / 2 + Config.GOAL_DEPTH + 10
			or math.abs(p.Z) > W / 2 + 10
		then
			placeAtStart(ball)
			table.insert(events, { kind = "out" })
		end
	end
	return events
end

return BallService
