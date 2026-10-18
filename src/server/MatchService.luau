-- 경기 흐름: 대기 → 카운트다운 → 경기 → (축구 골 → 킥오프) → 종료
-- 배드민턴 득점은 경기를 멈추지 않고 점수만 올린 뒤 다시 서브한다
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local BallService = require(script.Parent.BallService)
local BotService = require(script.Parent.BotService)
local PlayerService = require(script.Parent.PlayerService)
local ShuttleService = require(script.Parent.ShuttleService)

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

-- 팀당 PLAYERS_PER_BALL 명마다 축구공·셔틀콕 1개씩 (최소 1개)
local function ballCount(): number
	local largest = 0
	for _, key in Config.TEAM_ORDER do
		largest = math.max(largest, #PlayerService.membersOf(key))
	end
	return math.max(1, largest // Config.PLAYERS_PER_BALL)
end

local function kickoff()
	BotService.fill()
	local count = ballCount()
	BallService.reset(count)
	ShuttleService.reset(count)
	PlayerService.positionPlayers()
	PlayerService.setFrozen(true)
	setPhase("Countdown")
	for i = Config.COUNTDOWN, 1, -1 do
		announce(tostring(i), 0.9)
		task.wait(1)
	end
	announce("작전 개시!", 1.5)
	PlayerService.setFrozen(false)
	BallService.release()
	ShuttleService.release()
	setPhase("Playing")
end

-- 골 이벤트 처리: 점수, 리더보드, 안내
local function handleGoal(event: BallService.BallEvent)
	-- 공이 들어간 골대의 반대편 팀이 득점
	local scoringKey = teamKeyForSide(-(event.side :: number))
	local teamName = Config.Teams[scoringKey].Name
	addScore(scoringKey)

	local scorer = event.scorer
	local text
	if scorer and scorer.Parent and PlayerService.teamKeyOf(scorer) == scoringKey then
		PlayerService.addPoint(scorer)
		text = string.format("골! %s — %s", teamName, PlayerService.nameOf(scorer))
	elseif scorer and scorer.Parent then
		text = string.format("자책골! %s 득점 (%s)", teamName, PlayerService.nameOf(scorer))
	else
		text = string.format("골! %s", teamName)
	end
	announce(text, Config.GOAL_CELEBRATION)
end

-- 배드민턴 득점 처리: 셔틀콕이 떨어진(또는 반칙한) 진영의 반대편 팀이 득점
local function handleShuttlePoint(event: ShuttleService.ShuttleEvent)
	local concedingKey = teamKeyForSide(event.concedingSide)
	local scoringKey = teamKeyForSide(-event.concedingSide)
	addScore(scoringKey)

	local scorer = event.scorer
	if scorer and scorer.Parent and PlayerService.teamKeyOf(scorer) == scoringKey then
		PlayerService.addPoint(scorer)
	end
	local reason = if event.reason == "fault"
		then string.format("%s 4번 헤딩 반칙", Config.Teams[concedingKey].Name)
		else string.format("%s 진영에 떨어짐", Config.Teams[concedingKey].Name)
	announce(string.format("배드민턴 득점! %s (%s)", Config.Teams[scoringKey].Name, reason), 2)
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
		local dt = RunService.Heartbeat:Wait()
		timeLeft -= dt
		net:SetAttribute("TimeLeft", math.max(0, math.ceil(timeLeft)))

		local needKickoff = false
		for _, event in BallService.step() do
			if event.kind == "out" then
				announce("공이 작전 지역을 벗어남! 중앙 재배치", 1.5)
			else
				handleGoal(event)
				needKickoff = true
			end
		end
		for _, event in ShuttleService.step(dt) do
			handleShuttlePoint(event)
		end
		if needKickoff then
			setPhase("Goal")
			task.wait(Config.GOAL_CELEBRATION)
			kickoff()
		end
	end

	BallService.reset(ballCount())
	ShuttleService.reset(ballCount())
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
