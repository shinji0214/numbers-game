-- HUDController
-- ゲーム中のUI表示（スケールベース・モバイル対応）
--   - スコア・コンボ
--   - 残りマス数
--   - ペナルティカウントダウン
--   - アクションボタン（置く・捨てる）
--   - クリア結果画面

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")

local player = Players.LocalPlayer

------------------------------------------------------------------------
-- RemoteEvents
------------------------------------------------------------------------

local remoteFolder     = ReplicatedStorage:WaitForChild("RemoteEvents")
local RE_UpdateScore   = remoteFolder:WaitForChild("UpdateScore")
local RE_PenaltyNotify = remoteFolder:WaitForChild("PenaltyNotify")
local RE_BoardReady    = remoteFolder:WaitForChild("BoardReady")
local RE_GameResult    = remoteFolder:WaitForChild("GameResult")
local RE_UpdateCell    = remoteFolder:WaitForChild("UpdateCell")
local RE_BlockPickedUp = remoteFolder:WaitForChild("BlockPickedUp")
local RE_BlockDropped  = remoteFolder:WaitForChild("BlockDropped")

------------------------------------------------------------------------
-- プラットフォーム判定
-- TouchEnabled かつ KeyboardEnabled でない → モバイル
------------------------------------------------------------------------

local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

------------------------------------------------------------------------
-- ScreenGui
------------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name           = "HUD"
screenGui.ResetOnSpawn   = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent         = player.PlayerGui

------------------------------------------------------------------------
-- カラーパレット
------------------------------------------------------------------------

local C = {
	panel   = Color3.fromRGB(25,  28,  42),
	accent  = Color3.fromRGB(88,  185, 114),
	combo   = Color3.fromRGB(255, 210, 60),
	penalty = Color3.fromRGB(220, 70,  70),
	text    = Color3.fromRGB(230, 232, 245),
	dim     = Color3.fromRGB(130, 135, 160),
	gold    = Color3.fromRGB(255, 200, 50),
	silver  = Color3.fromRGB(190, 200, 210),
	bronze  = Color3.fromRGB(200, 140, 80),
	btnPlace = Color3.fromRGB(60,  140, 90),
	btnDrop  = Color3.fromRGB(140, 60,  60),
}

------------------------------------------------------------------------
-- UIユーティリティ
------------------------------------------------------------------------

local function corner(parent, r)
	local c = Instance.new("UICorner", parent)
	c.CornerRadius = UDim.new(0, r or 8)
end

local function padding(parent, s)
	local p = Instance.new("UIPadding", parent)
	local u = UDim.new(s, 0)
	p.PaddingTop    = u
	p.PaddingBottom = u
	p.PaddingLeft   = u
	p.PaddingRight  = u
end

-- パネル共通スタイル
local function makePanel(parent, pos, size, alpha)
	local f = Instance.new("Frame", parent)
	f.Position              = pos
	f.Size                  = size
	f.BackgroundColor3      = C.panel
	f.BackgroundTransparency = alpha or 0.15
	f.BorderSizePixel       = 0
	corner(f)
	return f
end

local function makeText(parent, text, size, color, bold, xAlign)
	local l = Instance.new("TextLabel", parent)
	l.Size                   = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Text                   = text
	l.TextSize               = size
	l.TextColor3             = color or C.text
	l.Font                   = bold and Enum.Font.GothamBold or Enum.Font.Gotham
	l.TextXAlignment         = xAlign or Enum.TextXAlignment.Center
	l.TextScaled             = false
	return l
end

------------------------------------------------------------------------
-- スケール係数
-- 基準解像度 1280px を基準に TextSize をスケール
------------------------------------------------------------------------

local function getScale()
	local vp = workspace.CurrentCamera.ViewportSize
	return math.clamp(vp.X / 1280, 0.55, 1.5)
end

local function ts(base)
	return math.round(base * getScale())
end

