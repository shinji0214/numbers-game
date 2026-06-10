-- GameManager
-- ゲーム全体の状態管理
--   - ナンプレ盤面の生成・3D描画
--   - ブロック配置の受付・正解判定・ロック処理
--   - スパム制限・ペナルティ管理
--   - クリア判定

local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players            = game:GetService("Players")

local SudokuModule = require(ReplicatedStorage.Shared.SudokuModule)

------------------------------------------------------------------------
-- 定数
------------------------------------------------------------------------

local CELL_SIZE   = 10     -- 1マスのサイズ (studs)
local CELL_HEIGHT = 0.5    -- マスの厚み (studs)
local BOARD_Y     = 0.25   -- 盤面の床面高さ (baseplate上面=0を想定)
local GAP         = 0.12   -- セル間の隙間 (グリッド線として見える)

local COLOR = {
	blockA    = Color3.fromRGB(215, 218, 232),
	blockB    = Color3.fromRGB(188, 192, 212),
	prefilled = Color3.fromRGB(55,  62,  82),
	correct   = Color3.fromRGB(88,  185, 114),
	wrong     = Color3.fromRGB(205, 92,  92),
	divider   = Color3.fromRGB(50,  55,  75),
	frame     = Color3.fromRGB(40,  44,  62),
}

local TEXT_COLOR = {
	prefilled = Color3.fromRGB(240, 242, 255),
	player    = Color3.fromRGB(35,  35,  120),
}

local SPAM_WINDOW     = 30
local SPAM_MISS_LIMIT = 3
local SPAM_PENALTY    = 10
local PLACE_COOLDOWN  = 3
local BLOCK_EXTRA     = 1   -- 各数字につき余裕で追加するブロック数

------------------------------------------------------------------------
-- ① ServerEvents（BindableEvent/Function）の作成
--    BlockManager が WaitForChild で待ち受ける
------------------------------------------------------------------------

local serverEventsFolder = Instance.new("Folder")
serverEventsFolder.Name   = "ServerEvents"
serverEventsFolder.Parent = ServerScriptService

local function makeBindable(name, class)
	local b = Instance.new(class)
	b.Name   = name
	b.Parent = serverEventsFolder
	return b
end

local BE_SpawnBlocks   = makeBindable("SpawnBlocks",   "BindableEvent")    -- GameManager → BlockManager : ブロックスポーン
local BE_ConsumeBlock  = makeBindable("ConsumeBlock",  "BindableEvent")    -- GameManager → BlockManager : ブロック消費
local BE_ApplyPenalty  = makeBindable("ApplyPenalty",  "BindableEvent")    -- GameManager → BlockManager : ペナルティ
local BF_GetHeldNumber = makeBindable("GetHeldNumber", "BindableFunction") -- GameManager → BlockManager : 持っている数字を問い合わせ
local BE_GameWon       = makeBindable("GameWon",       "BindableEvent")    -- GameManager → ScoreManager : クリア通知＋全プレイヤー状態

------------------------------------------------------------------------
-- RemoteEvents（クライアント通信）
------------------------------------------------------------------------

local remoteFolder = Instance.new("Folder")
remoteFolder.Name   = "RemoteEvents"
remoteFolder.Parent = ReplicatedStorage

local function makeRemote(name, class)
	local r = Instance.new(class)
	r.Name   = name
	r.Parent = remoteFolder
	return r
end

local RE_UpdateCell    = makeRemote("UpdateCell",    "RemoteEvent")
local RE_UpdateScore   = makeRemote("UpdateScore",   "RemoteEvent")
local RE_BoardReady    = makeRemote("BoardReady",    "RemoteEvent")
local RE_PenaltyNotify = makeRemote("PenaltyNotify", "RemoteEvent")
local RE_PlaceBlock    = makeRemote("PlaceBlock",    "RemoteEvent")
local RE_PickupBlock   = makeRemote("PickupBlock",   "RemoteEvent")

------------------------------------------------------------------------
-- ゲーム状態
------------------------------------------------------------------------

local gameState = {
	puzzle         = nil,
	solution       = nil,
	current        = nil,
	locked         = nil,
	cells          = nil,
	remainingCells = 0,
}

local playerState = {}

