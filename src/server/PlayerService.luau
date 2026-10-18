-- 팀 배정, 헬멧, 리더보드, 킥오프 배치/정지 처리
-- "선수(Actor)"는 실제 플레이어(Player) 또는 봇(캐릭터 Model)이다. 공 판정은 둘을 똑같이 다룬다.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")

local Config = require(ReplicatedStorage.Shared.Config)
local CollisionGroups = require(script.Parent.CollisionGroups)

local DEFAULT_JUMP_HEIGHT = 7.2
local DEFAULT_JUMP_POWER = 50

-- Player 또는 봇 캐릭터 Model
export type Actor = Instance

local PlayerService = {}
PlayerService.teams = {} :: { [string]: Team }

local frozen = false
local bots: { Model } = {}
-- 헤딩한 선수는 이 시각(os.clock)까지 축구공을 잡거나 찰 수 없다
local soccerLockedUntil: { [Actor]: number } = {}

function PlayerService.isBot(actor: Actor): boolean
	return actor:IsA("Model")
end

function PlayerService.characterOf(actor: Actor): Model?
	if actor:IsA("Player") then
		return actor.Character
	end
	return actor :: Model
end

function PlayerService.teamKeyOf(actor: Actor): string?
	if actor:IsA("Player") then
		return actor.Team and actor.Team:GetAttribute("Key")
	end
	return actor:GetAttribute("TeamKey")
end

function PlayerService.nameOf(actor: Actor): string
	if actor:IsA("Player") then
		return actor.DisplayName
	end
	return actor.Name
end

-- 공에 닿은 파트로 선수를 찾는다
function PlayerService.actorFromPart(part: BasePart): Actor?
	local model = part:FindFirstAncestorOfClass("Model")
	if not model then
		return nil
	end
	local player = Players:GetPlayerFromCharacter(model)
	if player then
		return player
	end
	if model:GetAttribute("IsBot") then
		return model
	end
	return nil
end

-- 팀의 모든 선수 (플레이어 + 봇)
function PlayerService.membersOf(key: string): { Actor }
	local members: { Actor } = {}
	for _, player in PlayerService.teams[key]:GetPlayers() do
		table.insert(members, player)
	end
	for _, bot in bots do
		if bot:GetAttribute("TeamKey") == key then
			table.insert(members, bot)
		end
	end
	return members
end

function PlayerService.allActors(): { Actor }
	local actors: { Actor } = {}
	for _, key in Config.TEAM_ORDER do
		for _, actor in PlayerService.membersOf(key) do
			table.insert(actors, actor)
		end
	end
	return actors
end

local function smallestTeam(): Team
	local best: Team? = nil
	local bestCount = math.huge
	for _, key in Config.TEAM_ORDER do
		local team = PlayerService.teams[key]
		local count = #team:GetPlayers()
		if count < bestCount then
			best, bestCount = team, count
		end
	end
	return best :: Team
end

local function applyMovement(humanoid: Humanoid)
	if frozen then
		humanoid.WalkSpeed = 0
		humanoid.JumpHeight = 0
		humanoid.JumpPower = 0
	else
		humanoid.WalkSpeed = Config.WALK_SPEED
		humanoid.JumpHeight = DEFAULT_JUMP_HEIGHT
		humanoid.JumpPower = DEFAULT_JUMP_POWER
	end
end

