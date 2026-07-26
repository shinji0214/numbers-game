-- SudokuModule
-- ナンプレの生成・正解判定を担当するモジュール

local SudokuModule = {}

-- 9×9の空盤面を作成
local function createEmptyBoard()
	local board = {}
	for i = 1, 9 do
		board[i] = {}
		for j = 1, 9 do
			board[i][j] = 0
		end
	end
	return board
end

-- 数字を置けるか判定
local function isValid(board, row, col, num)
	-- 行チェック
	for j = 1, 9 do
		if board[row][j] == num then return false end
	end
	-- 列チェック
	for i = 1, 9 do
		if board[i][col] == num then return false end
	end
	-- 3×3ブロックチェック
	local startRow = math.floor((row - 1) / 3) * 3 + 1
	local startCol = math.floor((col - 1) / 3) * 3 + 1
	for i = startRow, startRow + 2 do
		for j = startCol, startCol + 2 do
			if board[i][j] == num then return false end
		end
	end
	return true
end

-- バックトラッキングで盤面を完成させる
local function solveSudoku(board)
	for i = 1, 9 do
		for j = 1, 9 do
			if board[i][j] == 0 then
				-- 1〜9をシャッフルして試す（毎回異なるパズルに）
				local nums = {1,2,3,4,5,6,7,8,9}
				for k = #nums, 2, -1 do
					local r = math.random(k)
					nums[k], nums[r] = nums[r], nums[k]
				end
				for _, num in ipairs(nums) do
					if isValid(board, i, j, num) then
						board[i][j] = num
						if solveSudoku(board) then return true end
						board[i][j] = 0
					end
				end
				return false
			end
		end
	end
	return true
end

-- 難易度に応じた空きマス数
local BLANK_COUNT = {
	Debug  = 3,   -- デバッグ用：空きマス3つのみ
	Easy   = 32,
	Normal = 45,
	Hard   = 90,  -- Hardは12×12サムライ盤面（有効セル126個）
}

-- 完成盤面から指定数のマスを空にしてパズルを作る
local function createPuzzle(solvedBoard, blankCount)
	-- 深コピー
	local puzzle = {}
	for i = 1, 9 do
		puzzle[i] = {}
		for j = 1, 9 do
			puzzle[i][j] = solvedBoard[i][j]
		end
	end
	-- ランダムにマスを空にする
	local count = 0
	local attempts = 0
	while count < blankCount and attempts < 200 do
		local r = math.random(1, 9)
		local c = math.random(1, 9)
		if puzzle[r][c] ~= 0 then
			puzzle[r][c] = 0
			count = count + 1
		end
		attempts = attempts + 1
	end
	return puzzle
end

-- Hardモード（サムライ数独）生成
-- Grid A (9×9) + Grid B (9×9) が重なる12×12複合盤面
-- 重複ゾーン: 結合盤面の rows 4-9, cols 4-9 (Grid A の右下 / Grid B の左上)
local function generateHard()
	math.randomseed(tick())

	for _ = 1, 100 do
		-- Grid A を完全解決
		local gridA = createEmptyBoard()
		solveSudoku(gridA)

		-- Grid B の重複部分を Grid A から複写（Grid A rows 4-9, cols 4-9 → Grid B rows 1-6, cols 1-6）
		local gridB = createEmptyBoard()
		for r = 1, 6 do
			for c = 1, 6 do
				gridB[r][c] = gridA[r + 3][c + 3]
			end
		end

		-- Grid B を重複制約付きでバックトラッキング解決
		if solveSudoku(gridB) then
			-- 12×12 結合盤面を組み立てる（無効マスは 0 のまま）
			local solution = {}
			for r = 1, 12 do
				solution[r] = {}
				for c = 1, 12 do solution[r][c] = 0 end
			end
			for r = 1, 9 do
				for c = 1, 9 do solution[r][c]         = gridA[r][c] end
			end
			for r = 1, 9 do
				for c = 1, 9 do solution[r + 3][c + 3] = gridB[r][c] end
			end

			-- 有効マスリストを収集してシャッフル
			local validCells = {}
			for r = 1, 12 do
				for c = 1, 12 do
					if solution[r][c] ~= 0 then
						table.insert(validCells, {r, c})
					end
				end
			end
			for k = #validCells, 2, -1 do
				local rnd = math.random(k)
				validCells[k], validCells[rnd] = validCells[rnd], validCells[k]
			end

			-- solution を deep copy してパズルを作成
			local puzzle = {}
			for r = 1, 12 do
				puzzle[r] = {}
				for c = 1, 12 do puzzle[r][c] = solution[r][c] end
			end
			for i = 1, math.min(BLANK_COUNT.Hard, #validCells) do
				local pos = validCells[i]
				puzzle[pos[1]][pos[2]] = 0
			end

			return { puzzle = puzzle, solution = solution, boardType = "Hard" }
		end
	end

	-- フォールバック（ほぼ到達しない）
	warn("[SudokuModule] generateHard: failed after 100 attempts, falling back to Normal")
	local board = createEmptyBoard()
	solveSudoku(board)
	return { puzzle = createPuzzle(board, BLANK_COUNT.Normal), solution = board, boardType = "Normal" }
end

-- 外部公開：パズル生成
-- difficulty = "Debug" | "Easy" | "Normal" | "Hard"
-- 戻り値: { puzzle, solution, boardType }
function SudokuModule.generate(difficulty)
	if difficulty == "Hard" then
		return generateHard()
	end

	math.randomseed(tick())
	local board = createEmptyBoard()
	solveSudoku(board)

	local blankCount = BLANK_COUNT[difficulty] or BLANK_COUNT.Normal
	local puzzle = createPuzzle(board, blankCount)

	return {
		puzzle    = puzzle,
		solution  = board,
		boardType = "Normal",
	}
end

-- 外部公開：1マスの正解判定
function SudokuModule.isCorrect(solution, row, col, num)
	return solution[row][col] == num
end

return SudokuModule
