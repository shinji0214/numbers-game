-- GameStateManager
-- ゲーム状態機械・ホスト管理・プレイヤーワープ
--   状態: Lobby → InGame → Result → Lobby ...
--   ホスト: 最初に参加したプレイヤー。退出時は次のプレイヤーに引き継ぎ

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

------------------------------------------------------------------------
-- ワープ先座標
------------------------------------------------------------------------

local GAME_SPAWN_POS  = Vector3.new(-4286, 1864, 1760)  -- ゲームエリアSpawn
local LOBBY_SPAWN_POS = Vector3.new(-4286, 1864, 1560)  -- ロビーエリアSpawn（要Studio調整）

------------------------------------------------------------------------
-- ServerEvents / RemoteEvents
------------------------------------------------------------------------

local serverEventsFolder = ServerScriptService:WaitForChild("ServerEvents")
local BE_BuildBoard      = serverEventsFolder:WaitForChild("BuildBoard")
local BE_ResetBoard      = serverEventsFolder:WaitForChild("ResetBoard")
local BE_ResetBlocks     = serverEventsFolder:WaitForChild("ResetBlocks")

local remoteFolder = ReplicatedStorage:WaitForChild("RemoteEvents")

local function getOrCreate(name, class)
	local r = remoteFolder:FindFirstChild(name)
	if not r then
		r        = Instance.new(class)
		r.Name   = name
		r.Parent = remoteFolder
	end
	return r
end

local RE_GameStateChanged = getOrCreate("GameStateChanged", "RemoteEvent") -- S→C: 状態通知
local RE_RequestStart     = getOrCreate("RequestStart",     "RemoteEvent") -- C→S: ホストがゲーム開始を要求
local RE_PlayAgain        = getOrCreate("PlayAgain",        "RemoteEvent") -- C→S: ホストが次ゲームを回答

------------------------------------------------------------------------
-- 状態
------------------------------------------------------------------------

local gamePhase  = "Lobby"  -- "Lobby" | "InGame" | "Result"
local hostUserId = nil
local difficulty = "Normal"

------------------------------------------------------------------------
-- ホスト管理
------------------------------------------------------------------------

local function assignHost()
	local players = Players:GetPlayers()
	if #players == 0 then
		hostUserId = nil
		return
	end
	hostUserId = players[1].UserId
	print(string.format("[GameStateManager] Host assigned: %s", players[1].Name))
end

local function broadcastState()
	RE_GameStateChanged:FireAllClients(gamePhase, hostUserId)
end

------------------------------------------------------------------------
-- プレイヤーワープ
------------------------------------------------------------------------

local function warpPlayer(player, pos)
	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
	end
end

local function warpAll(pos)
	for _, player in ipairs(Players:GetPlayers()) do
		warpPlayer(player, pos)
	end
end

------------------------------------------------------------------------
-- 状態遷移
------------------------------------------------------------------------

local function startGame(diff)
	if gamePhase ~= "Lobby" then return end
	difficulty = diff or difficulty
	gamePhase  = "InGame"

	print(string.format("[GameStateManager] Starting game. Difficulty=%s", difficulty))

	-- 全員ゲームエリアにワープ
	warpAll(GAME_SPAWN_POS)

	-- 盤面・ブロック生成
	BE_BuildBoard:Fire(difficulty)

	broadcastState()
end

local function endGame()
	if gamePhase ~= "InGame" then return end
	gamePhase = "Result"
	print("[GameStateManager] Game ended → Result phase")
	broadcastState()

	-- ホストに次ゲームの確認を送る（クライアント側UIが受け取る）
	local host = Players:GetPlayerByUserId(hostUserId)
	if host then
		RE_GameStateChanged:FireClient(host, "Result_HostPrompt", hostUserId)
	end
end

local function resetToLobby()
	gamePhase = "Lobby"
	print("[GameStateManager] Resetting to Lobby")

	-- 盤面・ブロック削除
	BE_ResetBoard:Fire()
	BE_ResetBlocks:Fire()

	-- 全員ロビーにワープ
	task.wait(0.5)  -- リセット処理が完了するまで少し待つ
	warpAll(LOBBY_SPAWN_POS)

	broadcastState()
end

------------------------------------------------------------------------
-- ScoreManager のゲームクリア通知を受けて Result フェーズへ
------------------------------------------------------------------------

local BE_GameWon = serverEventsFolder:WaitForChild("GameWon")
BE_GameWon.Event:Connect(function()
	task.wait(1)  -- 結果画面表示のための待機
	endGame()
end)

------------------------------------------------------------------------
-- クライアントからのイベント受信
------------------------------------------------------------------------

-- ホストがゲーム開始を要求
RE_RequestStart.OnServerEvent:Connect(function(player, requestedDifficulty)
	if player.UserId ~= hostUserId then return end
	if gamePhase ~= "Lobby" then return end
	startGame(requestedDifficulty)
end)

-- ホストが次ゲームを回答
RE_PlayAgain.OnServerEvent:Connect(function(player, answer)
	if player.UserId ~= hostUserId then return end
	if gamePhase ~= "Result" then return end

	if answer == true then
		-- リセットしてそのままゲーム開始
		resetToLobby()
		task.wait(1)
		startGame(difficulty)
	else
		-- ロビーに戻る
		resetToLobby()
	end
end)

------------------------------------------------------------------------
-- プレイヤー参加・退出
------------------------------------------------------------------------

Players.PlayerAdded:Connect(function(player)
	-- ホスト未設定なら設定
	if hostUserId == nil then
		hostUserId = player.UserId
		print(string.format("[GameStateManager] Host assigned: %s", player.Name))
	end

	-- ゲーム中に参加した場合はゲームエリアにワープ
	if gamePhase == "InGame" then
		task.wait(2)  -- キャラクターのロードを待つ
		warpPlayer(player, GAME_SPAWN_POS)
	end

	broadcastState()
end)

Players.PlayerRemoving:Connect(function(player)
	if player.UserId ~= hostUserId then return end

	-- ホストが退出したら次のプレイヤーに引き継ぎ
	local players = Players:GetPlayers()
	local next    = nil
	for _, p in ipairs(players) do
		if p.UserId ~= player.UserId then
			next = p
			break
		end
	end

	hostUserId = next and next.UserId or nil
	if next then
		print(string.format("[GameStateManager] Host transferred to: %s", next.Name))
	end
	broadcastState()
end)

------------------------------------------------------------------------
-- 初期状態をロビーとして通知
------------------------------------------------------------------------

task.wait(1)  -- 他のスクリプトの起動を待つ
broadcastState()

print("[GameStateManager] loaded – phase=Lobby")
