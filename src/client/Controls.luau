-- 입력: 킥(차징), 돌격 대시, 무기 (바꾸기·사격)
-- 배드민턴 헤딩은 키 입력 없이 머리에 셔틀콕이 닿으면 서버가 처리한다
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
local fireEvent = net:WaitForChild("Fire") :: RemoteEvent

local Controls = {}

local hud

local chargeStart: number? = nil
local lastDash = -math.huge
-- 무기: 지금 고른 무기와 무기별 마지막 사격 시각 (서버도 쿨다운을 다시 검사한다)
local weaponIndex = 1
local lastFire: { [string]: number } = {}
local AIM_DISTANCE = 500

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
	if (player:GetAttribute("SoccerLockUntil") or 0) > workspace:GetServerTimeNow() then
		return "헤딩 직후에는 축구공을 찰 수 없어요"
	end
	if player:GetAttribute("Dribbling") then
		return nil
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

local function currentWeapon(): string
	return Config.WEAPON_ORDER[weaponIndex]
end

local function selectWeapon(index: number)
	weaponIndex = index
	ContextActionService:SetTitle("ArmyFire", Config.Weapons[currentWeapon()].Name)
end

-- 조준 지점: 마우스는 커서 위치, 터치 버튼·게임패드는 화면 가운데
local function aimPoint(useMouse: boolean): Vector3
	local camera = workspace.CurrentCamera
	local screen = if useMouse then UserInputService:GetMouseLocation() else camera.ViewportSize / 2
	local ray = camera:ViewportPointToRay(screen.X, screen.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: Instance }
	local result = workspace:Raycast(ray.Origin, ray.Direction * AIM_DISTANCE, params)
	return if result then result.Position else ray.Origin + ray.Direction * AIM_DISTANCE
end

local function onFire(_, inputState: Enum.UserInputState, input: InputObject)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	local key = currentWeapon()
	local weapon = Config.Weapons[key]
	local humanoid = aliveCharacter()
	if not humanoid then
		return Enum.ContextActionResult.Pass
	end
	if net:GetAttribute("Phase") ~= "Playing" then
		hud.flash("킥오프 전에는 쏠 수 없어요")
		return Enum.ContextActionResult.Pass
	end
	local now = os.clock()
	local remaining = weapon.Cooldown - (now - (lastFire[key] or -math.huge))
	if remaining > 0 then
		hud.flash(string.format("%s 재장전 중 (%.1f초)", weapon.Name, remaining))
		return Enum.ContextActionResult.Sink
	end
	lastFire[key] = now
	fireEvent:FireServer(key, aimPoint(input.UserInputType == Enum.UserInputType.MouseButton1))
	return Enum.ContextActionResult.Sink
end

local WEAPON_KEYS = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
}

local function onSwitch(_, inputState: Enum.UserInputState, input: InputObject)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	selectWeapon(WEAPON_KEYS[input.KeyCode] or weaponIndex % #Config.WEAPON_ORDER + 1)
	return Enum.ContextActionResult.Sink
end

function Controls.init(hudModule)
	hud = hudModule

	ContextActionService:BindAction("ArmyKick", onKick, true, Enum.KeyCode.E, Enum.KeyCode.ButtonR2)
	ContextActionService:SetTitle("ArmyKick", "킥")
	ContextActionService:BindAction("ArmyDash", onDash, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonX)
	ContextActionService:SetTitle("ArmyDash", "돌격")
	-- 사격: 왼쪽 클릭 (마우스 커서 쪽), 게임패드 R1·터치 버튼은 화면 가운데로
	ContextActionService:BindAction("ArmyFire", onFire, true, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR1)
	-- 무기 바꾸기: 1/2/3 으로 바로 고르거나 R(게임패드 Y, 터치 버튼)로 다음 무기
	ContextActionService:BindAction(
		"ArmySwitch",
		onSwitch,
		true,
		Enum.KeyCode.R,
		Enum.KeyCode.ButtonY,
		Enum.KeyCode.One,
		Enum.KeyCode.Two,
		Enum.KeyCode.Three
	)
	ContextActionService:SetTitle("ArmySwitch", "무기")
	selectWeapon(1)

	RunService.RenderStepped:Connect(function()
		if chargeStart then
			hud.setCharge(math.clamp((os.clock() - chargeStart) / Config.MAX_CHARGE_TIME, 0, 1))
		end
		local key = currentWeapon()
		local weapon = Config.Weapons[key]
		local ready = math.clamp((os.clock() - (lastFire[key] or -math.huge)) / weapon.Cooldown, 0, 1)
		hud.setWeapon(weapon.Name, weaponIndex, ready)
	end)
end

return Controls