local function getPlayerState(userId)
	if not playerState[userId] then
		playerState[userId] = {
			missTimes    = {},
			penaltyUntil = 0,
			score        = 0,
			combo        = 0,
			totalPlaced  = 0,
			correctCount = 0,
		}
	end
	return playerState[userId]
end

------------------------------------------------------------------------
-- ユーティリティ
------------------------------------------------------------------------

local function cellPosition(row, col)
	return Vector3.new((col - 5) * CELL_SIZE, BOARD_Y, (row - 5) * CELL_SIZE)
end

local function blockColor(row, col)
	local br = math.floor((row - 1) / 3)
	local bc = math.floor((col - 1) / 3)
	return (br + bc) % 2 == 0 and COLOR.blockA or COLOR.blockB
end

local function copy9x9(src)
	local dst = {}
	for i = 1, 9 do
		dst[i] = {}
		for j = 1, 9 do dst[i][j] = src[i][j] end
	end
	return dst
end

------------------------------------------------------------------------
-- ② ブロックリスト計算（空きマスの正解から必要な数字を集計）
------------------------------------------------------------------------

local function calcBlockList(puzzle, solution)
	-- 各数字（1〜9）が何個必要かを数える
	local counts = {}
	for n = 1, 9 do counts[n] = 0 end

	for i = 1, 9 do
		for j = 1, 9 do
			if puzzle[i][j] == 0 then
				local ans = solution[i][j]
				counts[ans] = counts[ans] + 1
			end
		end
	end

	-- 数字リストを作成（余裕分 BLOCK_EXTRA 個追加）
	local list = {}
	for n = 1, 9 do
		for _ = 1, counts[n] + BLOCK_EXTRA do
			table.insert(list, n)
		end
	end

	return list
end

------------------------------------------------------------------------
-- セルのビジュアル更新
------------------------------------------------------------------------

local function setCellVisual(cell, num, state)
	local gui   = cell:FindFirstChild("CellGui")
	local label = gui and gui:FindFirstChild("NumberLabel")

	if state == "prefilled" then
		cell.Color = COLOR.prefilled
	elseif state == "correct" then
		cell.Color = COLOR.correct
	elseif state == "wrong" then
		cell.Color = COLOR.wrong
	else
		cell.Color = blockColor(cell:GetAttribute("Row"), cell:GetAttribute("Col"))
	end

	if label then
		if num and num ~= 0 then
			label.Text       = tostring(num)
			label.TextColor3 = (state == "prefilled") and TEXT_COLOR.prefilled or TEXT_COLOR.player
			label.FontFace   = (state == "prefilled")
				and Font.fromEnum(Enum.Font.GothamBold)
				or  Font.fromEnum(Enum.Font.Gotham)
		else
			label.Text = ""
		end
	end
end

------------------------------------------------------------------------
-- 盤面の3D生成
------------------------------------------------------------------------

local function createCell(row, col, boardFolder, isPrefilled)
	local cell = Instance.new("Part")
	cell.Name          = string.format("Cell_%d_%d", row, col)
	cell.Size          = Vector3.new(CELL_SIZE - GAP, CELL_HEIGHT, CELL_SIZE - GAP)
	cell.Position      = cellPosition(row, col)
	cell.Anchored      = true
	cell.TopSurface    = Enum.SurfaceType.Smooth
	cell.BottomSurface = Enum.SurfaceType.Smooth
	cell.Material      = Enum.Material.SmoothPlastic
	cell.CastShadow    = false
	cell.Color         = isPrefilled and COLOR.prefilled or blockColor(row, col)

	cell:SetAttribute("Row",         row)
	cell:SetAttribute("Col",         col)
	cell:SetAttribute("IsPrefilled", isPrefilled)
	cell:SetAttribute("IsLocked",    isPrefilled)

	local gui = Instance.new("SurfaceGui")
	gui.Name       = "CellGui"
	gui.Face       = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(100, 100)
	gui.Parent     = cell

	local label = Instance.new("TextLabel")
	label.Name                   = "NumberLabel"
	label.Size                   = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled             = true
	label.Text                   = ""
	label.Parent                 = gui

	cell.Parent = boardFolder
	return cell
end

