-- 전쟁 모드: 5종목 공(축구공·미식축구공·농구공·배구공·셔틀콕)을 총으로만 다룬다
-- * 킥·헤딩·드리블은 없다. 공은 총알과 로켓 폭발에만 움직인다 (WeaponService 가 push 를 호출).
-- * 득점 방식은 공마다 다르다 (Config.WAR_BALLS 의 Goal):
--   pocket: 당구처럼 구멍 6개 중 아무 데나 넣으면 마지막으로 쏜 선수의 팀이 득점
--   hoop:   상대 쪽 끝 벽 위의 농구 링에 위에서 아래로 통과하면 득점
--   net:    공중 네트를 넘겨 상대 진영 바닥에 떨어뜨리면 득점. 네트 밑으로 빠지면 마지막으로 쏜 팀 실점
-- * 득점해도 경기는 멈추지 않는다. 그 공만 잠시 뒤 다시 나온다.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local CollisionGroups = require(script.Parent.CollisionGroups)
local PlayerService = require(script.Parent.PlayerService)
local ShuttleService = require(script.Parent.ShuttleService)

type Actor = PlayerService.Actor

export type WarEvent = {
	scoringKey: string,
	scorer: Actor?,
	text: string,
}

export type WarBall = {
	kind: { [string]: any },
	part: Part,
	enabled: boolean,
	respawnAt: number?,
	lastShooter: Actor?,
	lastPosition: Vector3,
	stillSince: number?,
	serveSide: number,
	lane: number,
}

local L = Config.FIELD_LENGTH
local W = Config.FIELD_WIDTH
local SERVE_X = L / 4 -- 네트 공이 서브되는 위치 (네트에서 떨어진 거리)
local STUCK_TIME = 1.5 -- 바닥이 아닌 곳에 멈춰 있어도 이 시간이 지나면 떨어진 것으로 본다

local WarService = {}

local field: Folder
local balls: { WarBall } = {}
local byPart: { [BasePart]: WarBall } = {}
local pending: { WarEvent } = {}

local function teamKeyForSide(side: number): string
	for key, info in Config.Teams do
		if info.Side == side then
			return key
		end
	end
	error("no team on side " .. side)
end

local function sideOf(x: number): number
	return if x < 0 then -1 else 1
end

-- 중력 일부를 상쇄해서 천천히 떨어지게 한다 (농구공·배구공)
local function addLift(part: Part, gravity: number)
	if gravity >= 1 then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Parent = part
	local lift = Instance.new("VectorForce")
	lift.Attachment0 = attachment
	lift.RelativeTo = Enum.ActuatorRelativeTo.World
	lift.ApplyAtCenterOfMass = true
	lift.Force = Vector3.new(0, part.AssemblyMass * workspace.Gravity * (1 - gravity), 0)
	lift.Parent = part
end

-- 공 위에 종목 이름 표시
local function addNameTag(part: Part, text: string)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 110, 0, 22)
	gui.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + 2, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 120
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.Parent = gui
	gui.Parent = part
end

local function makeBall(kind: { [string]: any }): Part
	local part: Part
	if kind.Shuttle then
		part = (ShuttleService.buildBody(field))
	else
		part = Instance.new("Part")
		part.Name = kind.Key
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.one * kind.Diameter
		part.Color = kind.Color
		part.Material = Enum.Material.SmoothPlastic
		part.CustomPhysicalProperties = PhysicalProperties.new(0.3, 0.4, 0.6, 1, 1)
		-- 농구공만 링에 부딪히고, 네트 공(배구공)은 네트에 막힌다
		part.CollisionGroup = if kind.Goal == "hoop"
			then CollisionGroups.Basketball
			elseif kind.Goal == "net" then CollisionGroups.Shuttle
			else CollisionGroups.SoccerBall
		if kind.Stretch then
			-- 미식축구공: 충돌은 공 모양 그대로, 보이는 모양만 길쭉하게
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Scale = Vector3.new(1, 1, kind.Stretch)
			mesh.Parent = part
		end
		part.Anchored = true
		part.Parent = field
		addLift(part, kind.Gravity)
	end
	part:SetAttribute("WarBall", kind.Key)
	addNameTag(part, kind.Name)
	return part