------------------------------------------------------------------------
-- スコアパネル（左上）
-- Size: 画面幅の16%, 高さ画面高さの10%
------------------------------------------------------------------------

local scorePanel = makePanel(screenGui,
	UDim2.fromScale(0.012, 0.016),
	UDim2.fromScale(0.16, 0.10)
)
padding(scorePanel, 0.08)

local scoreLayout = Instance.new("UIListLayout", scorePanel)
scoreLayout.FillDirection     = Enum.FillDirection.Vertical
scoreLayout.VerticalAlignment = Enum.VerticalAlignment.Center
scoreLayout.Padding           = UDim.new(0.04, 0)

local scoreValueLabel = Instance.new("TextLabel", scorePanel)
scoreValueLabel.Size                   = UDim2.new(1, 0, 0.58, 0)
scoreValueLabel.BackgroundTransparency = 1
scoreValueLabel.Text                   = "0"
scoreValueLabel.TextSize               = ts(30)
scoreValueLabel.TextColor3             = C.text
scoreValueLabel.Font                   = Enum.Font.GothamBold
scoreValueLabel.TextXAlignment         = Enum.TextXAlignment.Left

local scoreTitleLabel = Instance.new("TextLabel", scorePanel)
scoreTitleLabel.Size                   = UDim2.new(1, 0, 0.30, 0)
scoreTitleLabel.BackgroundTransparency = 1
scoreTitleLabel.Text                   = "SCORE"
scoreTitleLabel.TextSize               = ts(11)
scoreTitleLabel.TextColor3             = C.dim
scoreTitleLabel.Font                   = Enum.Font.Gotham
scoreTitleLabel.TextXAlignment         = Enum.TextXAlignment.Left

------------------------------------------------------------------------
-- コンボパネル（スコアパネル右隣）
------------------------------------------------------------------------

local comboPanel = makePanel(screenGui,
	UDim2.fromScale(0.178, 0.016),
	UDim2.fromScale(0.09, 0.10)
)
comboPanel.Visible = false
padding(comboPanel, 0.08)

local comboPanelLayout = Instance.new("UIListLayout", comboPanel)
comboPanelLayout.FillDirection     = Enum.FillDirection.Vertical
comboPanelLayout.VerticalAlignment = Enum.VerticalAlignment.Center
comboPanelLayout.Padding           = UDim.new(0.04, 0)

local comboValueLabel = Instance.new("TextLabel", comboPanel)
comboValueLabel.Size                   = UDim2.new(1, 0, 0.58, 0)
comboValueLabel.BackgroundTransparency = 1
comboValueLabel.Text                   = "×1.0"
comboValueLabel.TextSize               = ts(22)
comboValueLabel.TextColor3             = C.combo
comboValueLabel.Font                   = Enum.Font.GothamBold
comboValueLabel.TextXAlignment         = Enum.TextXAlignment.Center

local comboTitleLabel = Instance.new("TextLabel", comboPanel)
comboTitleLabel.Size                   = UDim2.new(1, 0, 0.30, 0)
comboTitleLabel.BackgroundTransparency = 1
comboTitleLabel.Text                   = "COMBO"
comboTitleLabel.TextSize               = ts(10)
comboTitleLabel.TextColor3             = C.dim
comboTitleLabel.Font                   = Enum.Font.Gotham
comboTitleLabel.TextXAlignment         = Enum.TextXAlignment.Center

------------------------------------------------------------------------
-- 残りマスパネル（右上）
------------------------------------------------------------------------

local remainPanel = makePanel(screenGui,
	UDim2.fromScale(0.838, 0.016),
	UDim2.fromScale(0.15, 0.065)
)
padding(remainPanel, 0.1)

local remainLabel = makeText(remainPanel, "残り -- マス", ts(15), C.text)

------------------------------------------------------------------------
-- スコア加算ポップアップ
------------------------------------------------------------------------

