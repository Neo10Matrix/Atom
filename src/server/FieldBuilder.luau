-- 경기장(잔디, 라인, 골대, 투명 벽, 스폰, 군대 장식)을 코드로 생성한다.
-- 전쟁 모드에서는 축구 골대 대신 당구 구멍 6개와 양쪽 끝 벽 위의 농구 링을 만든다.
-- Studio에서 따로 맵을 만들지 않아도 바로 플레이할 수 있다.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local CollisionGroups = require(script.Parent.CollisionGroups)

local L = Config.FIELD_LENGTH
local W = Config.FIELD_WIDTH
-- 전쟁 모드는 골대가 없으므로 끝 벽에 구멍을 뚫지 않는다
local GW = if Config.IS_WAR then 0 else Config.GOAL_WIDTH
local GH = Config.GOAL_HEIGHT
local GD = Config.GOAL_DEPTH
local WH = Config.WALL_HEIGHT

local FieldBuilder = {}

local function part(parent: Instance, props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

local function line(parent: Instance, cframe: CFrame, sizeX: number, sizeZ: number)
	part(parent, {
		Name = "Line",
		Size = Vector3.new(sizeX, 0.05, sizeZ),
		CFrame = cframe * CFrame.new(0, 0.025, 0),
		Color = Color3.new(1, 1, 1),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CanQuery = false,
	})
end

local function buildLines(parent: Instance)
	local t = 0.6
	-- 터치라인 / 골라인 / 하프라인
	line(parent, CFrame.new(0, 0, W / 2 - t / 2), L, t)
	line(parent, CFrame.new(0, 0, -W / 2 + t / 2), L, t)
	line(parent, CFrame.new(L / 2 - t / 2, 0, 0), t, W)
	line(parent, CFrame.new(-L / 2 + t / 2, 0, 0), t, W)
	line(parent, CFrame.new(0, 0, 0), t, W)

	-- 센터 서클
	local radius, segments = math.min(18, W * 0.15), 32
	local segLength = 2 * math.pi * radius / segments + 0.2
	for i = 1, segments do
		local angle = (i / segments) * math.pi * 2
		local cf = CFrame.new(math.cos(angle) * radius, 0, math.sin(angle) * radius) * CFrame.Angles(0, -angle, 0)
		line(parent, cf, t, segLength)
	end
	line(parent, CFrame.new(0, 0, 0), 1.5, 1.5)

	if Config.IS_WAR then
		return
	end
	-- 페널티 박스
	local boxDepth, boxWidth = Config.PENALTY_BOX_DEPTH, Config.PENALTY_BOX_WIDTH
	for _, side in { -1, 1 } do
		local edgeX = side * L / 2
		local innerX = edgeX - side * boxDepth
		line(parent, CFrame.new(innerX, 0, 0), t, boxWidth)
		line(parent, CFrame.new((edgeX + innerX) / 2, 0, boxWidth / 2), boxDepth, t)
		line(parent, CFrame.new((edgeX + innerX) / 2, 0, -boxWidth / 2), boxDepth, t)
	end
end

local function buildGoal(parent: Instance, side: number, teamColor: BrickColor)
	local goal = Instance.new("Model")
	goal.Name = "Goal"
	goal.Parent = parent

	local gx = side * L / 2
	local white = Color3.new(1, 1, 1)

	for _, zSign in { -1, 1 } do
		part(goal, {
			Name = "Post",
			Size = Vector3.new(1, GH, 1),
			Position = Vector3.new(gx + side * 0.5, GH / 2, zSign * (GW / 2 + 0.5)),
			Color = white,
		})
	end
	part(goal, {
		Name = "Crossbar",
		Size = Vector3.new(1, 1, GW + 2),
		Position = Vector3.new(gx + side * 0.5, GH + 0.5, 0),
		Color = white,
	})

	local netProps = {
		Color = white,
		Transparency = 0.6,
		Material = Enum.Material.SmoothPlastic,
	}
	local function net(name: string, size: Vector3, position: Vector3)
		local p = part(goal, netProps)
		p.Name = name
		p.Size = size
		p.Position = position
	end
	net("NetBack", Vector3.new(0.5, GH, GW), Vector3.new(gx + side * (GD + 0.25), GH / 2, 0))
	net("NetTop", Vector3.new(GD, 0.5, GW), Vector3.new(gx + side * GD / 2, GH + 0.25, 0))
	for _, zSign in { -1, 1 } do
		net("NetSide", Vector3.new(GD, GH, 0.5), Vector3.new(gx + side * GD / 2, GH / 2, zSign * (GW / 2 + 0.25)))
	end

	-- 골대 뒤 팀 깃발
	local poleX = gx + side * (GD + 6)
	part(goal, {
		Name = "FlagPole",
		Size = Vector3.new(0.6, 26, 0.6),
		Position = Vector3.new(poleX, 13, 0),
		Color = Color3.fromRGB(70, 70, 70),
		Material = Enum.Material.Metal,
	})
	part(goal, {
		Name = "Flag",
		Size = Vector3.new(0.2, 6, 10),
		Position = Vector3.new(poleX, 22, 5.3),
		BrickColor = teamColor,
		Material = Enum.Material.Fabric,
		CanCollide = false,
	})
end

local function buildWalls(parent: Instance)
	local walls = Instance.new("Folder")
	walls.Name = "Walls"
	walls.Parent = parent

	local wallProps = { Transparency = 1, CanQuery = false }
	local function wall(size: Vector3, position: Vector3)
		local p = part(walls, wallProps)
		p.Name = "Wall"
		p.Size = size
		p.Position = position
	end

	-- 측면
	for _, zSign in { -1, 1 } do
		wall(Vector3.new(L + 4, WH, 2), Vector3.new(0, WH / 2, zSign * (W / 2 + 1)))
	end
	-- 골라인 쪽 (골 입구만 비움)
	local segLength = (W / 2 + 2) - GW / 2
	for _, side in { -1, 1 } do
		local x = side * (L / 2 + 1)
		for _, zSign in { -1, 1 } do
			wall(Vector3.new(2, WH, segLength), Vector3.new(x, WH / 2, zSign * (GW / 2 + segLength / 2)))
		end
		if GW > 0 then
			local aboveGoal = WH - GH - 1
			wall(Vector3.new(2, aboveGoal, GW), Vector3.new(x, GH + 1 + aboveGoal / 2, 0))
		end
	end
	-- 천장 (공이 경기장 밖으로 날아가지 않도록)
	wall(Vector3.new(L + 4, 2, W + 4), Vector3.new(0, WH + 1, 0))

	-- 눈에 보이는 유리벽 (플러그인 경기장 스타일). 충돌은 위의 투명 벽이 담당한다
	local GH2 = Config.GLASS_WALL_HEIGHT
	local glassProps = {
		Name = "GlassWall",
		Color = Color3.fromRGB(170, 210, 230),
		Material = Enum.Material.Glass,
		Transparency = 0.6,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	}
	local function glass(size: Vector3, position: Vector3)
		local p = part(walls, glassProps)
		p.Size = size
		p.Position = position
	end
	for _, zSign in { -1, 1 } do
		glass(Vector3.new(L + 2, GH2, 0.5), Vector3.new(0, GH2 / 2, zSign * (W / 2 + 0.25)))
	end
	for _, side in { -1, 1 } do
		if GW == 0 then
			glass(Vector3.new(0.5, GH2, W + 1), Vector3.new(side * (L / 2 + 0.25), GH2 / 2, 0))
		else
			local glassSeg = W / 2 - GW / 2 - 1
			for _, zSign in { -1, 1 } do
				glass(Vector3.new(0.5, GH2, glassSeg), Vector3.new(side * (L / 2 + 0.25), GH2 / 2, zSign * (GW / 2 + 1 + glassSeg / 2)))
			end
		end
	end
end

-- 전쟁 모드: 당구 구멍 6개 (바닥의 검은 원. 공이 이 안으로 굴러 들어가면 득점은 WarService 가 판정)
local function buildPockets(parent: Instance)
	local pockets = Instance.new("Folder")
	pockets.Name = "Pockets"
	pockets.Parent = parent
	local r = Config.POCKET_RADIUS
	for _, center in Config.POCKETS do
		part(pockets, {
			Name = "Pocket",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.1, r * 2, r * 2),
			CFrame = CFrame.new(center + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			Color = Color3.fromRGB(15, 15, 15),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		})
		part(pockets, {
			Name = "PocketRim",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.08, r * 2 + 1.2, r * 2 + 1.2),
			CFrame = CFrame.new(center + Vector3.new(0, 0.04, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			Color = Color3.fromRGB(200, 170, 60),
			Material = Enum.Material.Metal,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		})
	end
end

-- 전쟁 모드: 양쪽 끝 벽 위의 반투명 농구 링. 농구공만 부딪힌다 (선수·다른 공은 통과)
local function buildHoop(parent: Instance, side: number, teamColor: BrickColor)
	local hoop = Instance.new("Model")
	hoop.Name = "Hoop"
	hoop.Parent = parent
	local center = Config.HOOPS[side]
	local r = Config.HOOP_RADIUS
	local hoopProps = {
		Transparency = 0.5,
		CanQuery = false,
		CollisionGroup = CollisionGroups.Hoop,
		Material = Enum.Material.SmoothPlastic,
	}
	local board = part(hoop, hoopProps)
	board.Name = "Backboard"
	board.Size = Vector3.new(0.4, 6, 10)
	board.Position = Vector3.new(side * (L / 2 - 0.5), center.Y + 2.5, 0)
	board.Color = Color3.new(1, 1, 1)
	-- 링: 작은 조각을 원 모양으로 이어 붙인다
	local segments = 14
	local segLength = 2 * math.pi * r / segments + 0.15
	for i = 1, segments do
		local angle = (i / segments) * math.pi * 2
		local p = part(hoop, hoopProps)
		p.Name = "Rim"
		p.Size = Vector3.new(0.3, 0.3, segLength)
		p.CFrame = CFrame.new(center + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)) * CFrame.Angles(0, -angle, 0)
		p.BrickColor = teamColor
		p.Transparency = 0.2
	end
end

local function buildSpawns(parent: Instance)
	for _, key in Config.TEAM_ORDER do
		local info = Config.Teams[key]
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = key .. "Spawn"
		spawn.Anchored = true
		spawn.Size = Vector3.new(12, 0.1, 12)
		spawn.Position = Vector3.new(info.Side * (L / 2 - 20), 0.05, 0)
		spawn.Transparency = 1
		spawn.CanCollide = false
		spawn.CanQuery = false
		spawn.Neutral = false
		spawn.TeamColor = info.Color
		spawn.AllowTeamChangeOnTouch = false
		spawn.Duration = 0
		spawn.Parent = parent
	end
end

-- 양쪽 터치라인 밖 계단식 관중석과 알록달록한 관중 (플러그인 경기장 스타일)
local function buildStands(parent: Instance)
	local stands = Instance.new("Folder")
	stands.Name = "Stands"
	stands.Parent = parent

	local rng = Random.new(7)
	local skin = { Color3.fromRGB(255, 220, 180), Color3.fromRGB(224, 172, 105), Color3.fromRGB(141, 85, 36) }
	for _, zSign in { -1, 1 } do
		for row = 1, Config.STAND_ROWS do
			local stepTop = row * 1.5
			local z = zSign * (W / 2 + 2 + row * 3)
			part(stands, {
				Name = "Step",
				Size = Vector3.new(L, stepTop, 3),
				Position = Vector3.new(0, stepTop / 2, z),
				Color = Color3.fromRGB(90, 95, 80),
				Material = Enum.Material.Concrete,
				CanQuery = false,
			})
			for x = -L / 2 + 3, L / 2 - 3, 4 do
				local jitter = rng:NextNumber(-0.6, 0.6)
				part(stands, {
					Name = "FanBody",
					Size = Vector3.new(1.4, 2, 1),
					Position = Vector3.new(x + jitter, stepTop + 1, z),
					Color = Color3.fromHSV(rng:NextNumber(), rng:NextNumber(0.4, 0.9), rng:NextNumber(0.5, 1)),
					CanCollide = false,
					CanQuery = false,
				})
				part(stands, {
					Name = "FanHead",
					Size = Vector3.new(1, 1, 1),
					Position = Vector3.new(x + jitter, stepTop + 2.5, z),
					Color = skin[rng:NextInteger(1, #skin)],
					CanCollide = false,
					CanQuery = false,
				})
			end
		end
	end
end

local scoreLabel: TextLabel? = nil

-- 경기장 위 대형 점수판 (플러그인 경기장의 Scoreboard 처럼)
local function buildScoreboard(parent: Instance)
	local anchor = part(parent, {
		Name = "Scoreboard",
		Size = Vector3.new(1, 1, 1),
		Position = Vector3.new(0, Config.SERVE_HEIGHT + 25, 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(40, 0, 8, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 1000
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(30, 35, 25)
	label.BackgroundTransparency = 0.2
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.Text = "아미사커"
	label.Parent = gui
	scoreLabel = label
end

function FieldBuilder.setScoreboard(text: string)
	if scoreLabel then
		scoreLabel.Text = text
	end
end

local function buildDecorations(parent: Instance)
	local deco = Instance.new("Folder")
	deco.Name = "Decorations"
	deco.Parent = parent

	-- 경기장 둘레 모래주머니
	local sandbagProps = {
		Name = "Sandbag",
		Size = Vector3.new(5, 2.5, 3),
		Color = Color3.fromRGB(150, 130, 90),
		Material = Enum.Material.Fabric,
		CanQuery = false,
	}
	local offset = 6 + Config.STAND_ROWS * 3 -- 관중석 바깥
	local function sandbagRow(from: Vector3, to: Vector3)
		local length = (to - from).Magnitude
		local direction = (to - from).Unit
		local count = math.floor(length / 5.5)
		for i = 0, count do
			local pos = from:Lerp(to, i / math.max(count, 1))
			local p = part(deco, sandbagProps)
			p.CFrame = CFrame.lookAt(pos, pos + direction) * CFrame.Angles(0, math.pi / 2, 0) + Vector3.new(0, 1.25, 0)
		end
	end
	local hx, hz = L / 2 + GD + offset, W / 2 + offset
	sandbagRow(Vector3.new(hx, 0, -hz), Vector3.new(hx, 0, hz))
	sandbagRow(Vector3.new(-hx, 0, -hz), Vector3.new(-hx, 0, hz))

	-- 네 모서리 감시탑
	local wood = Color3.fromRGB(105, 80, 55)
	for _, xs in { -1, 1 } do
		for _, zs in { -1, 1 } do
			local base = Vector3.new(xs * (hx + 8), 0, zs * (hz + 8))
			for _, lx in { -1, 1 } do
				for _, lz in { -1, 1 } do
					part(deco, {
						Name = "TowerLeg",
						Size = Vector3.new(1, 18, 1),
						Position = base + Vector3.new(lx * 3.5, 9, lz * 3.5),
						Color = wood,
						Material = Enum.Material.Wood,
					})
				end
			end
			part(deco, {
				Name = "TowerFloor",
				Size = Vector3.new(9, 1, 9),
				Position = base + Vector3.new(0, 18, 0),
				Color = wood,
				Material = Enum.Material.WoodPlanks,
			})
			part(deco, {
				Name = "TowerRoof",
				Size = Vector3.new(10, 0.6, 10),
				Position = base + Vector3.new(0, 25, 0),
				Color = Color3.fromRGB(75, 90, 55),
				Material = Enum.Material.CorrodedMetal,
			})
		end
	end
end

function FieldBuilder.build(): Folder
	local existing = workspace:FindFirstChild("ArmySoccerField")
	if existing then
		existing:Destroy()
	end
	-- Studio Baseplate 템플릿의 기본 바닥·스폰은 경기장 한가운데와 겹치므로 지운다
	for _, child in workspace:GetChildren() do
		if child:IsA("SpawnLocation") or (child:IsA("BasePart") and child.Name == "Baseplate") then
			child:Destroy()
		end
	end

	local field = Instance.new("Folder")
	field.Name = "ArmySoccerField"

	part(field, {
		Name = "Ground",
		Size = Vector3.new(L + 200, 1, W + 200),
		Position = Vector3.new(0, -0.6, 0),
		Color = Color3.fromRGB(110, 90, 60),
		Material = Enum.Material.Ground,
	})
	part(field, {
		Name = "Pitch",
		Size = Vector3.new(L, 1, W),
		Position = Vector3.new(0, -0.5, 0),
		Color = Color3.fromRGB(80, 125, 60),
		Material = Enum.Material.Grass,
	})

	buildLines(field)
	for _, key in Config.TEAM_ORDER do
		local info = Config.Teams[key]
		if Config.IS_WAR then
			buildHoop(field, info.Side, info.Color)
		else
			buildGoal(field, info.Side, info.Color)
		end
	end
	if Config.IS_WAR then
		buildPockets(field)
	end
	buildWalls(field)
	buildSpawns(field)
	buildStands(field)
	buildScoreboard(field)
	buildDecorations(field)

	local balls = Instance.new("Folder")
	balls.Name = "Balls"
	balls.Parent = field

	field.Parent = workspace
	return field
end

return FieldBuilder
