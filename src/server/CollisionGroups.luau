-- 충돌 그룹: 선수는 자기 종목의 공만 몸에 닿는다
-- * 축구 선수 ↔ 축구공만, 배드민턴 선수 ↔ 셔틀콕만
-- * 가운데 네트는 셔틀콕만 막는다 (선수·축구공은 통과)
local PhysicsService = game:GetService("PhysicsService")

local CollisionGroups = {
	SoccerBall = "SoccerBall",
	Shuttle = "Shuttle",
	Net = "BadmintonNet",
	Players = {
		Soccer = "SoccerPlayers",
		Badminton = "BadmintonPlayers",
	},
}

function CollisionGroups.setup()
	local G = CollisionGroups
	local all = { "Default", G.SoccerBall, G.Shuttle, G.Net, G.Players.Soccer, G.Players.Badminton }
	for _, name in all do
		if name ~= "Default" and not PhysicsService:IsCollisionGroupRegistered(name) then
			PhysicsService:RegisterCollisionGroup(name)
		end
	end

	PhysicsService:CollisionGroupSetCollidable(G.SoccerBall, G.Players.Badminton, false)
	PhysicsService:CollisionGroupSetCollidable(G.Shuttle, G.Players.Soccer, false)
	for _, other in all do
		PhysicsService:CollisionGroupSetCollidable(G.Net, other, other == G.Shuttle)
	end
end

-- 캐릭터의 모든 파트(나중에 붙는 액세서리 포함)를 그룹에 넣는다
function CollisionGroups.applyToCharacter(character: Model, group: string)
	local current = character:GetAttribute("CollisionGroup")
	if current == group then
		return
	end
	if current == nil then
		character.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("BasePart") then
				descendant.CollisionGroup = character:GetAttribute("CollisionGroup") or "Default"
			end
		end)
	end
	character:SetAttribute("CollisionGroup", group)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = group
		end
	end
end

return CollisionGroups