local function createDividers(boardFolder)
	local span = CELL_SIZE * 9
	for _, frac in ipairs({3.5, 6.5}) do
		for _, axis in ipairs({"V", "H"}) do
			local part = Instance.new("Part")
			part.Name          = "Divider" .. axis
			part.Size          = axis == "V"
				and Vector3.new(0.25, CELL_HEIGHT + 0.2, span)
				or  Vector3.new(span, CELL_HEIGHT + 0.2, 0.25)
			part.Position      = axis == "V"
				and Vector3.new((frac - 5) * CELL_SIZE, BOARD_Y + 0.1, 0)
				or  Vector3.new(0, BOARD_Y + 0.1, (frac - 5) * CELL_SIZE)
			part.Anchored      = true
			part.CanCollide    = false
			part.Color         = COLOR.divider
			part.Material      = Enum.Material.SmoothPlastic
			part.TopSurface    = Enum.SurfaceType.Smooth
			part.BottomSurface = Enum.SurfaceType.Smooth
			part.CastShadow    = false
			part.Parent        = boardFolder
		end
	end
end

local function createFrame(boardFolder)
	local span   = CELL_SIZE * 9
	local thick  = 0.5
	local height = CELL_HEIGHT + 0.3
	local yPos   = BOARD_Y + 0.1
	local offset = span / 2 + thick / 2

	local edges = {
		{Vector3.new(span + thick * 2, height, thick), Vector3.new(0,       yPos, -offset)},
		{Vector3.new(span + thick * 2, height, thick), Vector3.new(0,       yPos,  offset)},
		{Vector3.new(thick, height, span),              Vector3.new(-offset, yPos,  0)},
		{Vector3.new(thick, height, span),              Vector3.new( offset, yPos,  0)},
	}

	for _, e in ipairs(edges) do
		local part = Instance.new("Part")
		part.Size          = e[1]
		part.Position      = e[2]
		part.Anchored      = true
		part.CanCollide    = true
		part.Color         = COLOR.frame
		part.Material      = Enum.Material.SmoothPlastic
		part.TopSurface    = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.CastShadow    = false
		part.Parent        = boardFolder
	end
end

-- 盤面全体を生成
local function buildBoard(difficulty)
	local existing = workspace:FindFirstChild("Board")
	if existing then existing:Destroy() end

	local boardFolder = Instance.new("Folder")
	boardFolder.Name   = "Board"
	boardFolder.Parent = workspace

	local data = SudokuModule.generate(difficulty)
	gameState.puzzle         = data.puzzle
	gameState.solution       = data.solution
	gameState.current        = copy9x9(data.puzzle)
	gameState.locked         = {}
	gameState.cells          = {}
	gameState.remainingCells = 0

	for i = 1, 9 do
		gameState.locked[i] = {}
		gameState.cells[i]  = {}
		for j = 1, 9 do
			local isPrefilled = data.puzzle[i][j] ~= 0
			gameState.locked[i][j] = isPrefilled
			if not isPrefilled then
				gameState.remainingCells += 1
			end
		end
	end

	for i = 1, 9 do
		for j = 1, 9 do
			local val         = data.puzzle[i][j]
			local isPrefilled = val ~= 0
			local cell        = createCell(i, j, boardFolder, isPrefilled)
			gameState.cells[i][j] = cell
			if isPrefilled then setCellVisual(cell, val, "prefilled") end
		end
	end

	createDividers(boardFolder)
	createFrame(boardFolder)

	print(string.format("[GameManager] Board built. Difficulty=%s  EmptyCells=%d",
		difficulty, gameState.remainingCells))

	-- ③ ブロックリスト計算 → BlockManager にスポーン指示
	local blockList = calcBlockList(data.puzzle, data.solution)
	BE_SpawnBlocks:Fire(blockList)

	RE_BoardReady:FireAllClients(difficulty, gameState.remainingCells)
	return boardFolder
end

------------------------------------------------------------------------
-- スパム制限チェック
------------------------------------------------------------------------

local function checkSpam(ps)
	local now   = tick()
	local fresh = {}
	for _, t in ipairs(ps.missTimes) do
		if now - t < SPAM_WINDOW then table.insert(fresh, t) end
	end
	ps.missTimes = fresh
	return #ps.missTimes >= SPAM_MISS_LIMIT
end

------------------------------------------------------------------------
-- スコア加算
------------------------------------------------------------------------

local COMBO_MULTIPLIERS = {1.0, 1.5, 2.0, 2.5, 3.0}
local BASE_SCORE = 10

