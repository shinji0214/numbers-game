-- GameStateManager
-- ゲーム状態機械・看板スポーン・カウントダウン管理
--   状態: Lobby → InGame → Result → Lobby ...
--   ホスト: 開始ボタンを押したプレイヤー（入室順ではない）

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

------------------------------------------------------------------------
-- 座標定数
------------------------------------------------------------------------

local GAME_SPAWN_POS  = Vector3.new(-4286, 1864, 1760)
local LOBBY_SPAWN_POS = Vector3.new(-4286, 1864, 1560)  -- 要Studio調整
local SIGN_POS        = Vector3.new(-4286, 1864, 1600)  -- 看板位置（要Studio調整）

local COUNTDOWN_SEC = 10

------------------------------------------------------------------------
-- ServerEvents
------------------------------------------------------------------------

local serverEventsFolder = ServerScriptService:WaitForChild("ServerEvents")

local function getOrCreateBE(name)
	local r = serverEventsFolder:FindFirstChild(name)
	if not r then
		r        = Instance.new("BindableEvent")
		r.Name   = name
		r.Parent = serverEventsFolder
	end
	return r
end

local BE_BuildBoard  = getOrCreateBE("BuildBoard")
local BE_ResetBoard  = getOrCreateBE("ResetBoard")
local BE_ResetBlocks = getOrCreateBE("ResetBlocks")
local BE_GameWon     = getOrCreateBE("GameWon")

------------------------------------------------------------------------
-- RemoteEvents
------------------------------------------------------------------------

local remoteFolder = ReplicatedStorage:WaitForChild("RemoteEvents")

local function getOrCreateRE(name)
	local r = remoteFolder:FindFirstChild(name)
	if not r then
		r        = Instance.new("RemoteEvent")
		r.Name   = name
		r.Parent = remoteFolder
	end
	return r
end

local RE_GameStateChanged  = getOrCreateRE("GameStateChanged")   -- S→C: フェーズ通知
local RE_ConfigResult      = getOrCreateRE("ConfigResult")       -- S→C: 設定UI開閉結果
local RE_OpenConfig        = getOrCreateRE("OpenConfig")         -- C→S: 設定UI開放要求
local RE_CloseConfig       = getOrCreateRE("CloseConfig")        -- C→S: 設定UI閉鎖
local RE_RequestStart      = getOrCreateRE("RequestStart")       -- C→S: ゲーム開始要求
local RE_CountdownUpdate   = getOrCreateRE("CountdownUpdate")    -- S→C: カウントダウン通知
local RE_CancelCountdown   = getOrCreateRE("CancelCountdown")    -- C→S: カウントダウンキャンセル
local RE_PlayAgain         = getOrCreateRE("PlayAgain")          -- C→S: 次ゲーム回答

------------------------------------------------------------------------
-- 状態
------------------------------------------------------------------------

local gamePhase         = "Lobby"
local hostUserId        = nil
local difficulty        = "Normal"
local isConfiguring     = false   -- 設定UIを開いているプレイヤーがいるか
local configuringUserId = nil     -- 設定UIを開いているプレイヤーのUserId
local countdownThread   = nil     -- カウントダウンスレッド

------------------------------------------------------------------------
-- ユーティリティ
------------------------------------------------------------------------

local function broadcastState()
	RE_GameStateChanged:FireAllClients(gamePhase, hostUserId)
end

local function warpPlayer(player, pos)
	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
	end
end

local function warpAll(pos)
	for _, p in ipairs(Players:GetPlayers()) do
		warpPlayer(p, pos)
	end
end

------------------------------------------------------------------------
-- 設定UI排他制御
------------------------------------------------------------------------

local function tryOpenConfig(player)
	if gamePhase ~= "Lobby" then
		RE_ConfigResult:FireClient(player, false, "ゲームが進行中です")
		return
	end
	if isConfiguring then
		RE_ConfigResult:FireClient(player, false, "他のプレイヤーが設定中です")
		return
	end
	isConfiguring     = true
	configuringUserId = player.UserId
	RE_ConfigResult:FireClient(player, true, difficulty)
	print(string.format("[GameStateManager] Config opened by: %s", player.Name))
end

local function releaseConfig()
	isConfiguring     = false
	configuringUserId = nil
end

------------------------------------------------------------------------
-- カウントダウン
------------------------------------------------------------------------

local function cancelCountdown()
	if countdownThread then
		task.cancel(countdownThread)
		countdownThread = nil
	end
	hostUserId = nil
	releaseConfig()
	RE_CountdownUpdate:FireAllClients(nil)  -- nil = キャンセル通知
	print("[GameStateManager] Countdown cancelled")
end

local function startCountdown(diff)
	difficulty  = diff or difficulty
	hostUserId  = configuringUserId
	releaseConfig()

	print(string.format("[GameStateManager] Countdown started by %d. Difficulty=%s", hostUserId, difficulty))

	countdownThread = task.spawn(function()
		for i = COUNTDOWN_SEC, 0, -1 do
			RE_CountdownUpdate:FireAllClients(i)
			if i > 0 then
				task.wait(1)
			end
		end
		countdownThread = nil
		-- カウントダウン終了 → ゲーム開始
		gamePhase = "InGame"
		warpAll(GAME_SPAWN_POS)
		BE_BuildBoard:Fire(difficulty)
		broadcastState()
		print(string.format("[GameStateManager] Game started. Difficulty=%s", difficulty))
	end)