local gainPopup = Instance.new("TextLabel", screenGui)
gainPopup.Size                    = UDim2.fromScale(0.1, 0.05)
gainPopup.Position                = UDim2.fromScale(0.012, 0.12)
gainPopup.BackgroundTransparency  = 1
gainPopup.Text                    = ""
gainPopup.TextSize                = ts(22)
gainPopup.TextColor3              = C.accent
gainPopup.Font                    = Enum.Font.GothamBold
gainPopup.TextXAlignment          = Enum.TextXAlignment.Left
gainPopup.TextStrokeTransparency  = 0.4
gainPopup.ZIndex                  = 10

------------------------------------------------------------------------
-- ペナルティパネル（画面下中央）
------------------------------------------------------------------------

local penaltyPanel = makePanel(screenGui,
	UDim2.fromScale(0.35, 0.88),
	UDim2.fromScale(0.30, 0.065),
	0.10
)
penaltyPanel.BackgroundColor3 = C.penalty
penaltyPanel.Visible          = false
padding(penaltyPanel, 0.08)

local penaltyLabel = makeText(penaltyPanel, "ペナルティ  --秒", ts(16),
	Color3.fromRGB(255, 255, 255), true)

------------------------------------------------------------------------
-- アクションボタン（右下）
-- 置く・捨てる
-- モバイルでは大きめのタップ領域を確保
------------------------------------------------------------------------

-- ボタンサイズ：画面幅の12%、アスペクト比 2.5:1
local BTN_W = isMobile and 0.18 or 0.13
local BTN_H = isMobile and 0.09 or 0.07
local BTN_GAP = 0.012

local function makeActionButton(parent, pos, label, subLabel, color)
	local btn = Instance.new("TextButton", parent)
	btn.Position            = pos
	btn.Size                = UDim2.fromScale(BTN_W, BTN_H)
	btn.BackgroundColor3    = color
	btn.BackgroundTransparency = 0.1
	btn.Text                = ""
	btn.BorderSizePixel     = 0
	btn.AutoButtonColor     = true
	corner(btn, 10)

	-- メインラベル
	local main = Instance.new("TextLabel", btn)
	main.Size                   = UDim2.fromScale(1, 0.6)
	main.Position               = UDim2.fromScale(0, 0.08)
	main.BackgroundTransparency = 1
	main.Text                   = label
	main.TextSize               = ts(isMobile and 18 or 16)
	main.TextColor3             = Color3.fromRGB(255, 255, 255)
	main.Font                   = Enum.Font.GothamBold
	main.TextXAlignment         = Enum.TextXAlignment.Center

	-- サブラベル（キー表示）
	if not isMobile then
		local sub = Instance.new("TextLabel", btn)
		sub.Size                   = UDim2.fromScale(1, 0.35)
		sub.Position               = UDim2.fromScale(0, 0.62)
		sub.BackgroundTransparency = 1
		sub.Text                   = subLabel
		sub.TextSize               = ts(10)
		sub.TextColor3             = Color3.fromRGB(200, 200, 200)
		sub.Font                   = Enum.Font.Gotham
		sub.TextXAlignment         = Enum.TextXAlignment.Center
	end

	return btn
end

-- 捨てるボタン（右下左側）
local dropBtnX = 1 - (BTN_W * 2 + BTN_GAP + 0.012)
local dropBtn = makeActionButton(
	screenGui,
	UDim2.fromScale(dropBtnX, 1 - BTN_H - 0.02),
	"捨てる", "[ Q ]",
	C.btnDrop
)

-- 置くボタン（右下右側）
local placeBtnX = 1 - BTN_W - 0.012
local placeBtn = makeActionButton(
	screenGui,
	UDim2.fromScale(placeBtnX, 1 - BTN_H - 0.02),
	"置く", "[ E ]",
	C.btnPlace
)

