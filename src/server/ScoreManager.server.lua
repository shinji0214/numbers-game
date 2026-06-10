-- ScoreManager
-- クリア時のボーナス集計・最終スコア計算・結果通知

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players             = game:GetService("Players")

------------------------------------------------------------------------
-- ServerEvents / RemoteEvents を待つ
------------------------------------------------------------------------

local serverEventsFolder = ServerScriptService:WaitForChild("ServerEvents")
local BE_GameWon         = serverEventsFolder:WaitForChild("GameWon")

local remoteFolder = ReplicatedStorage:WaitForChild("RemoteEvents")

local function getOrCreate(name, class)
	local r = remoteFolder:FindFirstChild(name)
	if not r then
		r = Instance.new(class)
		r.Name   = name
		r.Parent = remoteFolder
	end
	return r
end

-- サーバー → クライアント
local RE_GameResult = getOrCreate("GameResult", "RemoteEvent")  -- 最終結果を全員に送る

------------------------------------------------------------------------
-- ボーナス定数
------------------------------------------------------------------------

local SPEED_BONUS_BASE        = 100   -- スピードボーナスの基準値
local COMPLETION_BONUS        = 50    -- 完成ボーナス（全員一律）

-- 完成貢献ボーナス（正解配置数の順位ごと）
local CONTRIBUTION_BONUS = {
	[1] = 200,  -- 1位
	[2] = 150,  -- 2位
	[3] = 100,  -- 3位
}
local CONTRIBUTION_BONUS_DEFAULT = 50  -- 4位以下

------------------------------------------------------------------------
-- スピードボーナス計算
-- 正解率（正解数 ÷ 本置き総数）× 基準値
------------------------------------------------------------------------

local function calcSpeedBonus(correctCount, totalPlaced)
	if totalPlaced == 0 then return 0 end
	local accuracy = correctCount / totalPlaced
	return math.floor(SPEED_BONUS_BASE * accuracy)
end

------------------------------------------------------------------------
-- 完成貢献ボーナス計算
-- 正解配置数の多い順にランキングし、順位に応じたボーナスを付与
------------------------------------------------------------------------

local function calcContributionBonuses(snapshot)
	-- 正解配置数でソート
	local ranked = {}
	for userId, data in pairs(snapshot) do
		table.insert(ranked, {userId = userId, correctCount = data.correctCount})
	end
	table.sort(ranked, function(a, b)
		return a.correctCount > b.correctCount
	end)

	-- 順位ごとにボーナスを付与（同率は同じ順位）
	local bonuses  = {}
	local prevCount = -1
	local rank      = 0
	local rankCount = 0

	for _, entry in ipairs(ranked) do
		rankCount += 1
		if entry.correctCount ~= prevCount then
			rank      = rankCount
			prevCount = entry.correctCount
		end
		bonuses[entry.userId] = CONTRIBUTION_BONUS[rank] or CONTRIBUTION_BONUS_DEFAULT
	end

	return bonuses
end

------------------------------------------------------------------------
-- クリア時の最終集計
------------------------------------------------------------------------

BE_GameWon.Event:Connect(function(snapshot)
	print("[ScoreManager] Calculating final scores...")

	local contributionBonuses = calcContributionBonuses(snapshot)

	-- 最終スコアを計算してリストを作る
	local results = {}

	for userId, data in pairs(snapshot) do
		local speedBonus        = calcSpeedBonus(data.correctCount, data.totalPlaced)
		local contributionBonus = contributionBonuses[userId] or CONTRIBUTION_BONUS_DEFAULT
		local finalScore        = data.score + speedBonus + contributionBonus + COMPLETION_BONUS

		table.insert(results, {
			userId           = userId,
			name             = data.name,
			baseScore        = data.score,
			speedBonus       = speedBonus,
			contributionBonus = contributionBonus,
			completionBonus  = COMPLETION_BONUS,
			finalScore       = finalScore,
			correctCount     = data.correctCount,
			totalPlaced      = data.totalPlaced,
		})

		print(string.format(
			"  %s: base=%d speed=%d contrib=%d complete=%d → total=%d",
			data.name, data.score, speedBonus, contributionBonus, COMPLETION_BONUS, finalScore
		))
	end

	-- 最終スコア順にソート
	table.sort(results, function(a, b)
		return a.finalScore > b.finalScore
	end)

	-- 順位を付ける
	for i, result in ipairs(results) do
		result.rank = i
	end

	-- 全クライアントに結果を送信
	RE_GameResult:FireAllClients(results)

	print(string.format("[ScoreManager] Done. Winner: %s (%d pts)",
		results[1] and results[1].name or "N/A",
		results[1] and results[1].finalScore or 0
	))
end)

print("[ScoreManager] loaded")
