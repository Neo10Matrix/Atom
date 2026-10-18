-- 아미사커 서버 진입점
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local BallService = require(script.BallService)
local FieldBuilder = require(script.FieldBuilder)
local MatchService = require(script.MatchService)
local PlayerService = require(script.PlayerService)
local ZoneService = require(script.ZoneService)

-- 원격 이벤트 + 경기 상태(속성)를 담는 폴더
local net = Instance.new("Folder")
net.Name = Config.NET_FOLDER
for _, name in { "Kick", "Ability", "ChooseClass", "Announce" } do
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

local field = FieldBuilder.build()
PlayerService.init(net)
ZoneService.init(field)
BallService.init(field, net)
MatchService.run(net)