-- ボタンのアクティブ状態（ブロックを持っていないときは非アクティブ）
local function updateButtonState(holding)
	local alpha = holding and 0.1 or 0.55
	placeBtn.BackgroundTransparency = alpha
	dropBtn.BackgroundTransparency  = alpha
	placeBtn.Active = holding
	dropBtn.Active  = holding
end
updateButtonState(false)

-- ボタン押下
placeBtn.Activated:Connect(function()
	local actions = _G.PlayerActions
	if actions then actions.tryPlace() end
end)

dropBtn.Activated:Connect(function()
	local actions = _G.PlayerActions
	if actions then actions.tryDrop() end
end)

------------------------------------------------------------------------
-- スコア更新
------------------------------------------------------------------------

local COMBO_LABELS = {"×1.0","×1.5","×2.0","×2.5","×3.0"}
local popupTween   = nil

local function showGainPopup(gain)
	if popupTween then popupTween:Cancel() end
	gainPopup.Text              = "+" .. gain
	gainPopup.TextTransparency  = 0
	gainPopup.Position          = UDim2.fromScale(0.012, 0.12)
	popupTween = TweenService:Create(gainPopup,
		TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Position = UDim2.fromScale(0.012, 0.09), TextTransparency = 1}
	)
	popupTween:Play()
end

