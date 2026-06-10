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
	Easy   = 32,
	Normal = 45,
	Hard   = 55, -- Hard(変形盤面)は別途対応予定
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

-- 外部公開：パズル生成
-- difficulty = "Easy" | "Normal" | "Hard"
-- 戻り値: { puzzle = 盤面(0が空きマス), solution = 正解盤面 }
function SudokuModule.generate(difficulty)
	math.randomseed(tick())
	local board = createEmptyBoard()
	solveSudoku(board)

	local blankCount = BLANK_COUNT[difficulty] or BLANK_COUNT.Normal
	local puzzle = createPuzzle(board, blankCount)

	return {
		puzzle   = puzzle,   -- プレイヤーに見せる盤面（0=空き）
		solution = board,    -- 正解盤面（サーバーのみ保持）
	}
end

-- 外部公開：1マスの正解判定
function SudokuModule.isCorrect(solution, row, col, num)
	return solution[row][col] == num
end

return SudokuModule