end

------------------------------------------------------------------------
-- 状態遷移
------------------------------------------------------------------------

local function endGame()
	if gamePhase ~= "InGame" then return end
	gamePhase = "Result"
	print("[GameStateManager] Game ended → Result phase")
	broadcastState()

	local host = Players:GetPlayerByUserId(hostUserId)
	if host then
		RE_GameStateChanged:FireClient(host, "Result_HostPrompt", hostUserId)
	end
end

local function resetToLobby()
	gamePhase  = "Lobby"
	hostUserId = nil
	releaseConfig()
	if countdownThread then
		task.cancel(countdownThread)
		countdownThread = nil
	end
	print("[GameStateManager] Resetting to Lobby")

	BE_ResetBoard:Fire()
	BE_ResetBlocks:Fire()
	task.wait(0.5)
	warpAll(LOBBY_SPAWN_POS)
	broadcastState()
end

------------------------------------------------------------------------
-- クライアントイベント受信
------------------------------------------------------------------------

-- ハンバーガーメニューから設定UI開放を要求
RE_OpenConfig.OnServerEvent:Connect(function(player)
	tryOpenConfig(player)
end)

-- 設定UIを閉じる
RE_CloseConfig.OnServerEvent:Connect(function(player)
	if player.UserId ~= configuringUserId then return end
	releaseConfig()
	print(string.format("[GameStateManager] Config closed by: %s", player.Name))
end)

-- 開始ボタン押下 → カウントダウン開始
RE_RequestStart.OnServerEvent:Connect(function(player, requestedDifficulty)
	if player.UserId ~= configuringUserId then return end
	if gamePhase ~= "Lobby" then return end
	startCountdown(requestedDifficulty)
end)

-- カウントダウンキャンセル（ホストのみ）
RE_CancelCountdown.OnServerEvent:Connect(function(player)
	if player.UserId ~= hostUserId then return end
	if countdownThread == nil then return end
	cancelCountdown()
end)

-- 次ゲーム回答（ホストのみ）
RE_PlayAgain.OnServerEvent:Connect(function(player, answer)
	if player.UserId ~= hostUserId then return end
	if gamePhase ~= "Result" then return end

	if answer == true then
		resetToLobby()
		task.wait(1)
		-- ロビーに戻った後、看板から再度開始する設計のため自動開始はしない
	else
		resetToLobby()
	end
end)

------------------------------------------------------------------------
-- ゲームクリア通知
------------------------------------------------------------------------

BE_GameWon.Event:Connect(function()
	task.wait(1)
	endGame()
end)

------------------------------------------------------------------------
-- プレイヤー参加・退出
------------------------------------------------------------------------

Players.PlayerAdded:Connect(function(player)
	if gamePhase == "InGame" then
		task.wait(2)
		warpPlayer(player, GAME_SPAWN_POS)
	end
	broadcastState()
end)

Players.PlayerRemoving:Connect(function(player)
	-- 設定UI開放中に退出したらロックを解放
	if player.UserId == configuringUserId then
		releaseConfig()
	end

	-- カウントダウン中またはResult中にホストが退出したらリセット
	if player.UserId == hostUserId then
		if countdownThread then
			cancelCountdown()
		elseif gamePhase == "Result" then
			resetToLobby()
		else
			hostUserId = nil
			broadcastState()
		end
	end
end)

------------------------------------------------------------------------
-- 看板スポーン
------------------------------------------------------------------------

local function spawnSign()
	local sign = Instance.new("Part")
	sign.Name      = "LobbySign"
	sign.Size      = Vector3.new(8, 4, 0.5)
	sign.CFrame    = CFrame.new(SIGN_POS + Vector3.new(0, 2, 0))
	sign.Anchored  = true
	sign.CanCollide = false
	sign.BrickColor = BrickColor.new("Sand green")
	sign.Material   = Enum.Material.SmoothPlastic
	sign.Parent     = workspace

	-- 看板上部に浮かぶテキスト
	local billboard = Instance.new("BillboardGui", sign)
	billboard.Size            = UDim2.fromOffset(300, 80)
	billboard.StudsOffset     = Vector3.new(0, 3.5, 0)
	billboard.AlwaysOnTop     = false
	billboard.ResetOnSpawn    = false

	local label = Instance.new("TextLabel", billboard)
	label.Size                   = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text                   = "▶  スタートはこちら"
	label.TextScaled             = true
	label.TextColor3             = Color3.fromRGB(255, 240, 100)
	label.Font                   = Enum.Font.GothamBold
	label.TextStrokeTransparency = 0.4

	-- ProximityPrompt
	local prompt = Instance.new("ProximityPrompt", sign)
	prompt.ObjectText    = "ゲーム設定"
	prompt.ActionText    = "開く"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 12
	prompt.HoldDuration  = 0

	prompt.Triggered:Connect(function(player)
		tryOpenConfig(player)
	end)

	print("[GameStateManager] Lobby sign spawned")
end

------------------------------------------------------------------------
-- 初期化
------------------------------------------------------------------------

task.wait(1)
spawnSign()
broadcastState()

print("[GameStateManager] loaded – phase=Lobby")