local function addScore(player, ps, isCorrect)
	if isCorrect then
		ps.combo        = math.min(ps.combo + 1, #COMBO_MULTIPLIERS)
		local gain      = math.floor(BASE_SCORE * COMBO_MULTIPLIERS[ps.combo])
		ps.score        += gain
		ps.correctCount += 1
		RE_UpdateScore:FireClient(player, ps.score, ps.combo, gain)
	else
		ps.combo = 0
		RE_UpdateScore:FireClient(player, ps.score, 0, 0)
	end
end

------------------------------------------------------------------------
-- クリア判定
------------------------------------------------------------------------

local function onWin()
	print("[GameManager] Puzzle cleared!")

	-- 全プレイヤーの状態をScoreManagerに渡す
	local snapshot = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local ps = getPlayerState(player.UserId)
		snapshot[player.UserId] = {
			name         = player.Name,
			score        = ps.score,
			correctCount = ps.correctCount,
			totalPlaced  = ps.totalPlaced,
		}
	end
	BE_GameWon:Fire(snapshot)
end

------------------------------------------------------------------------
-- セル配置処理（メイン）
------------------------------------------------------------------------

local lastPlaceTime = {}

local function handlePlaceBlock(player, row, col, num)
	-- 型チェック
	if type(row) ~= "number" or type(col) ~= "number" or type(num) ~= "number" then return end
	if row < 1 or row > 9 or col < 1 or col > 9 then return end
	if num < 1 or num > 9 then return end

	local userId = player.UserId
	local ps     = getPlayerState(userId)
	local now    = tick()

	-- ペナルティ中は無視
	if now < ps.penaltyUntil then
		RE_PenaltyNotify:FireClient(player, ps.penaltyUntil - now)
		return
	end

	-- クールダウンチェック
	if now - (lastPlaceTime[userId] or 0) < PLACE_COOLDOWN then return end
	lastPlaceTime[userId] = now

	-- ロック済みマスには置けない
	if gameState.locked[row][col] then return end

	-- ⑤ 実際に持っているブロックの数字と一致するか検証（不正防止）
	local heldNum = BF_GetHeldNumber:Invoke(userId)
	if heldNum == nil then return end          -- 何も持っていない
	if heldNum ~= num then return end          -- 持っている数字と違う

	ps.totalPlaced += 1

	local isCorrect = SudokuModule.isCorrect(gameState.solution, row, col, num)

	-- ③ 正解・不正解に関わらず本置き後はブロックを消費
	BE_ConsumeBlock:Fire(player)

	if isCorrect then
		gameState.current[row][col]  = num
		gameState.locked[row][col]   = true
		gameState.remainingCells    -= 1

		local cell = gameState.cells[row][col]
		setCellVisual(cell, num, "correct")
		cell:SetAttribute("IsLocked", true)

		addScore(player, ps, true)
		RE_UpdateCell:FireAllClients(row, col, num, "correct")

		if gameState.remainingCells <= 0 then onWin() end

	else
		gameState.current[row][col] = num
		setCellVisual(gameState.cells[row][col], num, "wrong")
		addScore(player, ps, false)

		-- スパムチェック → ④ ペナルティ
		table.insert(ps.missTimes, now)
		if checkSpam(ps) then
			ps.missTimes    = {}
			ps.penaltyUntil = now + SPAM_PENALTY
			ps.combo        = 0
			BE_ApplyPenalty:Fire(player, SPAM_PENALTY)   -- ④ BlockManagerにドロップ指示
			RE_PenaltyNotify:FireClient(player, SPAM_PENALTY)
			print(string.format("[GameManager] Penalty → %s", player.Name))
		end

		RE_UpdateCell:FireAllClients(row, col, num, "wrong")
	end
end

------------------------------------------------------------------------
-- RemoteEvent バインド
------------------------------------------------------------------------

RE_PlaceBlock.OnServerEvent:Connect(function(player, row, col, num)
	handlePlaceBlock(player, row, col, num)
end)

------------------------------------------------------------------------
-- プレイヤー退出時クリーンアップ
------------------------------------------------------------------------

Players.PlayerRemoving:Connect(function(player)
	playerState[player.UserId]   = nil
	lastPlaceTime[player.UserId] = nil
end)

------------------------------------------------------------------------
-- 起動
------------------------------------------------------------------------

buildBoard("Normal")