end

local function startCFrame(b: WarBall): CFrame
	if b.kind.Goal == "net" then
		return CFrame.new(b.serveSide * SERVE_X, Config.SERVE_HEIGHT, b.lane)
	end
	return CFrame.new(0, b.part.Size.Y / 2 + 0.5, b.lane)
end

-- 시작 자리(네트 공은 서브 높이)에 고정한다. 다시 움직이게 하려면 activate
local function place(b: WarBall)
	b.enabled = false
	b.part.Anchored = true
	b.part.CFrame = startCFrame(b)
	b.part.AssemblyLinearVelocity = Vector3.zero
	b.part.AssemblyAngularVelocity = Vector3.zero
	b.lastShooter = nil
	b.lastPosition = b.part.Position
	b.stillSince = nil
end

local function activate(b: WarBall)
	b.respawnAt = nil
	b.part.Anchored = false
	b.part:SetNetworkOwner(nil)
	b.enabled = true
end

-- 득점(또는 무효) 후 그 공만 시작 자리로 돌려놓고 잠시 뒤 다시 내보낸다
local function respawn(b: WarBall, delay: number)
	place(b)
	b.respawnAt = os.clock() + delay
end

local function score(b: WarBall, scoringKey: string, scorer: Actor?, text: string)
	table.insert(pending, { scoringKey = scoringKey, scorer = scorer, text = text })
	if b.kind.Goal == "net" then
		-- 득점한 팀 쪽에서 다음 서브
		b.serveSide = Config.Teams[scoringKey].Side
	end
	respawn(b, Config.WAR_RESPAWN_DELAY)
end

local function shooterKey(b: WarBall): string?
	local shooter = b.lastShooter
	return if shooter and shooter.Parent then PlayerService.teamKeyOf(shooter) else nil
end

local function checkPocket(b: WarBall, p: Vector3): boolean
	for _, center in Config.POCKETS do
		local horizontal = Vector3.new(p.X - center.X, 0, p.Z - center.Z).Magnitude
		if horizontal < Config.POCKET_RADIUS - 1 and p.Y < b.part.Size.Y + 1 then
			local key = shooterKey(b)
			if key then
				score(b, key, b.lastShooter, string.format("포켓! %s 득점 (%s)", Config.Teams[key].Name, b.kind.Name))
			else
				respawn(b, Config.WAR_RESPAWN_DELAY)
			end
			return true
		end
	end
	return false
end

local function checkHoop(b: WarBall, p: Vector3): boolean
	local before = b.lastPosition
	for side, center in Config.HOOPS do
		local horizontal = Vector3.new(p.X - center.X, 0, p.Z - center.Z).Magnitude
		if before.Y > center.Y and p.Y <= center.Y and horizontal < Config.HOOP_RADIUS then
			-- 그 링이 붙은 쪽의 반대편 팀이 득점
			local key = teamKeyForSide(-side)
			score(b, key, b.lastShooter, string.format("골인! %s 득점 (%s)", Config.Teams[key].Name, b.kind.Name))
			return true
		end
	end
	return false
end

local function checkNet(b: WarBall, p: Vector3, dt: number, now: number): boolean
	if b.kind.Shuttle then
		-- 셔틀콕은 수평 속도에 공기 저항
		local v = b.part.AssemblyLinearVelocity
		local damping = math.max(0, 1 - Config.SHUTTLE_DRAG * dt)
		b.part.AssemblyLinearVelocity = Vector3.new(v.X * damping, v.Y, v.Z * damping)
	end

	-- 네트 밑으로 빠짐: 마지막으로 쏜 팀 실점
	if sideOf(p.X) ~= sideOf(b.lastPosition.X) and p.Y < Config.NET_BOTTOM then
		local key = shooterKey(b)
		if key then
			local other = teamKeyForSide(-Config.Teams[key].Side)
			score(b, other, nil, string.format("%s 득점! %s 네트 밑으로 빠짐 (%s)", Config.Teams[other].Name, Config.Teams[key].Name, b.kind.Name))
		else
			respawn(b, Config.SERVE_DELAY)
		end
		return true
	end

	if b.part.AssemblyLinearVelocity.Magnitude < 0.5 then
		b.stillSince = b.stillSince or now
	else
		b.stillSince = nil
	end
	-- 바닥에 떨어짐: 떨어진 진영의 팀 실점
	if p.Y <= b.part.Size.Y / 2 + 0.6 or (b.stillSince and now - b.stillSince > STUCK_TIME) then
		local concedingSide = sideOf(p.X)
		local key = teamKeyForSide(-concedingSide)
		score(b, key, b.lastShooter, string.format(
			"%s 득점! %s 진영에 떨어짐 (%s)",
			Config.Teams[key].Name,
			Config.Teams[teamKeyForSide(concedingSide)].Name,
			b.kind.Name
		))
		return true
	end
	return false