local function addHelmet(character: Model, key: string?)
	local head = character:WaitForChild("Head", 5) :: BasePart?
	if not head then
		return
	end
	local width = math.min(head.Size.X, head.Size.Z) * 1.45
	local helmet = Instance.new("Part")
	helmet.Name = "ArmyHelmet"
	helmet.Size = Vector3.one
	helmet.CanCollide = false
	helmet.CanQuery = false
	helmet.CanTouch = false
	helmet.Massless = true
	helmet.Material = Enum.Material.Fabric
	helmet.BrickColor = if key then Config.Teams[key].Color else BrickColor.new("Earth green")
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(width, head.Size.Y * 0.75, width)
	mesh.Parent = helmet
	helmet.CFrame = head.CFrame * CFrame.new(0, head.Size.Y * 0.3, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = helmet
	weld.Parent = helmet
	helmet.Parent = character
end

-- 군대 복장 통일: 헬멧을 가리는 모자·머리카락 액세서리를 벗기고 팀 색 헬멧을 씌운다
local function dressUp(character: Model, key: string?)
	for _, child in character:GetChildren() do
		if
			child:IsA("Accessory")
			and (child.AccessoryType == Enum.AccessoryType.Hat or child.AccessoryType == Enum.AccessoryType.Hair)
		then
			child:Destroy()
		end
	end
	addHelmet(character, key)
end

local function onCharacter(player: Player, character: Model)
	CollisionGroups.applyToCharacter(character)
	local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
	if humanoid then
		applyMovement(humanoid)
	end

	-- 아바타 외형이 로드되면서 머리가 교체되면 먼저 붙인 헬멧이 떨어지므로 로드를 기다린다
	local deadline = os.clock() + 5
	while not player:HasAppearanceLoaded() and os.clock() < deadline do
		task.wait(0.1)
	end
	if player.Character ~= character or not character.Parent then
		return
	end
	dressUp(character, PlayerService.teamKeyOf(player))
end

local function onPlayerAdded(player: Player)
	player.Team = smallestTeam()

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local goals = Instance.new("IntValue")
	goals.Name = "득점"
	goals.Parent = leaderstats
	leaderstats.Parent = player

	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
end

function PlayerService.init()
	for _, key in Config.TEAM_ORDER do
		local info = Config.Teams[key]
		local team = Instance.new("Team")
		team.Name = info.Name
		team.TeamColor = info.Color
		team.AutoAssignable = false
		team:SetAttribute("Key", key)
		team.Parent = Teams
		PlayerService.teams[key] = team
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		soccerLockedUntil[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

-- 봇 등록: 팀 지정, 이동 속도, 헬멧
function PlayerService.registerBot(bot: Model, key: string)
	bot:SetAttribute("IsBot", true)
	bot:SetAttribute("TeamKey", key)
	table.insert(bots, bot)
	CollisionGroups.applyToCharacter(bot)
	local humanoid = bot:FindFirstChildOfClass("Humanoid")
	if humanoid then
		applyMovement(humanoid)
	end
	dressUp(bot, key)
end

function PlayerService.unregisterBot(bot: Model)
	local index = table.find(bots, bot)
	if index then
		table.remove(bots, index)
	end
	soccerLockedUntil[bot] = nil
end

function PlayerService.botsOf(key: string): { Model }
	local result = {}
	for _, bot in bots do
		if bot:GetAttribute("TeamKey") == key then
			table.insert(result, bot)
		end
	end
	return result
end

function PlayerService.addPoint(actor: Actor)
	local leaderstats = actor:IsA("Player") and actor:FindFirstChild("leaderstats")
	local goals = leaderstats and leaderstats:FindFirstChild("득점") :: IntValue?
	if goals then
		goals.Value += 1
	end
end

-- 킥오프 대형: 각 팀을 자기 진영에 세로로 정렬
function PlayerService.positionPlayers()
	for _, key in Config.TEAM_ORDER do
		local side = Config.Teams[key].Side
		local members = PlayerService.membersOf(key)
		local spacing = math.min(16, (Config.FIELD_WIDTH - 20) / math.max(#members, 1))
		for i, actor in members do
			local character = PlayerService.characterOf(actor)
			if character and character:FindFirstChild("HumanoidRootPart") then
				local z = (i - (#members + 1) / 2) * spacing
				local position = Vector3.new(side * Config.FIELD_LENGTH / 4, 4, z)
				character:PivotTo(CFrame.lookAt(position, Vector3.new(0, 4, z)))
			end
		end
	end
end

-- 한 사람은 공 두 개를 동시에 다룰 수 없다: 헤딩하면 CONTROL_LOCK_TIME 동안 축구공을 못 잡는다
function PlayerService.lockSoccer(actor: Actor)
	soccerLockedUntil[actor] = os.clock() + Config.CONTROL_LOCK_TIME
	actor:SetAttribute("SoccerLockUntil", workspace:GetServerTimeNow() + Config.CONTROL_LOCK_TIME)
end

function PlayerService.canTouchSoccer(actor: Actor): boolean
	local untilTime = soccerLockedUntil[actor]
	return not untilTime or os.clock() >= untilTime
end

function PlayerService.isFrozen(): boolean
	return frozen
end

function PlayerService.setFrozen(value: boolean)
	frozen = value
	for _, actor in PlayerService.allActors() do
		local character = PlayerService.characterOf(actor)
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			applyMovement(humanoid)
		end
	end
end

return PlayerService
