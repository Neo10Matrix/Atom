-- 테스트용 봇: 킥오프 때마다 각 팀을 BOT_TEAM_SIZE 명까지 채운다 (실제 플레이어가 오면 그만큼 빠짐)
-- 봇 AI (0.1초마다):
--   1. 셔틀콕이 우리 진영에 떨어질 것 같으면 가장 가까운 봇이 달려가서 점프 헤딩 (상대 쪽을 보고)
--   2. 축구공을 드리블 중이면 상대 골대로 몰고 가서 가까워지면 슛
--   3. 우리 팀이 갖지 않은 축구공은 가장 가까운 봇이 잡으러 감
--   4. 나머지는 수비 위치로
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local BallService = require(script.Parent.BallService)
local PlayerService = require(script.Parent.PlayerService)
local ShuttleService = require(script.Parent.ShuttleService)

local L = Config.FIELD_LENGTH
local W = Config.FIELD_WIDTH
local THINK_INTERVAL = 0.1
local SHOOT_DISTANCE = L * 0.3 -- 상대 골대와 이만큼 가까워지면 슛
local HEAD_HEIGHT = 6 -- 셔틀콕을 받을 높이 (지면 기준)

local BotService = {}

local folder: Folder
local botCount = 0

local function sideOf(key: string): number
	return Config.Teams[key].Side
end

-- 셔틀콕이 머리 높이까지 내려오는 지점 예측 (줄어든 중력 + 수평 공기 저항)
local function predictLanding(cork: Part): Vector3?
	local p = cork.Position
	local v = cork.AssemblyLinearVelocity
	local g = workspace.Gravity * Config.SHUTTLE_GRAVITY_SCALE
	local drop = p.Y - HEAD_HEIGHT
	local disc = v.Y * v.Y + 2 * g * drop
	if disc < 0 then
		return nil
	end
	local t = math.max(0, (v.Y + math.sqrt(disc)) / g)
	local k = Config.SHUTTLE_DRAG
	local travel = (1 - math.exp(-k * t)) / k
	return Vector3.new(p.X + v.X * travel, 0, p.Z + v.Z * travel)
end

local function rootOf(bot: Model): BasePart?
	return bot:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- 같은 팀 봇 중 position 에 가장 가까운 봇
local function closestBot(key: string, position: Vector3): Model?
	local best, bestDistance = nil, math.huge
	for _, bot in PlayerService.botsOf(key) do
		local root = rootOf(bot)
		if root then
			local d = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(position.X, 0, position.Z)).Magnitude
			if d < bestDistance then
				best, bestDistance = bot, d
			end
		end
	end
	return best
end

local function face(root: BasePart, direction: Vector3)
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude > 1e-3 then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
	end
end