end

function WarService.init(fieldFolder: Folder)
	field = fieldFolder
	local groundLanes = { -15, 0, 15 }
	local netLanes = { -W / 4, W / 4 }
	local groundIndex, netIndex = 0, 0
	for _, kind in Config.WAR_BALLS do
		local lane
		if kind.Goal == "net" then
			netIndex += 1
			lane = netLanes[(netIndex - 1) % #netLanes + 1]
		else
			groundIndex += 1
			lane = groundLanes[(groundIndex - 1) % #groundLanes + 1]
		end
		local part = makeBall(kind)
		local b: WarBall = {
			kind = kind,
			part = part,
			enabled = false,
			respawnAt = nil,
			lastShooter = nil,
			lastPosition = part.Position,
			stillSince = nil,
			serveSide = if math.random() < 0.5 then -1 else 1,
			lane = lane,
		}
		byPart[part] = b
		table.insert(balls, b)
		place(b)
	end
end

-- 킥오프 준비: 모든 공을 시작 자리에 고정
function WarService.reset()
	pending = {}
	for _, b in balls do
		b.respawnAt = nil
		place(b)
	end
end

function WarService.release()
	for _, b in balls do
		activate(b)
	end
end

-- 총알·로켓 폭발에 맞으면 호출 (WeaponService)
function WarService.push(part: BasePart, impulse: Vector3, shooter: Actor)
	local b = byPart[part]
	if not b or not b.enabled then
		return
	end
	local v = impulse * b.kind.Push
	-- 공마다 정해진 만큼 위로 더 띄운다 (농구 링·공중 네트를 넘길 수 있게)
	v += Vector3.new(0, v.Magnitude * b.kind.Up, 0)
	b.part.AssemblyLinearVelocity += v
	b.lastShooter = shooter
end

-- 무기 폭발 판정용: 지금 움직이는 공 파트들
function WarService.getParts(): { BasePart }
	local parts = {}
	for _, b in balls do
		if b.enabled then
			table.insert(parts, b.part)
		end
	end
	return parts
end

-- 봇 AI 용: 지금 움직이는 공들
function WarService.getActive(): { WarBall }
	local active = {}
	for _, b in balls do
		if b.enabled then
			table.insert(active, b)
		end
	end
	return active
end

-- 매 프레임 호출: 득점 판정과 다시 나오기. 발생한 득점 이벤트를 돌려준다
function WarService.step(dt: number): { WarEvent }
	local now = os.clock()
	for _, b in balls do
		if b.respawnAt then
			if now >= b.respawnAt then
				activate(b)
			end
		elseif b.enabled then
			local p = b.part.Position
			if math.abs(p.X) > L / 2 + 10 or math.abs(p.Z) > W / 2 + 10 or p.Y > Config.WALL_HEIGHT + 5 or p.Y < -20 then
				-- 경기장 밖: 점수 없이 다시
				respawn(b, Config.SERVE_DELAY)
			else
				local goal = b.kind.Goal
				local scored = if goal == "pocket"
					then checkPocket(b, p)
					elseif goal == "hoop" then checkHoop(b, p)
					else checkNet(b, p, dt, now)
				if not scored then
					b.lastPosition = p
				end
			end
		end
	end
	local events = pending
	pending = {}
	return events
end

return WarService
