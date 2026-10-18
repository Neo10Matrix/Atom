-- 진영 규칙과 골키퍼 구역
-- * 필드 선수는 기본적으로 하프라인 벽에 막혀 자기 진영에만 있다.
-- * 자기 진영에서 적 방향으로 공을 찬 선수만 잠시 하프라인을 통과할 수 있다 (수비수가 남도록).
-- * 적진에 들어갔다가 자기 진영으로 돌아오면 다시 막힌다.
-- * 골키퍼는 자기 골키퍼 구역(페널티 박스) 안에서만 움직인다.
-- 벽은 충돌 그룹으로 특정 선수만 막고, 공은 통과시킨다.
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local PlayerService = require(script.Parent.PlayerService)

local L = Config.FIELD_LENGTH
local W = Config.FIELD_WIDTH
local WH = Config.WALL_HEIGHT

-- 자기 진영으로 이만큼 들어와야 "복귀"로 본다 (하프라인 벽 두께보다 크게)
local RETURN_DEPTH = 3
-- 막힌 선수가 적진에서 이만큼 넘어가 있으면 서버가 되돌린다 (치트/끼임 방지)
local ILLEGAL_DEPTH = 4

type ZoneState = "Locked" | "Ready" | "Crossed"

local ZoneService = {}

ZoneService.Groups = {
	HalfLine = "HalfLine",
	Restricted = "PlayersRestricted",
	Free = "PlayersFree",
	SpecialBall = "SpecialBall",
}

local states: { [Player]: { state: ZoneState, expiry: number } } = {}

local function keeperGroup(key: string): string
	return "Keeper" .. key
end

local function keeperBoxGroup(key: string): string
	return "KeeperBox" .. key
end

local function registerGroups()
	local G = ZoneService.Groups
	local all = { "Default", G.HalfLine, G.Restricted, G.Free, G.SpecialBall }
	for _, key in Config.TEAM_ORDER do
		table.insert(all, keeperGroup(key))
		table.insert(all, keeperBoxGroup(key))
	end
	for _, name in all do
		if name ~= "Default" and not PhysicsService:IsCollisionGroupRegistered(name) then
			PhysicsService:RegisterCollisionGroup(name)
		end
	end

	local function onlyCollidesWith(wallGroup: string, target: string)
		for _, other in all do
			PhysicsService:CollisionGroupSetCollidable(wallGroup, other, other == target)
		end
	end
	onlyCollidesWith(G.HalfLine, G.Restricted)
	for _, key in Config.TEAM_ORDER do
		onlyCollidesWith(keeperBoxGroup(key), keeperGroup(key))
	end

	-- 스페셜 슛 공은 모든 선수를 통과한다 (사격/포탄 공으로만 궤적 변경)
	for _, playerGroup in { G.Restricted, G.Free, keeperGroup("Alpha"), keeperGroup("Bravo") } do
		PhysicsService:CollisionGroupSetCollidable(G.SpecialBall, playerGroup, false)
	end
end

local function wall(parent: Instance, group: string, size: Vector3, position: Vector3, visible: boolean)
	local p = Instance.new("Part")
	p.Name = group
	p.Anchored = true
	p.Size = size
	p.Position = position
	p.CanQuery = false
	p.CanTouch = false
	p.CollisionGroup = group
	if visible then
		p.Material = Enum.Material.ForceField
		p.Color = Color3.fromRGB(255, 220, 120)
		p.Transparency = 0.6
	else
		p.Transparency = 1
	end
	p.Parent = parent
end

local function buildWalls(field: Folder)
	local folder = Instance.new("Folder")
	folder.Name = "ZoneWalls"
	folder.Parent = field

	wall(folder, ZoneService.Groups.HalfLine, Vector3.new(2, WH, W), Vector3.new(0, WH / 2, 0), true)

	local depth, width = Config.KEEPER_BOX_DEPTH, Config.KEEPER_BOX_WIDTH
	for _, key in Config.TEAM_ORDER do
		local side = Config.Teams[key].Side
		local group = keeperBoxGroup(key)
		wall(folder, group, Vector3.new(1, WH, width), Vector3.new(side * (L / 2 - depth), WH / 2, 0), false)
		for _, zSign in { -1, 1 } do
			wall(
				folder,
				group,
				Vector3.new(depth, WH, 1),
				Vector3.new(side * (L / 2 - depth / 2), WH / 2, zSign * width / 2),
				false
			)
		end
	end
end

local function getState(player: Player)
	local entry = states[player]
	if not entry then
		entry = { state = "Locked" :: ZoneState, expiry = 0 }
		states[player] = entry
	end
	return entry
end

local function desiredGroup(player: Player, key: string): string
	if PlayerService.classOf(player) == "Goalkeeper" then
		return keeperGroup(key)
	end
	if getState(player).state == "Locked" then
		return ZoneService.Groups.Restricted
	end
	return ZoneService.Groups.Free
end

local function applyGroup(character: Model, group: string)
	local current = character:GetAttribute("ZoneGroup")
	if current == group then
		return
	end
	if current == nil then
		-- 나중에 붙는 액세서리 등에도 같은 그룹을 적용
		character.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("BasePart") then
				descendant.CollisionGroup = character:GetAttribute("ZoneGroup") or "Default"
			end
		end)
	end
	character:SetAttribute("ZoneGroup", group)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = group
		end
	end
end

local function step()
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local key = PlayerService.teamKeyOf(player)
		if character and root and key then
			local side = Config.Teams[key].Side
			-- 자기 진영 쪽으로 얼마나 들어와 있는지 (음수면 적진)
			local depth = root.Position.X * side
			local entry = getState(player)

			if PlayerService.classOf(player) == "Goalkeeper" then
				entry.state = "Locked"
			elseif entry.state == "Ready" then
				if depth < 0 then
					entry.state = "Crossed"
				elseif now > entry.expiry and depth > RETURN_DEPTH then
					entry.state = "Locked"
				end
			elseif entry.state == "Crossed" then
				if depth > RETURN_DEPTH then
					entry.state = "Locked"
				end
			elseif depth < -ILLEGAL_DEPTH then
				character:PivotTo(root.CFrame.Rotation + Vector3.new(side * 6, root.Position.Y, root.Position.Z))
			end

			player:SetAttribute("ZoneState", entry.state)
			applyGroup(character, desiredGroup(player, key))
		end
	end
end

function ZoneService.init(field: Folder)
	registerGroups()
	buildWalls(field)
	RunService.Heartbeat:Connect(step)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
end

-- 킥 판정에서 호출: 자기 진영에서 적 방향으로 공을 찼으면 하프라인 통과 허용
function ZoneService.onKick(player: Player, kickDirection: Vector3)
	local key = PlayerService.teamKeyOf(player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not key or not root or PlayerService.classOf(player) == "Goalkeeper" then
		return
	end
	local side = Config.Teams[key].Side
	local inOwnHalf = root.Position.X * side > 0
	local towardEnemy = kickDirection.X * side < 0
	local entry = getState(player)
	if inOwnHalf and towardEnemy and entry.state ~= "Crossed" then
		entry.state = "Ready"
		entry.expiry = os.clock() + Config.CROSS_WINDOW
		player:SetAttribute("ZoneState", "Ready")
		player:SetAttribute("CrossExpiry", workspace:GetServerTimeNow() + Config.CROSS_WINDOW)
	end
end

-- 킥오프 때 모두 자기 진영에 묶는다
function ZoneService.resetAll()
	for _, entry in states do
		entry.state = "Locked"
	end
end

return ZoneService