RE_UpdateScore.OnClientEvent:Connect(function(score, combo, gain)
	scoreValueLabel.Text = tostring(score)
	if combo > 1 then
		comboPanel.Visible   = true
		comboValueLabel.Text = COMBO_LABELS[math.min(combo, #COMBO_LABELS)]
	else
		comboPanel.Visible = false
	end
	if gain and gain > 0 then showGainPopup(gain) end
end)

------------------------------------------------------------------------
-- ブロック取得/解放 → ボタン状態更新
------------------------------------------------------------------------

RE_BlockPickedUp.OnClientEvent:Connect(function()
	updateButtonState(true)
end)

RE_BlockDropped.OnClientEvent:Connect(function()
	updateButtonState(false)
end)

RE_PenaltyNotify.OnClientEvent:Connect(function()
	updateButtonState(false)
end)

------------------------------------------------------------------------
-- 残りマス数
------------------------------------------------------------------------

RE_BoardReady.OnClientEvent:Connect(function(difficulty, emptyCells)
	remainLabel.Text     = string.format("残り %d マス", emptyCells)
	scoreValueLabel.Text = "0"
	comboPanel.Visible   = false
	updateButtonState(false)
end)

RE_UpdateCell.OnClientEvent:Connect(function(row, col, num, state)
	if state ~= "correct" then return end
	local current = tonumber(remainLabel.Text:match("%d+")) or 0
	local next    = math.max(0, current - 1)
	remainLabel.Text = next > 0
		and string.format("残り %d マス", next)
		or  "完成！"
end)

------------------------------------------------------------------------
-- ペナルティカウントダウン
------------------------------------------------------------------------

local penaltyEnd    = 0
local penaltyActive = false

RE_PenaltyNotify.OnClientEvent:Connect(function(remaining)
	penaltyEnd    = tick() + remaining
	penaltyActive = true
	penaltyPanel.Visible = true
end)

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
-- 結果画面
------------------------------------------------------------------------

local RANK_COLORS = {C.gold, C.silver, C.bronze}

local resultScreen = Instance.new("Frame", screenGui)
resultScreen.Size                    = UDim2.fromScale(1, 1)
resultScreen.BackgroundColor3        = Color3.fromRGB(0, 0, 0)
resultScreen.BackgroundTransparency  = 1
resultScreen.Visible                 = false
resultScreen.ZIndex                  = 20
resultScreen.BorderSizePixel         = 0

local resultPanel = makePanel(resultScreen,
	UDim2.fromScale(0.5 - 0.2, 0.06),
	UDim2.fromScale(0.40, 0.88),
	0.05
)
resultPanel.ZIndex = 21
corner(resultPanel, 16)

local clearTitle = makeText(resultPanel, "CLEAR!", ts(48), C.accent, true)
clearTitle.Size     = UDim2.fromScale(1, 0.13)
clearTitle.Position = UDim2.fromScale(0, 0.02)
clearTitle.ZIndex   = 22

local rankingFrame = Instance.new("ScrollingFrame", resultPanel)
rankingFrame.Size               = UDim2.fromScale(0.94, 0.82)
rankingFrame.Position           = UDim2.fromScale(0.03, 0.16)
rankingFrame.BackgroundTransparency = 1
rankingFrame.ScrollBarThickness = 4
rankingFrame.BorderSizePixel    = 0
rankingFrame.ZIndex             = 22

local rankingLayout = Instance.new("UIListLayout", rankingFrame)
rankingLayout.FillDirection = Enum.FillDirection.Vertical
rankingLayout.Padding       = UDim.new(0.012, 0)
rankingLayout.SortOrder     = Enum.SortOrder.LayoutOrder

local function createRankRow(result, isMe)
	local row = Instance.new("Frame", rankingFrame)
	row.Name              = "Row_" .. result.rank
	row.Size              = UDim2.new(1, 0, 0, 0)
	-- 高さを相対スケールで設定
	local rowH = Instance.new("UISizeConstraint", row)
	rowH.MaxSize = Vector2.new(math.huge, math.huge)
	row.Size = UDim2.fromScale(1, 0.13)
	row.BackgroundColor3 = isMe
		and Color3.fromRGB(50, 75, 55)
		or  Color3.fromRGB(38, 42, 60)
	row.BackgroundTransparency = 0.1
	row.LayoutOrder = result.rank
	row.ZIndex = 23
	corner(row, 8)
	padding(row, 0.06)

	-- 順位
	local rankLbl = makeText(row, tostring(result.rank), ts(24),
		RANK_COLORS[result.rank] or C.dim, true)
	rankLbl.Size     = UDim2.fromScale(0.12, 1)
	rankLbl.Position = UDim2.fromScale(0, 0)
	rankLbl.ZIndex   = 24

	-- 名前
	local nameLbl = makeText(row, result.name, ts(15),
		isMe and C.accent or C.text, isMe)
	nameLbl.Size           = UDim2.fromScale(0.42, 0.55)
	nameLbl.Position       = UDim2.fromScale(0.13, 0.04)
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.ZIndex         = 24

	-- 内訳
	local detailLbl = makeText(row,
		string.format("基本%d  速度+%d  貢献+%d",
			result.baseScore, result.speedBonus, result.contributionBonus),
		ts(10), C.dim)
	detailLbl.Size           = UDim2.fromScale(0.55, 0.40)
	detailLbl.Position       = UDim2.fromScale(0.13, 0.54)
	detailLbl.TextXAlignment = Enum.TextXAlignment.Left
	detailLbl.ZIndex         = 24

	-- 合計
	local totalLbl = makeText(row, tostring(result.finalScore), ts(22),
		RANK_COLORS[result.rank] or C.text, true)
	totalLbl.Size           = UDim2.fromScale(0.28, 1)
	totalLbl.Position       = UDim2.fromScale(0.72, 0)
	totalLbl.TextXAlignment = Enum.TextXAlignment.Right
	totalLbl.ZIndex         = 24
end

RE_GameResult.OnClientEvent:Connect(function(results)
	for _, child in ipairs(rankingFrame:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end

	local myName = player.Name
	for _, result in ipairs(results) do
		createRankRow(result, result.name == myName)
	end

	rankingFrame.CanvasSize = UDim2.fromScale(0, #results * 0.15)

	resultScreen.Visible                = true
	resultScreen.BackgroundTransparency = 1
	TweenService:Create(resultScreen, TweenInfo.new(0.5), {
		BackgroundTransparency = 0.45
	}):Play()
end)

print("[HUDController] loaded")
