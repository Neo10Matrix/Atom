-- 화면 UI: 점수판, 타이머, 안내 메시지, 킥 파워 게이지, 병과 선택
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local player = Players.LocalPlayer
local net = ReplicatedStorage:WaitForChild(Config.NET_FOLDER) :: Folder

local OLIVE = Color3.fromRGB(45, 52, 32)
local KHAKI = Color3.fromRGB(215, 200, 150)

local HUD = {}

local chargeFill: Frame
local chargeFrame: Frame
local abilityLabel: TextLabel

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

	-- 병과 선택 + 조작 안내
	local panel = make("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -10),
		Size = UDim2.new(0, 260, 0, 134),
		BackgroundColor3 = OLIVE,
		BackgroundTransparency = 0.2,
		Parent = gui,
	}, { corner(8) })
	local classButtons: { [string]: TextButton } = {}
	for i, key in Config.CLASS_ORDER do
		local button = make("TextButton", {
			Position = UDim2.new((i - 1) / #Config.CLASS_ORDER, 6, 0, 6),
			Size = UDim2.new(1 / #Config.CLASS_ORDER, -12, 0, 28),
			Text = Config.Classes[key].Name,
			Font = Enum.Font.GothamBold,
			TextScaled = true,
			TextColor3 = Color3.new(1, 1, 1),
			Parent = panel,
		}, { corner(6) })
		button.Activated:Connect(function()
			(net:WaitForChild("ChooseClass") :: RemoteEvent):FireServer(key)
		end)
		classButtons[key] = button
	end
	local classInfo = label({
		Position = UDim2.new(0, 8, 0, 38),
		Size = UDim2.new(1, -16, 0, 16),
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	})
	label({
		Position = UDim2.new(0, 8, 0, 58),
		Size = UDim2.new(1, -16, 0, 30),
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = "E 길게: 킥  |  Q: 돌격\n클릭/F: 병과 스킬 (마우스로 조준)",
		Parent = panel,
	})
	abilityLabel = label({
		Position = UDim2.new(0, 8, 0, 90),
		Size = UDim2.new(1, -16, 0, 16),
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "스킬 준비 완료",
		Parent = panel,
	})

	local zoneLabel = label({
		Position = UDim2.new(0, 8, 0, 110),
		Size = UDim2.new(1, -16, 0, 16),
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	})
	RunService.Heartbeat:Connect(function()
		local class = player:GetAttribute("Class")
		local zone = player:GetAttribute("ZoneState")
		if class == "Goalkeeper" then
			zoneLabel.Text = "골키퍼 구역 사수"
			zoneLabel.TextColor3 = KHAKI
		elseif zone == "Ready" then
			local remaining = (player:GetAttribute("CrossExpiry") or 0) - workspace:GetServerTimeNow()
			zoneLabel.Text = string.format("돌파 허가! 하프라인 통과 가능 (%d초)", math.max(0, math.ceil(remaining)))
			zoneLabel.TextColor3 = Color3.fromRGB(255, 220, 120)
		elseif zone == "Crossed" then
			zoneLabel.Text = "적진 침투 중 — 복귀하면 다시 수비"
			zoneLabel.TextColor3 = Color3.fromRGB(255, 140, 110)
		else
			zoneLabel.Text = "자기 진영 사수 (공을 적진으로 차면 돌파)"
			zoneLabel.TextColor3 = KHAKI
		end
	end)

	local function refreshClass()
		local current = player:GetAttribute("Class") or Config.DEFAULT_CLASS
		for key, button in classButtons do
			button.BackgroundColor3 = if key == current then Color3.fromRGB(120, 140, 70) else Color3.fromRGB(70, 75, 55)
		end
		classInfo.Text = Config.Classes[current].Description
	end
	player:GetAttributeChangedSignal("Class"):Connect(refreshClass)
	refreshClass()

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

function HUD.setCharge(alpha: number)
	chargeFrame.Visible = alpha > 0
	chargeFill.Size = UDim2.new(alpha, 0, 1, 0)
end

function HUD.setAbilityCooldown(remaining: number)
	abilityLabel.Text = if remaining > 0 then string.format("스킬 재장전 %.1f초", remaining) else "스킬 준비 완료"
end

return HUD
