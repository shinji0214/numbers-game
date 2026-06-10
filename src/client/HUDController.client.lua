-- HUDController
-- ゲーム中のUI表示
--   - スコア・コンボ
--   - 残りマス数プログレス
--   - ペナルティカウントダウン
--   - クリア結果画面

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local player = Players.LocalPlayer

------------------------------------------------------------------------
-- RemoteEvents
------------------------------------------------------------------------

local remoteFolder   = ReplicatedStorage:WaitForChild("RemoteEvents")
local RE_UpdateScore = remoteFolder:WaitForChild("UpdateScore")
local RE_PenaltyNotify = remoteFolder:WaitForChild("PenaltyNotify")
local RE_BoardReady  = remoteFolder:WaitForChild("BoardReady")
local RE_GameResult  = remoteFolder:WaitForChild("GameResult")

------------------------------------------------------------------------
-- ScreenGui 作成
------------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name            = "HUD"
screenGui.ResetOnSpawn    = false
screenGui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
screenGui.Parent          = player.PlayerGui

------------------------------------------------------------------------
-- カラーパレット
------------------------------------------------------------------------

local C = {
	bg         = Color3.fromRGB(20,  20,  30),
	panel      = Color3.fromRGB(35,  38,  55),
	accent     = Color3.fromRGB(88,  185, 114),
	combo      = Color3.fromRGB(255, 210, 60),
	penalty    = Color3.fromRGB(220, 70,  70),
	text       = Color3.fromRGB(230, 232, 245),
	textDim    = Color3.fromRGB(140, 145, 170),
	gold       = Color3.fromRGB(255, 200, 50),
	silver     = Color3.fromRGB(190, 200, 210),
	bronze     = Color3.fromRGB(200, 140, 80),
}

------------------------------------------------------------------------
-- UIユーティリティ
------------------------------------------------------------------------

local function makeCorner(parent, radius)
	local c = Instance.new("UICorner", parent)
	c.CornerRadius = UDim.new(0, radius or 8)
end

local function makePadding(parent, px)
	local p = Instance.new("UIPadding", parent)
	p.PaddingTop    = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.PaddingLeft   = UDim.new(0, px)
	p.PaddingRight  = UDim.new(0, px)
end

local function makeLabel(parent, text, textSize, color, font)
	local lbl = Instance.new("TextLabel", parent)
	lbl.Size                   = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Text                   = text
	lbl.TextSize               = textSize or 16
	lbl.TextColor3             = color or C.text
	lbl.Font                   = font or Enum.Font.Gotham
	lbl.TextXAlignment         = Enum.TextXAlignment.Center
	lbl.TextYAlignment         = Enum.TextYAlignment.Center
	return lbl
end

------------------------------------------------------------------------
-- スコア・コンボパネル（左上）
------------------------------------------------------------------------

local scorePanel = Instance.new("Frame", screenGui)
scorePanel.Name              = "ScorePanel"
scorePanel.Size              = UDim2.fromOffset(180, 80)
scorePanel.Position          = UDim2.new(0, 16, 0, 16)
scorePanel.BackgroundColor3  = C.panel
scorePanel.BackgroundTransparency = 0.15
makeCorner(scorePanel, 10)
makePadding(scorePanel, 10)

local scoreLayout = Instance.new("UIListLayout", scorePanel)
scoreLayout.FillDirection  = Enum.FillDirection.Vertical
scoreLayout.VerticalAlignment = Enum.VerticalAlignment.Center
scoreLayout.Padding        = UDim.new(0, 2)

-- スコア値
local scoreValueLabel = Instance.new("TextLabel", scorePanel)
scoreValueLabel.Name               = "ScoreValue"
scoreValueLabel.Size               = UDim2.new(1, 0, 0, 36)
scoreValueLabel.BackgroundTransparency = 1
scoreValueLabel.Text               = "0"
scoreValueLabel.TextSize           = 32
scoreValueLabel.TextColor3         = C.text
scoreValueLabel.Font               = Enum.Font.GothamBold
scoreValueLabel.TextXAlignment     = Enum.TextXAlignment.Left

-- スコアラベル
local scoreTitleLabel = Instance.new("TextLabel", scorePanel)
scoreTitleLabel.Name               = "ScoreTitle"
scoreTitleLabel.Size               = UDim2.new(1, 0, 0, 18)
scoreTitleLabel.BackgroundTransparency = 1
scoreTitleLabel.Text               = "SCORE"
scoreTitleLabel.TextSize           = 12
scoreTitleLabel.TextColor3         = C.textDim
scoreTitleLabel.Font               = Enum.Font.Gotham
scoreTitleLabel.TextXAlignment     = Enum.TextXAlignment.Left

------------------------------------------------------------------------
-- コンボ表示（左上・スコアパネル右隣）
------------------------------------------------------------------------

