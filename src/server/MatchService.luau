-- 경기 흐름: 대기 → 카운트다운 → 경기 → (골 → 킥오프) → 종료
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local BallService = require(script.Parent.BallService)
local PlayerService = require(script.Parent.PlayerService)
local ZoneService = require(script.Parent.ZoneService)

local MatchService = {}

local net: Folder
local announceEvent: RemoteEvent

local function setPhase(phase: string)
	net:SetAttribute("Phase", phase)
end

local function announce(text: string, duration: number?)
	announceEvent:FireAllClients(text, duration or 2)
end

local function teamKeyForSide(side: number): string
	for key, info in Config.Teams do
		if info.Side == side then
			return key
		end
	end
	error("no team on side " .. side)
end

local function addScore(key: string)
	local attribute = "Score" .. key
	net:SetAttribute(attribute, (net:GetAttribute(attribute) or 0) + 1)
end

local function kickoff()
	BallService.reset()
	PlayerService.positionPlayers()
	ZoneService.resetAll()
	PlayerService.setFrozen(true)
	setPhase("Countdown")
	for i = Config.COUNTDOWN, 1, -1 do
		announce(tostring(i), 0.9)
		task.wait(1)
	end
	announce("작전 개시!", 1.5)
	PlayerService.setFrozen(false)
	BallService.release()
	setPhase("Playing")
end

-- 골 이벤트 처리. 메인 공 골이면 true (킥오프 필요)
local function handleGoal(event: BallService.BallEvent): boolean
	-- 공이 들어간 골대의 반대편 팀이 득점
	local scoringKey = teamKeyForSide(-(event.side :: number))
	local teamName = Config.Teams[scoringKey].Name
	addScore(scoringKey)

	local scorer = event.scorer
	local text
	if scorer and scorer.Parent and PlayerService.teamKeyOf(scorer) == scoringKey then
		PlayerService.addGoal(scorer)
		text = string.format("골! %s — %s", teamName, scorer.DisplayName)
	elseif scorer and scorer.Parent then
		text = string.format("자책골! %s 득점 (%s)", teamName, scorer.DisplayName)
	else
		text = string.format("골! %s", teamName)
	end
	if event.ballKind == "bonus" then
		text ..= " (포탄 공)"
	elseif event.ballKind == "special" then
		text ..= " (골키퍼 스페셜 슛!)"
	end
	announce(text, if event.isMain then Config.GOAL_CELEBRATION else 2)
	return event.isMain
end

local function playMatch()
	for _, key in Config.TEAM_ORDER do
		net:SetAttribute("Score" .. key, 0)
	end
	local timeLeft = Config.MATCH_DURATION
	net:SetAttribute("TimeLeft", timeLeft)

	announce("전원 집합! 경기 준비", 2)
	task.wait(2)
	kickoff()

	while timeLeft > 0 do
		timeLeft -= RunService.Heartbeat:Wait()
		net:SetAttribute("TimeLeft", math.max(0, math.ceil(timeLeft)))

		local needKickoff = false
		for _, event in BallService.step() do
			if event.kind == "out" then
				announce("공이 작전 지역을 벗어남! 중앙 재배치", 1.5)
			elseif handleGoal(event) then
				needKickoff = true
			end
		end
		if needKickoff then
			setPhase("Goal")
			task.wait(Config.GOAL_CELEBRATION)
			kickoff()
		end
	end

	BallService.reset()
	setPhase("Ended")
	local alpha = net:GetAttribute("ScoreAlpha") or 0
	local bravo = net:GetAttribute("ScoreBravo") or 0
	if alpha == bravo then
		announce(string.format("무승부 %d : %d — 전원 휴식!", alpha, bravo), Config.END_SCREEN)
	else
		local winner = if alpha > bravo then "Alpha" else "Bravo"
		announce(string.format("%s 승리! %d : %d", Config.Teams[winner].Name, alpha, bravo), Config.END_SCREEN)
	end
	task.wait(Config.END_SCREEN)
end

function MatchService.run(netFolder: Folder)
	net = netFolder
	announceEvent = net:WaitForChild("Announce") :: RemoteEvent
	local minPlayers = if RunService:IsStudio() then 1 else Config.MIN_PLAYERS
	net:SetAttribute("MinPlayers", minPlayers)

	while true do
		setPhase("Waiting")
		while #Players:GetPlayers() < minPlayers do
			task.wait(1)
		end
		playMatch()
	end
end

return MatchService
