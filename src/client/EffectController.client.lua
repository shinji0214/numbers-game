-- EffectController
-- ブロック設置時のエフェクト
--   正解: 置いたセル → 行・列が波状に光る → 3×3エリアの縁が光る
--   不正解: 盤面全体が赤くフラッシュ

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local remoteFolder    = ReplicatedStorage:WaitForChild("RemoteEvents")
local RE_PlaceEffect  = remoteFolder:WaitForChild("PlaceEffect")
local RE_BoardReady   = remoteFolder:WaitForChild("BoardReady")

local currentBoardType = "Normal"

------------------------------------------------------------------------
-- 定数
------------------------------------------------------------------------

local BOARD_CENTER_X = -4307
local BOARD_CENTER_Z =  1923
local CELL_SIZE      = 10

-- 正解エフェクト色
local COLOR_HIT      = Color3.fromRGB(160, 255, 180)  -- 置いたセル（明るい緑）
local COLOR_WAVE     = Color3.fromRGB(120, 220, 145)  -- 行・列の波
local COLOR_AREA     = Color3.fromRGB(100, 200, 130)  -- 3×3エリア

-- 不正解エフェクト色
local COLOR_WRONG    = Color3.fromRGB(255, 100, 100)  -- 全体フラッシュ

-- タイミング
local WAVE_STEP      = 0.055   -- 行・列の波：1マスあたりの遅延（秒）
local AREA_DELAY     = 0.25    -- エリア光りの開始遅延（秒）
local FLASH_TIME     = 0.12    -- 光る時間（秒）
local RESTORE_TIME   = 0.25    -- 元の色に戻る時間（秒）
local WRONG_HOLD     = 0.18    -- 不正解フラッシュの保持時間（秒）

------------------------------------------------------------------------
-- ユーティリティ
------------------------------------------------------------------------

local function getBoard()
	return workspace:FindFirstChild("Board")
end

local function getCell(board, row, col)
	return board and board:FindFirstChild(string.format("Cell_%d_%d", row, col))
end

-- Hard モード: (r,c) が有効セルかどうか
local function isHardCell(r, c)
	return (r <= 9 and c <= 9) or (r >= 4 and c >= 4 and r <= 12 and c <= 12)
end

-- セルをフラッシュして元の色に戻す
local function flashCell(cell, color, delay, holdTime, restoreTime)
	if not cell or not cell:IsA("BasePart") then return end
	task.delay(delay, function()
		if not cell or not cell.Parent then return end
		local originalColor = cell.Color
		cell.Color = color
		task.delay(holdTime, function()
			if not cell or not cell.Parent then return end
			TweenService:Create(cell,
				TweenInfo.new(restoreTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Color = originalColor }
			):Play()
		end)
	end)
end

------------------------------------------------------------------------
-- 正解エフェクト
------------------------------------------------------------------------

local function playCorrectEffect(row, col)
	local board = getBoard()
	if not board then return end

	local isHard = currentBoardType == "Hard"
	local maxDim = isHard and 12 or 9

	-- 1. 置いたセルを光らせる
	local hitCell = getCell(board, row, col)
	flashCell(hitCell, COLOR_HIT, 0, FLASH_TIME, RESTORE_TIME)

	-- 2. 行・列を距離に応じた遅延で波状に光らせる（有効セルのみ）
	for i = 1, maxDim do
		if not isHard or isHardCell(row, i) then
			if i ~= col then
				local dist = math.abs(i - col)
				flashCell(getCell(board, row, i), COLOR_WAVE, dist * WAVE_STEP, FLASH_TIME, RESTORE_TIME)
			end
		end
		if not isHard or isHardCell(i, col) then
			if i ~= row then
				local dist = math.abs(i - row)
				flashCell(getCell(board, i, col), COLOR_WAVE, dist * WAVE_STEP, FLASH_TIME, RESTORE_TIME)
			end
		end
	end

	-- 3. 3×3 ボックスを光らせる（行・列と被るセルは除く）
	-- Hard モード: 属するグリッド（Grid A 優先、それ以外は Grid B）でボックスを決定
	-- 重複ゾーン(4-9, 4-9)は両グリッドで同一ボックスになるため常に一つのボックスのみ
	local boxRow, boxCol
	if not isHard or (row <= 9 and col <= 9) then
		-- Grid A ボックス (0-indexed 開始点)
		boxRow = math.floor((row - 1) / 3) * 3
		boxCol = math.floor((col - 1) / 3) * 3
	else
		-- Grid B ボックス: ローカル座標 (row-3, col-3) のボックスを結合座標に変換
		boxRow = math.floor((row - 4) / 3) * 3 + 3
		boxCol = math.floor((col - 4) / 3) * 3 + 3
	end

	for r = boxRow + 1, boxRow + 3 do
		for c = boxCol + 1, boxCol + 3 do
			if r ~= row and c ~= col then
				if not isHard or isHardCell(r, c) then
					flashCell(getCell(board, r, c), COLOR_AREA, AREA_DELAY, FLASH_TIME, RESTORE_TIME)
				end
			end
		end
	end
end

------------------------------------------------------------------------
-- 不正解エフェクト
------------------------------------------------------------------------

local function playWrongEffect(row, col)
	local board = getBoard()
	if not board then return end

	local isHard = currentBoardType == "Hard"
	local maxDim = isHard and 12 or 9

	-- 有効セルを全て赤くフラッシュ
	for r = 1, maxDim do
		for c = 1, maxDim do
			if not isHard or isHardCell(r, c) then
				flashCell(getCell(board, r, c), COLOR_WRONG, 0, WRONG_HOLD, RESTORE_TIME)
			end
		end
	end
end

------------------------------------------------------------------------
-- イベント受信
------------------------------------------------------------------------

RE_BoardReady.OnClientEvent:Connect(function(_difficulty, _remaining, boardType)
	currentBoardType = boardType or "Normal"
end)

RE_PlaceEffect.OnClientEvent:Connect(function(row, col, result)
	if result == "correct" then
		playCorrectEffect(row, col)
	elseif result == "wrong" then
		playWrongEffect(row, col)
	end
end)

print("[EffectController] loaded")
