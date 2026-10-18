-- 팀 배정, 종목 선택(축구/배드민턴), 헬멧, 리더보드, 킥오프 배치/정지 처리
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")

local Config = require(ReplicatedStorage.Shared.Config)
local CollisionGroups = require(script.Parent.CollisionGroups)

local DEFAULT_JUMP_HEIGHT = 7.2
local DEFAULT_JUMP_POWER = 50

local PlayerService = {}
PlayerService.teams = {} :: { [string]: Team }

local frozen = false

local function teamKeyOf(player: Player): string?
	return player.Team and player.Team:GetAttribute("Key")
end
PlayerService.teamKeyOf = teamKeyOf

local function smallestTeam(exclude: Player?): Team
	local best: Team? = nil
	local bestCount = math.huge
	for _, key in Config.TEAM_ORDER do
		local team = PlayerService.teams[key]
		local count = 0
		for _, p in team:GetPlayers() do
			if p ~= exclude then
				count += 1
			end
		end
		if count < bestCount then
			best, bestCount = team, count
		end
	end
	return best :: Team
end

function PlayerService.sportOf(player: Player): string
	return player:GetAttribute("Sport") or Config.DEFAULT_SPORT
end

local function applySportGroup(player: Player)
	local character = player.Character
	if character then
		CollisionGroups.applyToCharacter(character, CollisionGroups.Players[PlayerService.sportOf(player)])
	end
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

local function addHelmet(character: Model, team: Team?)
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
	helmet.BrickColor = team and team.TeamColor or BrickColor.new("Earth green")
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

local function onCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
	if humanoid then
		applyMovement(humanoid)
	end
	applySportGroup(player)

	-- 아바타 외형이 로드되면서 머리가 교체되면 먼저 붙인 헬멧이 떨어지므로 로드를 기다린다
	local deadline = os.clock() + 5
	while not player:HasAppearanceLoaded() and os.clock() < deadline do
		task.wait(0.1)
	end
	if player.Character ~= character or not character.Parent then
		return
	end

	-- 군대 복장 통일: 헬멧을 가리는 모자·머리카락 액세서리를 벗긴다
	for _, child in character:GetChildren() do
		if
			child:IsA("Accessory")
			and (child.AccessoryType == Enum.AccessoryType.Hat or child.AccessoryType == Enum.AccessoryType.Hair)
		then
			child:Destroy()
		end
	end
	addHelmet(character, player.Team)
end

local function onPlayerAdded(player: Player)
	player.Team = smallestTeam()
	player:SetAttribute("Sport", Config.DEFAULT_SPORT)

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

local function onChooseSport(player: Player, sport: unknown)
	if typeof(sport) ~= "string" or not Config.Sports[sport] then
		return
	end
	player:SetAttribute("Sport", sport)
	applySportGroup(player)
end

function PlayerService.init(net: Folder)
	CollisionGroups.setup()

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
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	local chooseSport = net:WaitForChild("ChooseSport") :: RemoteEvent
	chooseSport.OnServerEvent:Connect(onChooseSport)
end

function PlayerService.addPoint(player: Player)
	local leaderstats = player:FindFirstChild("leaderstats")
	local goals = leaderstats and leaderstats:FindFirstChild("득점") :: IntValue?
	if goals then
		goals.Value += 1
	end
end

-- 킥오프 대형: 각 팀을 자기 진영에 세로로 정렬
-- 축구 선수는 진영 중간, 배드민턴 선수는 네트 가까이
local SPORT_LINE_X = {
	Soccer = Config.FIELD_LENGTH / 4,
	Badminton = 25,
}

function PlayerService.positionPlayers()
	for _, key in Config.TEAM_ORDER do
		local side = Config.Teams[key].Side
		for _, sport in Config.SPORT_ORDER do
			local members = {}
			for _, player in PlayerService.teams[key]:GetPlayers() do
				if PlayerService.sportOf(player) == sport then
					table.insert(members, player)
				end
			end
			local spacing = math.min(16, (Config.FIELD_WIDTH - 20) / math.max(#members, 1))
			for i, player in members do
				local character = player.Character
				if character and character:FindFirstChild("HumanoidRootPart") then
					local z = (i - (#members + 1) / 2) * spacing
					local position = Vector3.new(side * SPORT_LINE_X[sport], 4, z)
					character:PivotTo(CFrame.lookAt(position, Vector3.new(0, 4, z)))
				end
			end
		end
	end
end

function PlayerService.setFrozen(value: boolean)
	frozen = value
	for _, player in Players:GetPlayers() do
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			applyMovement(humanoid)
		end
	end
end

return PlayerService
