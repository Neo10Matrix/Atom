-- 입력: 킥(차징), 병과 스킬(사격/포격 조준), 돌격 대시
local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)

local player = Players.LocalPlayer
local net = ReplicatedStorage:WaitForChild(Config.NET_FOLDER) :: Folder
local kickEvent = net:WaitForChild("Kick") :: RemoteEvent
local abilityEvent = net:WaitForChild("Ability") :: RemoteEvent

local Controls = {}

local hud

local chargeStart: number? = nil
local lastAbility = -math.huge
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

local function abilityCooldown(): number
	local class = player:GetAttribute("Class") or Config.DEFAULT_CLASS
	return Config.Classes[class].Cooldown
end

-- 마우스 위치(터치/패드는 화면 중앙) 기준으로 월드 조준 지점을 구한다
local function aimPoint(inputObject: InputObject): Vector3
	local camera = workspace.CurrentCamera
	local screenPoint = if inputObject.UserInputType == Enum.UserInputType.MouseButton1
			or inputObject.UserInputType == Enum.UserInputType.Keyboard
		then UserInputService:GetMouseLocation()
		else camera.ViewportSize / 2
	local ray = camera:ViewportPointToRay(screenPoint.X, screenPoint.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: Instance }
	local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
	return if result then result.Position else ray.Origin + ray.Direction * 300
end

local function onKick(_, inputState: Enum.UserInputState)
	if inputState == Enum.UserInputState.Begin then
		chargeStart = os.clock()
	elseif chargeStart then
		local power = math.clamp((os.clock() - chargeStart) / Config.MAX_CHARGE_TIME, 0, 1)
		chargeStart = nil
		hud.setCharge(0)
		if inputState == Enum.UserInputState.End then
			kickEvent:FireServer(power)
		end
	end
	return Enum.ContextActionResult.Sink
end

local function onAbility(_, inputState: Enum.UserInputState, inputObject: InputObject)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	local now = os.clock()
	if now - lastAbility < abilityCooldown() or not aliveCharacter() then
		return Enum.ContextActionResult.Pass
	end
	if net:GetAttribute("Phase") ~= "Playing" then
		return Enum.ContextActionResult.Pass
	end
	lastAbility = now
	abilityEvent:FireServer(aimPoint(inputObject))
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
	ContextActionService:BindAction(
		"ArmyAbility",
		onAbility,
		true,
		Enum.UserInputType.MouseButton1,
		Enum.KeyCode.F,
		Enum.KeyCode.ButtonR1
	)
	ContextActionService:SetTitle("ArmyAbility", "스킬")
	ContextActionService:BindAction("ArmyDash", onDash, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonX)
	ContextActionService:SetTitle("ArmyDash", "돌격")

	RunService.RenderStepped:Connect(function()
		if chargeStart then
			hud.setCharge(math.clamp((os.clock() - chargeStart) / Config.MAX_CHARGE_TIME, 0, 1))
		end
		hud.setAbilityCooldown(math.max(0, abilityCooldown() - (os.clock() - lastAbility)))
	end)
end

return Controls
