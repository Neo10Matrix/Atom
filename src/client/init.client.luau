-- 아미사커 클라이언트 진입점
local Controls = require(script.Controls)
local HUD = require(script.HUD)

HUD.init()
Controls.init(HUD)