local function think(bot: Model, index: number)
	local key = bot:GetAttribute("TeamKey") :: string
	local humanoid = bot:FindFirstChildOfClass("Humanoid")
	local root = rootOf(bot)
	if not key or not humanoid or not root then
		return
	end
	local side = sideOf(key)
	local toEnemy = Vector3.new(-side, 0, 0)

	-- 1. 우리 진영에 떨어지는 셔틀콕
	for _, cork in ShuttleService.getActive() do
		local landing = predictLanding(cork)
		if landing and landing.X * side > 0 and math.abs(landing.Z) < W / 2 and closestBot(key, landing) == bot then
			humanoid:MoveTo(landing)
			local offset = cork.Position - root.Position
			local horizontal = Vector3.new(offset.X, 0, offset.Z).Magnitude
			if horizontal < Config.SHUTTLE_DIAMETER / 2 + 2 and offset.Y > 2 and offset.Y < 14 and cork.AssemblyLinearVelocity.Y < 0 then
				face(root, toEnemy)
				humanoid.Jump = true
			end
			return
		end
	end

	-- 2. 드리블 중이면 상대 골대로
	local enemyGoal = Vector3.new(-side * L / 2, root.Position.Y, 0)
	for _, ball in BallService.getBalls() do
		if BallService.ownerOf(ball) == bot then
			if (enemyGoal - root.Position).Magnitude < SHOOT_DISTANCE then
				face(root, enemyGoal - root.Position)
				BallService.kick(bot, 0.6 + math.random() * 0.3)
			else
				humanoid:MoveTo(enemyGoal)
			end
			return
		end
	end

	-- 3. 우리 팀이 갖지 않은 가장 가까운 축구공을 잡으러
	local target: Part? = nil
	local targetDistance = math.huge
	for _, ball in BallService.getBalls() do
		local holder = BallService.ownerOf(ball)
		local holderKey = holder and PlayerService.teamKeyOf(holder)
		local d = (ball.Position - root.Position).Magnitude
		if holderKey ~= key and d < targetDistance then
			target, targetDistance = ball, d
		end
	end
	if target and closestBot(key, target.Position) == bot then
		humanoid:MoveTo(target.Position)
		return
	end

	-- 4. 수비 위치
	local teamBots = PlayerService.botsOf(key)
	local z = (index - (#teamBots + 1) / 2) * (W / (#teamBots + 1))
	humanoid:MoveTo(Vector3.new(side * L / 4, root.Position.Y, z))
end

-- 블록으로 만든 단순한 봇 (아바타 파일을 불러오지 않아서 게시 전 Studio 에서도 확실히 생성됨)
local function buildBot(color: Color3): Model
	local bot = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Transparency = 1
	root.CanCollide = false
	root.Parent = bot
	bot.PrimaryPart = root

	local function piece(name: string, size: Vector3, offset: Vector3, partColor: Color3, collide: boolean)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = partColor
		p.Material = Enum.Material.SmoothPlastic
		p.CanCollide = collide
		p.CFrame = root.CFrame + offset
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = p
		weld.Parent = p
		p.Parent = bot
	end
	piece("UpperTorso", Vector3.new(2, 2, 1), Vector3.zero, color, true)
	piece("Head", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 1.6, 0), Color3.fromRGB(240, 200, 160), true)
	-- 다리: 공에 닿는 판정(드리블)은 하되 충돌은 하지 않음 (HipHeight 로 서 있음)
	piece("Legs", Vector3.new(2, 2, 1), Vector3.new(0, -2, 0), Color3.fromRGB(60, 60, 50), false)

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = 2
	humanoid.Parent = bot
	return bot
end

local function spawnBot(key: string)
	botCount += 1
	local info = Config.Teams[key]
	local bot = buildBot(info.Color.Color)
	bot.Name = string.format("%s 봇 %d", info.Name, botCount)
	local humanoid = bot:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayName = bot.Name
	bot:PivotTo(CFrame.new(info.Side * L / 4, 4, (math.random() - 0.5) * W * 0.6))
	bot.Parent = folder
	PlayerService.registerBot(bot, key)
	local root = rootOf(bot)
	if root then
		root:SetNetworkOwner(nil)
	end
end

local function removeBot(bot: Model)
	PlayerService.unregisterBot(bot)
	bot:Destroy()
end

-- 각 팀을 BOT_TEAM_SIZE 명까지 봇으로 채운다 (실제 플레이어 수만큼 봇이 빠짐)
function BotService.fill()
	for _, key in Config.TEAM_ORDER do
		local real = #PlayerService.teams[key]:GetPlayers()
		local want = if Config.BOTS_ENABLED then math.max(0, Config.BOT_TEAM_SIZE - real) else 0
		local current = PlayerService.botsOf(key)
		for _ = #current + 1, want do
			spawnBot(key)
		end
		for i = #current, want + 1, -1 do
			removeBot(current[i])
		end
	end
end

function BotService.init()
	folder = Instance.new("Folder")
	folder.Name = "Bots"
	folder.Parent = workspace

	task.spawn(function()
		while true do
			task.wait(THINK_INTERVAL)
			if not PlayerService.isFrozen() then
				for _, key in Config.TEAM_ORDER do
					for index, bot in PlayerService.botsOf(key) do
						local ok, err = pcall(think, bot, index)
						if not ok then
							warn("봇 AI 오류:", err)
						end
					end
				end
			end
		end
	end)
end

return BotService
