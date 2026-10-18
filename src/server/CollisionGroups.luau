-- 충돌 그룹: 가운데 네트는 셔틀콕만 막는다 (선수·축구공은 통과)
local PhysicsService = game:GetService("PhysicsService")

local CollisionGroups = {
	SoccerBall = "SoccerBall",
	Shuttle = "Shuttle",
	Net = "BadmintonNet",
}

function CollisionGroups.setup()
	local G = CollisionGroups
	local all = { "Default", G.SoccerBall, G.Shuttle, G.Net }
	for _, name in all do
		if name ~= "Default" and not PhysicsService:IsCollisionGroupRegistered(name) then
			PhysicsService:RegisterCollisionGroup(name)
		end
	end
	for _, other in all do
		PhysicsService:CollisionGroupSetCollidable(G.Net, other, other == G.Shuttle)
	end
end

return CollisionGroups
