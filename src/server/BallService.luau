-- 축구공(일반 크기): 킥오프 때 인원에 맞춰 놓이는 공들, 자석 드리블, 킥 처리, 골 판정
-- * 축구공은 발로만 다룬다.
-- * 공에 닿으면 소유권을 얻고, 공이 발 앞에 붙어서 따라온다 (자석 드리블). 소유 중에는 팀 색 테두리.
-- * 다른 선수가 닿으면 공을 뺏는다 (잡은 직후 STEAL_PROTECT 동안은 보호).
-- * 드리블 중 헤딩하면 공을 놓치고, CONTROL_LOCK_TIME 동안 축구공을 다시 못 잡는다.
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
-- 찬 공이 바로 다시 발에 붙지 않도록 잠깐 잡기 금지 (초)
local KICK_REGRAB_DELAY = 0.4
-- 공이 이 높이보다 떠 있으면 드리블로 잡지 않는다 (공중볼은 그냥 튕김)
local GRAB_MAX_HEIGHT = D / 2 + 2.5

export type BallEvent = {
	kind: "goal" | "out",
	side: number?, -- 공이 들어간 골대 쪽 (-1 / 1)
	scorer: PlayerService.Actor?,
}

type Actor = PlayerService.Actor
type Possession = { player: Actor, since: number }

local BallService = {}

local folder: Instance
local balls: { Part } = {}
local startPosition: { [Part]: Vector3 } = {}
local lastToucher: { [Part]: Actor } = {}
local owner: { [Part]: Possession } = {}
local highlight: { [Part]: Highlight } = {}
local lastKick: { [Actor]: number } = {}
local regrabAt: { [Actor]: number } = {}
local enabled = false

local function aliveRoot(actor: Actor): BasePart?
	local character = PlayerService.characterOf(actor)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return root
end

local function flatLook(root: BasePart): Vector3
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	return if flat.Magnitude > 1e-3 then flat.Unit else Vector3.xAxis
end

local function ownsAny(player: Actor): boolean
	for _, possession in owner do
		if possession.player == player then
			return true
		end
	end
	return false
end

local function release(ball: Part)
	local possession = owner[ball]
	if not possession then
		return
	end
	owner[ball] = nil
	highlight[ball].Enabled = false
	if possession.player.Parent then
		possession.player:SetAttribute("Dribbling", ownsAny(possession.player))
	end
end

local function grab(ball: Part, player: Actor)
	owner[ball] = { player = player, since = os.clock() }
	local key = PlayerService.teamKeyOf(player)
	highlight[ball].OutlineColor = if key then Config.Teams[key].Color.Color else Color3.new(1, 1, 1)
	highlight[ball].Enabled = true
	player:SetAttribute("Dribbling", true)
end

local function onTouched(ball: Part, hit: BasePart)
	local player = PlayerService.actorFromPart(hit)
	if not player or not PlayerService.canTouchSoccer(player) then
		return
	end
	lastToucher[ball] = player

	local now = os.clock()
	if not enabled or ball.Position.Y > GRAB_MAX_HEIGHT or now < (regrabAt[player] or 0) then
		return
	end
	local current = owner[ball]
	if current and (current.player == player or now - current.since < Config.STEAL_PROTECT) then
		return
	end
	release(ball)
	grab(ball, player)
end

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

	-- 소유 중 표시: 소유한 선수의 팀 색 테두리
	local outline = Instance.new("Highlight")
	outline.FillTransparency = 1
	outline.OutlineTransparency = 0
	outline.Enabled = false
	outline.Parent = ball
	highlight[ball] = outline

	ball.Touched:Connect(function(hit)
		onTouched(ball, hit)
	end)
	return ball
end

