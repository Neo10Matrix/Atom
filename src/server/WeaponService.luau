-- 무기: 누구나 소총·저격총·로켓탄을 쓸 수 있다
-- * 사람은 맞지 않는다. 총알과 폭발은 선수 몸을 통과하고, 축구공·셔틀콕의 궤적만 바꾼다.
-- * 소총·저격총은 즉시 명중(히트스캔), 로켓탄은 날아가다가 무언가에 닿거나 사거리 끝에서 터진다.
-- * 쏘는 위치는 서버가 캐릭터 머리에서 정하고, 클라이언트는 조준 지점만 보낸다. 쿨다운도 서버가 검사한다.
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local BallService = require(script.Parent.BallService)
local PlayerService = require(script.Parent.PlayerService)
local ShuttleService = require(script.Parent.ShuttleService)
local WarService = require(script.Parent.WarService)

type Actor = PlayerService.Actor

-- 클라이언트/서버 시간 차이로 정상 사격이 거부되지 않도록 쿨다운을 조금 느슨하게 검사
local COOLDOWN_LENIENCY = 0.9
-- 로켓이 이 거리 안으로 공에 다가가면 닿지 않아도 터진다 (근접 신관)
local ROCKET_FUSE = 3

local TRACER_COLORS = {
	Rifle = Color3.fromRGB(255, 220, 120),
	Sniper = Color3.fromRGB(140, 220, 255),
}

type Rocket = {
	part: Part,
	shooter: Actor,
	direction: Vector3,
	travelled: number,
	exclude: { Instance },
}

local WeaponService = {}

local net: Folder
local effects: Folder
local lastFire: { [Actor]: { [string]: number } } = {}
local rockets: { Rocket } = {}

-- 총알은 선수 몸을 통과한다: 모든 선수 캐릭터를 레이캐스트에서 뺀다
local function characterList(): { Instance }
	local list = {}
	for _, actor in PlayerService.allActors() do
		local character = PlayerService.characterOf(actor)
		if character then
			table.insert(list, character)
		end
	end
	return list
end

local function cast(origin: Vector3, offset: Vector3, exclude: { Instance }): RaycastResult?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	return workspace:Raycast(origin, offset, params)
end

-- 맞은 파트가 공이면 궤적을 바꾼다 (전쟁 모드 공 / 축구공 / 셔틀콕)
local function hitBall(part: BasePart, impulse: Vector3, shooter: Actor)
	if part:GetAttribute("WarBall") then
		WarService.push(part, impulse, shooter)
	elseif part.Name == "Ball" then
		BallService.push(part :: Part, impulse, shooter)
	elseif part.Name == "Shuttle" then
		ShuttleService.push(part, impulse)
	end
end

local function tracer(from: Vector3, to: Vector3, color: Color3, width: number)
	local length = (to - from).Magnitude
	if length < 0.1 then
		return
	end
	local beam = Instance.new("Part")
	beam.Name = "Tracer"
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.Material = Enum.Material.Neon
	beam.Color = color
	beam.Size = Vector3.new(width, width, length)
	beam.CFrame = CFrame.lookAt((from + to) / 2, to)
	beam.Parent = effects
	Debris:AddItem(beam, 0.08)
end

local function shoot(shooter: Actor, key: string, origin: Vector3, direction: Vector3)
	local weapon = Config.Weapons[key]
	local result = cast(origin, direction * weapon.Range, characterList())
	local hitPosition = if result then result.Position else origin + direction * weapon.Range
	tracer(origin, hitPosition, TRACER_COLORS[key], if key == "Sniper" then 0.35 else 0.15)
	if result then
		local push = (direction + Vector3.new(0, weapon.Lift or 0, 0)).Unit * weapon.Push
		hitBall(result.Instance, push, shooter)
	end
end

-- 폭발·근접 신관이 노리는 모든 공
local function allBalls(): { BasePart }
	local targets: { BasePart } = {}
	for _, ball in BallService.getBalls() do
		table.insert(targets, ball)
	end
	for _, cork in ShuttleService.getActive() do
		table.insert(targets, cork)
	end
	for _, part in WarService.getParts() do
		table.insert(targets, part)
	end
	return targets
end

