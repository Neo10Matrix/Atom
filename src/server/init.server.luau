-- 아미사커 서버 진입점
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local BallService = require(script.BallService)
local BotService = require(script.BotService)
local CollisionGroups = require(script.CollisionGroups)
local FieldBuilder = require(script.FieldBuilder)
local MatchService = require(script.MatchService)
local PlayerService = require(script.PlayerService)
local ShuttleService = require(script.ShuttleService)
local WarService = require(script.WarService)
local WeaponService = require(script.WeaponService)

-- 원격 이벤트 + 경기 상태(속성)를 담는 폴더
local net = Instance.new("Folder")
net.Name = Config.NET_FOLDER
for _, name in { "Kick", "Fire", "Announce" } do
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = net
end
net:SetAttribute("Phase", "Waiting")
net:SetAttribute("TimeLeft", Config.MATCH_DURATION)
for _, key in Config.TEAM_ORDER do
	net:SetAttribute("Score" .. key, 0)
end
net.Parent = ReplicatedStorage

-- 충돌 그룹을 먼저 등록해야 경기장 파트(농구 링 등)에 그룹을 지정할 수 있다
CollisionGroups.setup()
local field = FieldBuilder.build()
PlayerService.init()
if Config.IS_WAR then
	-- 전쟁 모드: 축구공·킥 없이 전쟁 모드 공 5개만. 네트는 ShuttleService 가 만든다
	WarService.init(field)
else
	BallService.init(field, net)
end
ShuttleService.init(field)
WeaponService.init(field, net)
BotService.init()
MatchService.run(net)