-- 킥: 드리블 중인 공이 있으면 그 공을, 없으면 가장 가까운 공을 바라보는 방향으로 찬다
-- (플레이어는 원격 이벤트로, 봇은 직접 호출)
function BallService.kick(player: Actor, power: unknown)
	if not enabled or typeof(power) ~= "number" or power ~= power then
		return
	end
	local root = aliveRoot(player)
	if not root or not PlayerService.canTouchSoccer(player) then
		return
	end

	local target: Part? = nil
	for ball, possession in owner do
		if possession.player == player then
			target = ball
		end
	end
	if not target then
		local bestDistance = Config.KICK_RANGE
		for _, ball in balls do
			local distance = (ball.Position - root.Position).Magnitude
			if distance <= bestDistance then
				target, bestDistance = ball, distance
			end
		end
	end
	local now = os.clock()
	local last = lastKick[player]
	if not target or (last and now - last < Config.KICK_COOLDOWN * COOLDOWN_LENIENCY) then
		return
	end
	lastKick[player] = now
	regrabAt[player] = now + KICK_REGRAB_DELAY
	release(target)

	local alpha = math.clamp(power :: number, 0, 1)
	local speed = Config.KICK_MIN_SPEED + (Config.KICK_MAX_SPEED - Config.KICK_MIN_SPEED) * alpha
	local lift = Config.KICK_MIN_LIFT + (Config.KICK_MAX_LIFT - Config.KICK_MIN_LIFT) * alpha
	target.AssemblyLinearVelocity = (flatLook(root) + Vector3.new(0, lift, 0)).Unit * speed
	lastToucher[target] = player
end

-- 헤딩하면 호출: 드리블 중이던 축구공을 놓쳐서 앞으로 굴러가고, 잠시 축구공을 못 잡는다
function BallService.dropFor(player: Actor)
	PlayerService.lockSoccer(player)
	local root = aliveRoot(player)
	for _, ball in balls do
		local possession = owner[ball]
		if possession and possession.player == player then
			release(ball)
			if root then
				ball.AssemblyLinearVelocity = flatLook(root) * Config.HEADER_DROP_SPEED + Vector3.new(0, 8, 0)
			end
		end
	end
end

-- 드리블 중인 공을 소유자의 발 앞으로 끌어당긴다
local function updateDribble(ball: Part)
	local possession = owner[ball]
	if not possession then
		return
	end
	local root = aliveRoot(possession.player)
	if not root then
		release(ball)
		return
	end
	local target = root.Position + flatLook(root) * Config.DRIBBLE_OFFSET
	local offset = Vector3.new(target.X - ball.Position.X, 0, target.Z - ball.Position.Z)
	if offset.Magnitude > Config.DRIBBLE_BREAK then
		release(ball)
		return
	end
	local runVelocity = root.AssemblyLinearVelocity
	local desired = Vector3.new(runVelocity.X, 0, runVelocity.Z) + offset * Config.DRIBBLE_GAIN
	ball.AssemblyLinearVelocity = Vector3.new(desired.X, ball.AssemblyLinearVelocity.Y, desired.Z)
end

local function placeAtStart(ball: Part)
	release(ball)
	ball.CFrame = CFrame.new(startPosition[ball])
	ball.AssemblyLinearVelocity = Vector3.zero
	ball.AssemblyAngularVelocity = Vector3.zero
	lastToucher[ball] = nil
end

function BallService.init(field: Folder, net: Folder)
	folder = field:WaitForChild("Balls")
	BallService.reset(1)

	local kick = net:WaitForChild("Kick") :: RemoteEvent
	kick.OnServerEvent:Connect(BallService.kick)
	Players.PlayerRemoving:Connect(function(player)
		lastKick[player] = nil
		regrabAt[player] = nil
		for _, ball in balls do
			if owner[ball] and owner[ball].player == player then
				release(ball)
			end
		end
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
		release(ball)
		startPosition[ball] = nil
		lastToucher[ball] = nil
		highlight[ball] = nil
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

-- 봇 AI 용: 현재 축구공 목록과 소유자
function BallService.getBalls(): { Part }
	return balls
end

function BallService.ownerOf(ball: Part): Actor?
	local possession = owner[ball]
	return possession and possession.player
end

-- 매 프레임 호출: 드리블, 골/아웃을 처리하고 발생한 이벤트 목록을 돌려준다
function BallService.step(): { BallEvent }
	local events: { BallEvent } = {}
	for _, ball in balls do
		updateDribble(ball)
		local p = ball.Position
		if math.abs(p.Z) < Config.GOAL_WIDTH / 2 and p.Y < Config.GOAL_HEIGHT and math.abs(p.X) > L / 2 + D / 2 then
			enabled = false
			release(ball)
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