local comboPanel = Instance.new("Frame", screenGui)
comboPanel.Name              = "ComboPanel"
comboPanel.Size              = UDim2.fromOffset(90, 80)
comboPanel.Position          = UDim2.new(0, 204, 0, 16)
comboPanel.BackgroundColor3  = C.panel
comboPanel.BackgroundTransparency = 0.15
comboPanel.Visible           = false  -- コンボ中のみ表示
makeCorner(comboPanel, 10)
makePadding(comboPanel, 8)

local comboLayout = Instance.new("UIListLayout", comboPanel)
comboLayout.FillDirection     = Enum.FillDirection.Vertical
comboLayout.VerticalAlignment = Enum.VerticalAlignment.Center
comboLayout.Padding           = UDim.new(0, 2)

local comboValueLabel = Instance.new("TextLabel", comboPanel)
comboValueLabel.Name               = "ComboValue"
comboValueLabel.Size               = UDim2.new(1, 0, 0, 36)
comboValueLabel.BackgroundTransparency = 1
comboValueLabel.Text               = "×1.0"
comboValueLabel.TextSize           = 24
comboValueLabel.TextColor3         = C.combo
comboValueLabel.Font               = Enum.Font.GothamBold
comboValueLabel.TextXAlignment     = Enum.TextXAlignment.Center

local comboTitleLabel = Instance.new("TextLabel", comboPanel)
comboTitleLabel.Name               = "ComboTitle"
comboTitleLabel.Size               = UDim2.new(1, 0, 0, 18)
comboTitleLabel.BackgroundTransparency = 1
comboTitleLabel.Text               = "COMBO"
comboTitleLabel.TextSize           = 12
comboTitleLabel.TextColor3         = C.textDim
comboTitleLabel.Font               = Enum.Font.Gotham
comboTitleLabel.TextXAlignment     = Enum.TextXAlignment.Center

------------------------------------------------------------------------
-- 残りマス数（右上）
------------------------------------------------------------------------

local remainPanel = Instance.new("Frame", screenGui)
remainPanel.Name              = "RemainPanel"
remainPanel.Size              = UDim2.fromOffset(160, 50)
remainPanel.Position          = UDim2.new(1, -176, 0, 16)
remainPanel.BackgroundColor3  = C.panel
remainPanel.BackgroundTransparency = 0.15
makeCorner(remainPanel, 10)
makePadding(remainPanel, 8)

local remainLabel = Instance.new("TextLabel", remainPanel)
remainLabel.Name               = "RemainLabel"
remainLabel.Size               = UDim2.fromScale(1, 1)
remainLabel.BackgroundTransparency = 1
remainLabel.Text               = "残り -- マス"
remainLabel.TextSize           = 16
remainLabel.TextColor3         = C.text
remainLabel.Font               = Enum.Font.Gotham
remainLabel.TextXAlignment     = Enum.TextXAlignment.Center

------------------------------------------------------------------------
-- スコア加算ポップアップ（スコア横に一瞬出る）
------------------------------------------------------------------------

local gainPopup = Instance.new("TextLabel", screenGui)
gainPopup.Name               = "GainPopup"
gainPopup.Size               = UDim2.fromOffset(120, 36)
gainPopup.Position           = UDim2.new(0, 16, 0, 100)
gainPopup.BackgroundTransparency = 1
gainPopup.Text               = ""
gainPopup.TextSize           = 22
gainPopup.TextColor3         = C.accent
gainPopup.Font               = Enum.Font.GothamBold
gainPopup.TextXAlignment     = Enum.TextXAlignment.Left
gainPopup.TextStrokeTransparency = 0.5
gainPopup.ZIndex             = 10

------------------------------------------------------------------------
-- ペナルティ表示（画面中央下）
------------------------------------------------------------------------

local penaltyPanel = Instance.new("Frame", screenGui)
penaltyPanel.Name              = "PenaltyPanel"
penaltyPanel.Size              = UDim2.fromOffset(280, 52)
penaltyPanel.Position          = UDim2.new(0.5, -140, 1, -90)
penaltyPanel.BackgroundColor3  = C.penalty
penaltyPanel.BackgroundTransparency = 0.15
penaltyPanel.Visible           = false
makeCorner(penaltyPanel, 10)

local penaltyLabel = Instance.new("TextLabel", penaltyPanel)
penaltyLabel.Name              = "PenaltyLabel"
penaltyLabel.Size              = UDim2.fromScale(1, 1)
penaltyLabel.BackgroundTransparency = 1
penaltyLabel.Text              = "ペナルティ  --秒"
penaltyLabel.TextSize          = 18
penaltyLabel.TextColor3        = Color3.fromRGB(255, 255, 255)
penaltyLabel.Font              = Enum.Font.GothamBold
penaltyLabel.TextXAlignment    = Enum.TextXAlignment.Center

