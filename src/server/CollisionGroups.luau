-- 충돌 그룹
-- * 가운데 네트는 셔틀콕만 막는다 (선수·축구공은 통과)
-- * 드리블 중인 축구공은 선수 몸과 부딪히지 않는다 (공 위에 올라타지 않도록)
local PhysicsService = game:GetService("PhysicsService")

local CollisionGroups = {
	SoccerBall = "SoccerBall",
	DribbledBall = "DribbledBall",
	Shuttle = "Shuttle",
	Net = "BadmintonNet",
	Characters = "Characters",
}

function CollisionGroups.setup()
	local G = CollisionGroups
	local all = { "Default", G.SoccerBall, G.DribbledBall, G.Shuttle, G.Net, G.Characters }
	for _, name in all do
		if name ~= "Default" and not PhysicsService:IsCollisionGroupRegistered(name) then
			PhysicsService:RegisterCollisionGroup(name)
		end
	end
	for _, other in all do
		PhysicsService:CollisionGroupSetCollidable(G.Net, other, other == G.Shuttle)
	end
	PhysicsService:CollisionGroupSetCollidable(G.DribbledBall, G.Characters, false)
end

-- 캐릭터(플레이어·봇)의 모든 파트를 Characters 그룹에 넣는다 (나중에 붙는 액세서리 포함)
function CollisionGroups.applyToCharacter(character: Model)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = CollisionGroups.Characters
		end
	end
	character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = CollisionGroups.Characters
		end
	end)
end

return CollisionGroups
