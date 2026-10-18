-- 팀 배정, 병과(소총수/전차병) 선택, 헬멧, 리더보드, 킥오프 배치/정지 처리
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")

local Config = require(ReplicatedStorage.Shared.Config)

local DEFAULT_JUMP_HEIGHT = 7.2
local DEFAULT_JUMP_POWER = 50

local PlayerService = {}
PlayerService.teams = {} :: { [string]: Team }

local frozen = false
local rooted: { [Player]: boolean? } = {} -- 골키퍼 스페셜 슛 충전 중

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

function PlayerService.classOf(player: Player): string
	return player:GetAttribute("Class") or Config.DEFAULT_CLASS
end

local function applyMovement(humanoid: Humanoid, player: Player)
	if frozen or rooted[player] then
		humanoid.WalkSpeed = 0
		humanoid.JumpHeight = 0
		humanoid.JumpPower = 0
	else
		humanoid.WalkSpeed = Config.Classes[PlayerService.classOf(player)].WalkSpeed
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
		applyMovement(humanoid, player)
	end

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
	player:SetAttribute("Class", Config.DEFAULT_CLASS)

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local goals = Instance.new("IntValue")
	goals.Name = "골"
	goals.Parent = leaderstats
	leaderstats.Parent = player

	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
end

local function countClass(team: Team, class: string, exclude: Player): number
	local count = 0
	for _, p in team:GetPlayers() do
		if p ~= exclude and PlayerService.classOf(p) == class then
			count += 1
		end
	end
	return count
end

-- 골키퍼 위치: 자기 골대 바로 앞
local function keeperCFrame(side: number): CFrame
	local position = Vector3.new(side * (Config.FIELD_LENGTH / 2 - 6), 4, 0)
	return CFrame.lookAt(position, Vector3.new(0, 4, 0))
end

local function onChooseClass(player: Player, class: unknown)
	if typeof(class) ~= "string" or not Config.Classes[class] or rooted[player] then
		return
	end
	if PlayerService.classOf(player) == class then
		return
	end
	local maxPerTeam = Config.Classes[class].MaxPerTeam
	if maxPerTeam and player.Team and countClass(player.Team, class, player) >= maxPerTeam then
		return
	end
	player:SetAttribute("Class", class)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		applyMovement(humanoid, player)
	end
	-- 골키퍼는 골키퍼 구역 안에서만 움직이므로 바로 골대 앞으로 보낸다
	local key = teamKeyOf(player)
	if class == "Goalkeeper" and character and key then
		character:PivotTo(keeperCFrame(Config.Teams[key].Side))
	end
end

function PlayerService.init(net: Folder)
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
		rooted[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	local chooseClass = net:WaitForChild("ChooseClass") :: RemoteEvent
	chooseClass.OnServerEvent:Connect(onChooseClass)
end

function PlayerService.addGoal(player: Player)
	local leaderstats = player:FindFirstChild("leaderstats")
	local goals = leaderstats and leaderstats:FindFirstChild("골") :: IntValue?
	if goals then
		goals.Value += 1
	end
end

-- 킥오프 대형: 각 팀을 자기 진영에 세로로 정렬
function PlayerService.positionPlayers()
	for _, key in Config.TEAM_ORDER do
		local side = Config.Teams[key].Side
		local members = {}
		for _, player in PlayerService.teams[key]:GetPlayers() do
			local character = player.Character
			if PlayerService.classOf(player) == "Goalkeeper" then
				if character and character:FindFirstChild("HumanoidRootPart") then
					character:PivotTo(keeperCFrame(side))
				end
			else
				table.insert(members, player)
			end
		end
		local spacing = math.min(12, (Config.FIELD_WIDTH - 20) / math.max(#members, 1))
		for i, player in members do
			local character = player.Character
			if character and character:FindFirstChild("HumanoidRootPart") then
				local z = (i - (#members + 1) / 2) * spacing
				local position = Vector3.new(side * Config.FIELD_LENGTH / 4, 4, z)
				character:PivotTo(CFrame.lookAt(position, Vector3.new(0, 4, z)))
			end
		end
	end
end

function PlayerService.setRooted(player: Player, value: boolean)
	rooted[player] = if value then true else nil
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		applyMovement(humanoid, player)
	end
end

function PlayerService.setFrozen(value: boolean)
	frozen = value
	for _, player in Players:GetPlayers() do
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			applyMovement(humanoid, player)
		end
	end
end

return PlayerService