------------------------------------------------------------------------
-- 結果画面（クリア時）
------------------------------------------------------------------------

local resultScreen = Instance.new("Frame", screenGui)
resultScreen.Name              = "ResultScreen"
resultScreen.Size              = UDim2.fromScale(1, 1)
resultScreen.BackgroundColor3  = Color3.fromRGB(0, 0, 0)
resultScreen.BackgroundTransparency = 0.4
resultScreen.Visible           = false
resultScreen.ZIndex            = 20

-- 中央パネル
local resultPanel = Instance.new("Frame", resultScreen)
resultPanel.Name              = "ResultPanel"
resultPanel.Size              = UDim2.fromOffset(480, 520)
resultPanel.Position          = UDim2.new(0.5, -240, 0.5, -260)
resultPanel.BackgroundColor3  = C.panel
resultPanel.BackgroundTransparency = 0.05
resultPanel.ZIndex            = 21
makeCorner(resultPanel, 16)

-- タイトル "CLEAR!"
local clearTitle = Instance.new("TextLabel", resultPanel)
clearTitle.Name              = "ClearTitle"
clearTitle.Size              = UDim2.new(1, 0, 0, 70)
clearTitle.Position          = UDim2.new(0, 0, 0, 16)
clearTitle.BackgroundTransparency = 1
clearTitle.Text              = "CLEAR!"
clearTitle.TextSize          = 52
clearTitle.TextColor3        = C.accent
clearTitle.Font              = Enum.Font.GothamBold
clearTitle.TextXAlignment    = Enum.TextXAlignment.Center
clearTitle.ZIndex            = 22

-- ランキングリスト
local rankingFrame = Instance.new("ScrollingFrame", resultPanel)
rankingFrame.Name              = "RankingFrame"
rankingFrame.Size              = UDim2.new(1, -32, 1, -160)
rankingFrame.Position          = UDim2.new(0, 16, 0, 100)
rankingFrame.BackgroundTransparency = 1
rankingFrame.ScrollBarThickness = 4
rankingFrame.ZIndex            = 22

local rankingLayout = Instance.new("UIListLayout", rankingFrame)
rankingLayout.FillDirection    = Enum.FillDirection.Vertical
rankingLayout.Padding          = UDim.new(0, 6)
rankingLayout.SortOrder        = Enum.SortOrder.LayoutOrder

------------------------------------------------------------------------
-- ランキング行を生成
------------------------------------------------------------------------

local RANK_COLORS = {C.gold, C.silver, C.bronze}

local function createRankRow(result, isMe)
	local row = Instance.new("Frame", rankingFrame)
	row.Name              = "Row_" .. result.rank
	row.Size              = UDim2.new(1, 0, 0, 56)
	row.BackgroundColor3  = isMe
		and Color3.fromRGB(60, 80, 60)
		or  Color3.fromRGB(45, 48, 65)
	row.BackgroundTransparency = 0.1
	row.LayoutOrder       = result.rank
	row.ZIndex            = 23
	makeCorner(row, 8)
	makePadding(row, 8)

	-- 順位
	local rankLabel = Instance.new("TextLabel", row)
	rankLabel.Size               = UDim2.new(0, 36, 1, 0)
	rankLabel.Position           = UDim2.new(0, 0, 0, 0)
	rankLabel.BackgroundTransparency = 1
	rankLabel.Text               = tostring(result.rank)
	rankLabel.TextSize           = 26
	rankLabel.TextColor3         = RANK_COLORS[result.rank] or C.textDim
	rankLabel.Font               = Enum.Font.GothamBold
	rankLabel.TextXAlignment     = Enum.TextXAlignment.Center
	rankLabel.ZIndex             = 24

	-- プレイヤー名
	local nameLabel = Instance.new("TextLabel", row)
	nameLabel.Size               = UDim2.new(0, 160, 1, 0)
	nameLabel.Position           = UDim2.new(0, 44, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text               = result.name
	nameLabel.TextSize           = 16
	nameLabel.TextColor3         = isMe and C.accent or C.text
	nameLabel.Font               = isMe and Enum.Font.GothamBold or Enum.Font.Gotham
	nameLabel.TextXAlignment     = Enum.TextXAlignment.Left
	nameLabel.ZIndex             = 24

	-- スコア内訳
	local detailLabel = Instance.new("TextLabel", row)
	detailLabel.Size             = UDim2.new(0, 180, 0.5, 0)
	detailLabel.Position         = UDim2.new(0, 44, 0.5, 0)
	detailLabel.BackgroundTransparency = 1
	detailLabel.Text             = string.format(
		"基本%d  速度+%d  貢献+%d",
		result.baseScore, result.speedBonus, result.contributionBonus
	)
	detailLabel.TextSize         = 11
	detailLabel.TextColor3       = C.textDim
	detailLabel.Font             = Enum.Font.Gotham
	detailLabel.TextXAlignment   = Enum.TextXAlignment.Left
	detailLabel.ZIndex           = 24

	-- 合計スコア
	local totalLabel = Instance.new("TextLabel", row)
	totalLabel.Size              = UDim2.new(0, 80, 1, 0)
	totalLabel.Position          = UDim2.new(1, -80, 0, 0)
	totalLabel.BackgroundTransparency = 1
	totalLabel.Text              = tostring(result.finalScore)
	totalLabel.TextSize          = 24
	totalLabel.TextColor3        = RANK_COLORS[result.rank] or C.text
	totalLabel.Font              = Enum.Font.GothamBold
	totalLabel.TextXAlignment    = Enum.TextXAlignment.Right
	totalLabel.ZIndex            = 24
end

------------------------------------------------------------------------
-- 状態
------------------------------------------------------------------------

local totalCells    = 0
local remainCells   = 0
local penaltyEnd    = 0
local penaltyActive = false
local COMBO_LABELS  = {"×1.0","×1.5","×2.0","×2.5","×3.0"}

------------------------------------------------------------------------
-- スコア更新（ポップアップ付き）
------------------------------------------------------------------------

local popupTween = nil

local function showGainPopup(gain)
	if popupTween then popupTween:Cancel() end
	gainPopup.Text         = "+" .. tostring(gain)
	gainPopup.TextTransparency = 0
	gainPopup.Position     = UDim2.new(0, 16, 0, 100)

	-- 上にフロートして消える
	local tween = TweenService:Create(gainPopup, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position           = UDim2.new(0, 16, 0, 72),
		TextTransparency   = 1,
	})
	popupTween = tween
	tween:Play()
