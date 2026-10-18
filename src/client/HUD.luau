-- 화면 UI: 점수판, 타이머, 안내 메시지, 킥 파워 게이지, 종목 선택
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local player = Players.LocalPlayer
local net = ReplicatedStorage:WaitForChild(Config.NET_FOLDER) :: Folder

local OLIVE = Color3.fromRGB(45, 52, 32)
local KHAKI = Color3.fromRGB(215, 200, 150)

local HUD = {}

local chargeFill: Frame
local hintLabel: TextLabel
local hintToken = 0
local chargeFrame: Frame

local function make(className: string, props: { [string]: any }, children: { Instance }?): any
	local instance = Instance.new(className)
	for key, value in props do
		if key ~= "Parent" then
			(instance :: any)[key] = value
		end
	end
	for _, child in children or {} do
		child.Parent = instance
	end
	instance.Parent = props.Parent
	return instance
end

local function corner(radius: number): UICorner
	return make("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function label(props: { [string]: any }): TextLabel
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Font = props.Font or Enum.Font.GothamBold
	props.TextColor3 = props.TextColor3 or KHAKI
	props.TextScaled = true
	return make("TextLabel", props)
end

local function formatTime(seconds: number): string
	return string.format("%02d:%02d", seconds // 60, seconds % 60)
end

local PHASE_TEXT = {
	Countdown = "킥오프 준비",
	Playing = "작전 진행 중",
	Goal = "골! 재정비 중",
	Ended = "경기 종료",
}

function HUD.init()
	local gui = make("ScreenGui", {
		Name = "ArmySoccerHUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		Parent = player:WaitForChild("PlayerGui"),
	})

	-- 점수판
	local board = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.new(0.9, 0, 0, 56),
		BackgroundColor3 = OLIVE,
		BackgroundTransparency = 0.1,
		Parent = gui,
	}, { corner(10), make("UISizeConstraint", { MaxSize = Vector2.new(460, 56) }) })
	local alphaLabel = label({
		Position = UDim2.new(0, 10, 0, 6),
		Size = UDim2.new(0.38, -10, 0, 30),
		TextColor3 = Config.Teams.Alpha.Color.Color:Lerp(Color3.new(1, 1, 1), 0.35),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = board,
	})
	local timerLabel = label({
		Position = UDim2.new(0.38, 0, 0, 4),
		Size = UDim2.new(0.24, 0, 0, 34),
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.Code,
		Parent = board,
	})
	local bravoLabel = label({
		Position = UDim2.new(0.62, 0, 0, 6),
		Size = UDim2.new(0.38, -10, 0, 30),
		TextColor3 = Config.Teams.Bravo.Color.Color:Lerp(Color3.new(1, 1, 1), 0.35),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = board,
	})
	local phaseLabel = label({
		Position = UDim2.new(0, 0, 0, 38),
		Size = UDim2.new(1, 0, 0, 14),
		Font = Enum.Font.Gotham,
		Parent = board,
	})

	-- 중앙 안내 메시지
	local announcement = label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.32, 0),
		Size = UDim2.new(0.8, 0, 0, 60),
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0.3,
		Visible = false,
		Parent = gui,
	})

	-- 킥 파워 게이지
	chargeFrame = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -110),
		Size = UDim2.new(0, 240, 0, 14),
		BackgroundColor3 = OLIVE,
		Visible = false,
		Parent = gui,
	}, { corner(7) })
	chargeFill = make("Frame", {
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(230, 170, 60),
		Parent = chargeFrame,
	}, { corner(7) })

	-- 짧은 안내 (킥 실패 이유 등)
	hintLabel = label({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -130),
		Size = UDim2.new(0, 320, 0, 24),
		TextColor3 = Color3.fromRGB(255, 230, 150),
		TextStrokeTransparency = 0.4,
		Visible = false,
		Parent = gui,
	})

	-- 종목 선택 + 조작 안내 (선수는 자기 종목의 공 하나만 건드릴 수 있다)
	local panel = make("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -10),
		Size = UDim2.new(0, 280, 0, 96),
		BackgroundColor3 = OLIVE,
		BackgroundTransparency = 0.2,
		Parent = gui,
	}, { corner(8) })
	local sportButtons: { [string]: TextButton } = {}
	local chooseSport = net:WaitForChild("ChooseSport") :: RemoteEvent
	for i, key in Config.SPORT_ORDER do
		local button = make("TextButton", {
			Position = UDim2.new((i - 1) / #Config.SPORT_ORDER, 6, 0, 6),
			Size = UDim2.new(1 / #Config.SPORT_ORDER, -12, 0, 28),
			Text = Config.Sports[key].Name,
			Font = Enum.Font.GothamBold,
			TextScaled = true,
			TextColor3 = Color3.new(1, 1, 1),
			Parent = panel,
		}, { corner(6) })
		button.Activated:Connect(function()
			chooseSport:FireServer(key)
		end)
		sportButtons[key] = button
	end
	local sportInfo = label({
		Position = UDim2.new(0, 8, 0, 40),
		Size = UDim2.new(1, -16, 0, 16),
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	})
	local controlsInfo = label({
		Position = UDim2.new(0, 8, 0, 62),
		Size = UDim2.new(1, -16, 0, 28),
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = panel,
	})

	local function refreshSport()
		local current = player:GetAttribute("Sport") or Config.DEFAULT_SPORT
		for key, button in sportButtons do
			button.BackgroundColor3 = if key == current then Color3.fromRGB(120, 140, 70) else Color3.fromRGB(70, 75, 55)
		end
		sportInfo.Text = Config.Sports[current].Description
		controlsInfo.Text = if current == "Badminton"
			then "점프해서 머리로 헤딩 (팀당 3번까지)\n3번째에 빨간색! 꼭 넘기기 | Q: 돌격"
			else "E 길게 눌렀다 떼기: 킥\nQ: 돌격"
	end
	player:GetAttributeChangedSignal("Sport"):Connect(refreshSport)
	refreshSport()

	local function refreshBoard()
		alphaLabel.Text = string.format("%s  %d", Config.Teams.Alpha.Name, net:GetAttribute("ScoreAlpha") or 0)
		bravoLabel.Text = string.format("%d  %s", net:GetAttribute("ScoreBravo") or 0, Config.Teams.Bravo.Name)
		timerLabel.Text = formatTime(net:GetAttribute("TimeLeft") or 0)
		local phase = net:GetAttribute("Phase")
		if phase == "Waiting" then
			phaseLabel.Text = string.format(
				"병력 집결 중... (%d/%d명)",
				#Players:GetPlayers(),
				net:GetAttribute("MinPlayers") or Config.MIN_PLAYERS
			)
		else
			phaseLabel.Text = PHASE_TEXT[phase] or ""
		end
	end
	net.AttributeChanged:Connect(refreshBoard)
	Players.PlayerAdded:Connect(refreshBoard)
	Players.PlayerRemoving:Connect(function()
		task.defer(refreshBoard)
	end)
	refreshBoard()

	local announceToken = 0
	local announceEvent = net:WaitForChild("Announce") :: RemoteEvent
	announceEvent.OnClientEvent:Connect(function(text: string, duration: number)
		announceToken += 1
		local token = announceToken
		announcement.Text = text
		announcement.Visible = true
		task.delay(duration, function()
			if announceToken == token then
				announcement.Visible = false
			end
		end)
	end)
end

function HUD.flash(text: string)
	hintToken += 1
	local token = hintToken
	hintLabel.Text = text
	hintLabel.Visible = true
	task.delay(1.5, function()
		if hintToken == token then
			hintLabel.Visible = false
		end
	end)
end

function HUD.setCharge(alpha: number)
	chargeFrame.Visible = alpha > 0
	chargeFill.Size = UDim2.new(alpha, 0, 1, 0)
end

return HUD
