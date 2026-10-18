-- 입력: 킥(차징), 돌격 대시
-- 배드민턴 헤딩은 키 입력 없이 머리에 셔틀콕이 닿으면 서버가 처리한다
local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local player = Players.LocalPlayer
local net = ReplicatedStorage:WaitForChild(Config.NET_FOLDER) :: Folder
local kickEvent = net:WaitForChild("Kick") :: RemoteEvent

local Controls = {}

local hud

local chargeStart: number? = nil
local lastDash = -math.huge

local function aliveCharacter(): (Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root or humanoid.Health <= 0 then
		return nil, nil
	end
	return humanoid, root
end

-- 킥이 안 되는 이유 (없으면 nil). 서버도 같은 조건을 다시 검사한다
local function kickBlockReason(): string?
	if net:GetAttribute("Phase") ~= "Playing" then
		return "킥오프 전에는 찰 수 없어요"
	end
	if
		player:GetAttribute("Control") == "Shuttle"
		and (player:GetAttribute("ControlUntil") or 0) > workspace:GetServerTimeNow()
	then
		return "헤딩 직후에는 축구공을 찰 수 없어요"
	end
	local _, root = aliveCharacter()
	local field = workspace:FindFirstChild("ArmySoccerField")
	local balls = field and field:FindFirstChild("Balls")
	if not root or not balls then
		return nil
	end
	for _, ball in balls:GetChildren() do
		if ball:IsA("BasePart") and (ball.Position - root.Position).Magnitude <= Config.KICK_RANGE then
			return nil
		end
	end
	return "공에 더 가까이 가세요"
end

local function onKick(_, inputState: Enum.UserInputState)
	if inputState == Enum.UserInputState.Begin then
		chargeStart = os.clock()
	elseif chargeStart then
		local power = math.clamp((os.clock() - chargeStart) / Config.MAX_CHARGE_TIME, 0, 1)
		chargeStart = nil
		hud.setCharge(0)
		if inputState == Enum.UserInputState.End then
			local reason = kickBlockReason()
			if reason then
				hud.flash(reason)
			else
				kickEvent:FireServer(power)
			end
		end
	end
	return Enum.ContextActionResult.Sink
end

local function onDash(_, inputState: Enum.UserInputState)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	local humanoid, root = aliveCharacter()
	local now = os.clock()
	if not humanoid or not root or humanoid.WalkSpeed == 0 or now - lastDash < Config.DASH_COOLDOWN then
		return Enum.ContextActionResult.Sink
	end
	local look = root.CFrame.LookVector
	local flat = Vector2.new(look.X, look.Z)
	if flat.Magnitude < 1e-3 then
		return Enum.ContextActionResult.Sink
	end
	lastDash = now

	local attachment = Instance.new("Attachment")
	attachment.Parent = root
	local velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	velocity.PrimaryTangentAxis = Vector3.xAxis
	velocity.SecondaryTangentAxis = Vector3.zAxis
	velocity.PlaneVelocity = flat.Unit * Config.DASH_SPEED
	velocity.MaxForce = 1e6
	velocity.Parent = root
	Debris:AddItem(velocity, Config.DASH_DURATION)
	Debris:AddItem(attachment, Config.DASH_DURATION)
	return Enum.ContextActionResult.Sink
end

function Controls.init(hudModule)
	hud = hudModule

	ContextActionService:BindAction("ArmyKick", onKick, true, Enum.KeyCode.E, Enum.KeyCode.ButtonR2)
	ContextActionService:SetTitle("ArmyKick", "킥")
	ContextActionService:BindAction("ArmyDash", onDash, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonX)
	ContextActionService:SetTitle("ArmyDash", "돌격")

	RunService.RenderStepped:Connect(function()
		if chargeStart then
			hud.setCharge(math.clamp((os.clock() - chargeStart) / Config.MAX_CHARGE_TIME, 0, 1))
		end
	end)
end

return Controls