end

RE_UpdateScore.OnClientEvent:Connect(function(score, combo, gain)
	-- スコア更新
	scoreValueLabel.Text = tostring(score)

	-- コンボ表示
	if combo > 1 then
		comboPanel.Visible    = true
		comboValueLabel.Text  = COMBO_LABELS[math.min(combo, #COMBO_LABELS)]
	else
		comboPanel.Visible    = false
	end

	-- 加算ポップアップ
	if gain and gain > 0 then
		showGainPopup(gain)
	end
end)

------------------------------------------------------------------------
-- 残りマス数更新
------------------------------------------------------------------------

RE_BoardReady.OnClientEvent:Connect(function(difficulty, emptyCells)
	totalCells  = emptyCells
	remainCells = emptyCells
	remainLabel.Text = string.format("残り %d マス", remainCells)
	scoreValueLabel.Text = "0"
	comboPanel.Visible   = false
end)

-- UpdateCell を使って残りマス数を減らす
local RE_UpdateCell = remoteFolder:WaitForChild("UpdateCell")
RE_UpdateCell.OnClientEvent:Connect(function(row, col, num, state)
	if state == "correct" then
		remainCells = math.max(0, remainCells - 1)
		remainLabel.Text = remainCells > 0
			and string.format("残り %d マス", remainCells)
			or  "完成！"
	end
end)

------------------------------------------------------------------------
-- ペナルティ表示
------------------------------------------------------------------------

RE_PenaltyNotify.OnClientEvent:Connect(function(remaining)
	penaltyEnd    = tick() + remaining
	penaltyActive = true
	penaltyPanel.Visible = true
end)

-- ペナルティカウントダウン（RunServiceで毎フレーム更新）
local RunService = game:GetService("RunService")
RunService.RenderStepped:Connect(function()
	if not penaltyActive then return end
	local left = penaltyEnd - tick()
	if left <= 0 then
		penaltyActive        = false
		penaltyPanel.Visible = false
	else
		penaltyLabel.Text = string.format("ブロックを落とした！  %.1f秒", left)
	end
end)

------------------------------------------------------------------------
-- 結果画面表示
------------------------------------------------------------------------

RE_GameResult.OnClientEvent:Connect(function(results)
	-- 既存の行を削除
	for _, child in ipairs(rankingFrame:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end

	-- ランキング行を生成
	local myName = player.Name
	for _, result in ipairs(results) do
		local isMe = result.name == myName
		createRankRow(result, isMe)
	end

	-- ScrollingFrame の高さを調整
	rankingFrame.CanvasSize = UDim2.new(0, 0, 0, #results * 62)

	-- 結果画面をフェードイン
	resultScreen.Visible           = true
	resultScreen.BackgroundTransparency = 1
	TweenService:Create(resultScreen, TweenInfo.new(0.5), {
		BackgroundTransparency = 0.4
	}):Play()
end)

print("[HUDController] loaded")