local function explode(rocket: Rocket, position: Vector3)
	local weapon = Config.Weapons.Rocket
	rocket.part:Destroy()

	-- 보이기만 하는 폭발 (선수는 밀리거나 다치지 않는다)
	local blast = Instance.new("Explosion")
	blast.Position = position
	blast.BlastRadius = weapon.Radius
	blast.BlastPressure = 0
	blast.DestroyJointRadiusPercent = 0
	blast.Parent = effects

	for _, part in allBalls() do
		local offset = part.Position - position
		local distance = offset.Magnitude
		if distance < weapon.Radius then
			local away = if distance > 1e-3 then offset.Unit else Vector3.yAxis
			local strength = weapon.Push * (1 - distance / weapon.Radius)
			-- 바깥쪽 + 살짝 위로 띄운다
			hitBall(part, (away + Vector3.new(0, 0.4, 0)).Unit * strength, rocket.shooter)
		end
	end
end

local function launch(shooter: Actor, origin: Vector3, direction: Vector3, exclude: { Instance })
	local part = Instance.new("Part")
	part.Name = "Rocket"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Size = Vector3.new(0.7, 0.7, 2.4)
	part.Color = Color3.fromRGB(80, 90, 60)
	part.CFrame = CFrame.lookAt(origin, origin + direction)
	local fire = Instance.new("Fire")
	fire.Size = 2
	fire.Heat = 0
	fire.Parent = part
	part.Parent = effects
	table.insert(rockets, {
		part = part,
		shooter = shooter,
		direction = direction,
		travelled = 0,
		exclude = exclude,
	})
end

local function nearBall(position: Vector3): boolean
	for _, ball in allBalls() do
		if (ball.Position - position).Magnitude < ROCKET_FUSE + ball.Size.X / 2 then
			return true
		end
	end
	return false
end

local function stepRockets(dt: number)
	local weapon = Config.Weapons.Rocket
	for i = #rockets, 1, -1 do
		local rocket = rockets[i]
		local from = rocket.part.Position
		local move = rocket.direction * weapon.Speed * dt
		local result = cast(from, move, rocket.exclude)
		if result then
			table.remove(rockets, i)
			explode(rocket, result.Position)
		else
			local to = from + move
			rocket.travelled += move.Magnitude
			if rocket.travelled >= weapon.Range or nearBall(to) then
				table.remove(rockets, i)
				explode(rocket, to)
			else
				rocket.part.CFrame = CFrame.lookAt(to, to + rocket.direction)
			end
		end
	end
end

-- 사격 (플레이어는 원격 이벤트로 조준 지점을 보낸다)
function WeaponService.fire(shooter: Actor, key: unknown, target: unknown)
	if net:GetAttribute("Phase") ~= "Playing" then
		return
	end
	if typeof(key) ~= "string" or not Config.Weapons[key :: string] or typeof(target) ~= "Vector3" then
		return
	end
	local weaponKey = key :: string
	local aim = target :: Vector3
	if aim ~= aim then -- NaN
		return
	end
	local character = PlayerService.characterOf(shooter)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local head = character and character:FindFirstChild("Head") :: BasePart?
	if not character or not humanoid or not head or humanoid.Health <= 0 then
		return
	end

	local now = os.clock()
	local times = lastFire[shooter]
	if not times then
		times = {}
		lastFire[shooter] = times
	end
	local last = times[weaponKey]
	if last and now - last < Config.Weapons[weaponKey].Cooldown * COOLDOWN_LENIENCY then
		return
	end

	local origin = head.Position
	local offset = aim - origin
	if offset.Magnitude < 1e-3 then
		return
	end
	times[weaponKey] = now
	local direction = offset.Unit
	if weaponKey == "Rocket" then
		launch(shooter, origin + direction * 2, direction, characterList())
	else
		shoot(shooter, weaponKey, origin, direction)
	end
end

function WeaponService.init(field: Folder, netFolder: Folder)
	net = netFolder
	effects = Instance.new("Folder")
	effects.Name = "Effects"
	effects.Parent = field

	local fireEvent = net:WaitForChild("Fire") :: RemoteEvent
	fireEvent.OnServerEvent:Connect(WeaponService.fire)
	Players.PlayerRemoving:Connect(function(player)
		lastFire[player] = nil
	end)
	RunService.Heartbeat:Connect(stepRockets)
end

return WeaponService
