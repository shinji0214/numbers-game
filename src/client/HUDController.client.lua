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
local RE_BlockPickedUp    = remoteFolder:WaitForChild("BlockPickedUp")
local RE_BlockDropped     = remoteFolder:WaitForChild("BlockDropped")
local RE_GameStateChanged = remoteFolder:WaitForChild("GameStateChanged")

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
	btnPlace    = Color3.fromRGB(60,  140, 90),
	btnDrop     = Color3.fromRGB(140, 60,  60),
	-- タイル風カラー（鮮やか・ソリッド）
	tilePlace   = Color3.fromRGB(45,  170, 90),
	tileDrop    = Color3.fromRGB(195, 65,  60),
	tileCam     = Color3.fromRGB(55,  105, 210),
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

------------------------------------------------------------------------
-- ボタン定数
-- モバイル: 円形ボタン（直径はピクセル固定、Y位置はスケール指定）
--           AnchorPoint=(1,1) でボタン右下を基点とする
-- PC:       スケールベースの角丸ボタン
------------------------------------------------------------------------

-- モバイル用定数（ビューポート取得で画面サイズ非依存に）
-- ViewportSize は起動直後に (0,0) を返すことがあるため確定まで待機する
local vp = workspace.CurrentCamera.ViewportSize
if vp.X <= 1 then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Wait()
	vp = workspace.CurrentCamera.ViewportSize
end
-- 短辺の17%を直径にする → iPhone SE〜iPad Pro まで適切なサイズに
local M_PX       = math.round(math.min(vp.X, vp.Y) * 0.20)
local M_EDGE_PX  = math.round(M_PX * 0.45)   -- 画面右端からの余白（ジャンプボタンに合わせて左寄せ）
local M_GAP_PX   = math.round(M_PX * 0.40)   -- ボタン間の隙間（押し間違い防止）

-- ボタン高さ・隙間をYスケールに換算（行間計算用）
local M_PX_Y     = M_PX    / vp.Y
local M_GAP_Y    = M_GAP_PX / vp.Y

-- レイアウト（AnchorPoint=(1,1) → Positionはボタン右下コーナーの座標）
--
--   左列X offset  右列X offset
--   [カメラ]      [拾う/置く]   ← 上段 Y = M_UPPER_Y
--   [捨てる]      [Jump※]      ← 下段 Y = M_LOWER_Y
--
-- ※Roblox標準ジャンプボタンは右下に固定（約Y=0.88）

local M_LOWER_Y   = 0.90                          -- 下段ボタン下辺（Jumpと同列）
local M_UPPER_Y   = M_LOWER_Y - M_PX_Y - M_GAP_Y -- 上段ボタン下辺

local M_RIGHT_COL       = M_EDGE_PX                    -- 右列: 右端から M_EDGE_PX
local M_LEFT_COL        = M_EDGE_PX + M_PX + M_GAP_PX -- 左列: 右列の左に隙間を挟む
local M_UPPER_SHIFT_PX  = math.round(M_PX * 0.25)     -- 上段ボタンを右にずらす量

-- PC用スケール定数
local BTN_W      = 0.13
local BTN_H      = 0.07
local BTN_GAP    = 0.012
local BTN_BOTTOM = 0.02

-- color = タイルカラー（tilePlace / tileDrop / tileCam）
-- ボタンアイコン アセットID
local ICON_PICKUP = "rbxassetid://109962355428219"
local ICON_PLACE  = "rbxassetid://110724425029427"
local ICON_DROP   = "rbxassetid://72269721103074"
local ICON_CAM    = "rbxassetid://138754679857357"

local function makeActionButton(parent, pos, size, anchor, imageId, subLabel, color)
	local btn = Instance.new("TextButton", parent)
	btn.AnchorPoint            = anchor
	btn.Position               = pos
	btn.Size                   = size
	btn.BackgroundColor3       = color
	btn.BackgroundTransparency = 0.05
	btn.Text                   = ""
	btn.BorderSizePixel        = 0
	btn.AutoButtonColor        = true
	corner(btn, isMobile and 999 or 12)

	-- アイコン画像（透過PNG）
	local icon = Instance.new("ImageLabel", btn)
	icon.Size                   = UDim2.fromScale(0.65, 0.65)
	icon.Position               = UDim2.fromScale(0.175, 0.04)
	icon.BackgroundTransparency = 1
	icon.Image                  = imageId
	icon.ImageColor3            = Color3.fromRGB(255, 255, 255)
	icon.ScaleType              = Enum.ScaleType.Fit
	icon.ZIndex                 = 2

	-- ラベル（モバイル: アクション名、PC: キー表示）
	local sub = Instance.new("TextLabel", btn)
	sub.Size                   = UDim2.fromScale(1, 0.22)
	sub.Position               = UDim2.fromScale(0, 0.77)
	sub.BackgroundTransparency = 1
	sub.Text                   = subLabel
	sub.TextScaled             = true
	sub.TextColor3             = Color3.fromRGB(255, 255, 255)
	sub.Font                   = Enum.Font.GothamBold
	sub.TextXAlignment         = Enum.TextXAlignment.Center
	sub.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)
	sub.TextStrokeTransparency = 0.4
	sub.ZIndex                 = 3

	return btn, icon
end

-- モバイル: AnchorPoint=(1,1) → Position は「ボタン右下コーナー」の座標
--   X: スクリーン右端からのピクセル負オフセット
--   Y: スケール（M_BTN_BOTTOM_SCALE = ボタン下辺のYスケール）
-- PC: AnchorPoint=(0,0) → 従来通りのスケール指定

-- 捨てるボタン（左列・下段 → Jumpボタンと同じ行）
local dropBtn = makeActionButton(
	screenGui,
	isMobile
		and UDim2.new(1, -M_LEFT_COL, M_LOWER_Y, 0)
		or  UDim2.fromScale(1-(BTN_W*2+BTN_GAP+0.012), 1-BTN_H-BTN_BOTTOM),
	isMobile and UDim2.fromOffset(M_PX, M_PX) or UDim2.fromScale(BTN_W, BTN_H),
	isMobile and Vector2.new(1, 1) or Vector2.new(0, 0),
	ICON_DROP, isMobile and "捨てる" or "[ Q ]", C.tileDrop
)

-- 置く/拾うボタン（右列・上段 → Jumpボタンの上、上段シフト適用）
local placeBtn, placeBtnImage = makeActionButton(
	screenGui,
	isMobile
		and UDim2.new(1, -(M_RIGHT_COL - M_UPPER_SHIFT_PX), M_UPPER_Y, 0)
		or  UDim2.fromScale(1-BTN_W-0.012, 1-BTN_H-BTN_BOTTOM),
	isMobile and UDim2.fromOffset(M_PX, M_PX) or UDim2.fromScale(BTN_W, BTN_H),
	isMobile and Vector2.new(1, 1) or Vector2.new(0, 0),
	ICON_PICKUP, isMobile and "拾う" or "[ E ]", C.tilePlace
)

-- ボタンのアクティブ状態
-- 置く/拾うボタン: 常時アクティブ（手持ちなし→拾う、手持ちあり→置く）
-- 捨てるボタン: 手持ちがあるときのみアクティブ
local placeBtnLabel = placeBtn:FindFirstChildWhichIsA("TextLabel")
local dropBtnLabel  = dropBtn:FindFirstChildWhichIsA("TextLabel")

-- ラベルフェードアウト
local FADE_DELAY   = 3.0   -- 表示してからフェード開始までの秒数
local FADE_TIME    = 1.5   -- フェードアウトにかける秒数
local fadeTweenInfo = TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local fadeThreads = {}  -- ラベルごとの delay スレッド
local fadeTweens  = {}  -- ラベルごとの実行中 Tween

local function fadeLabel(label)
	if not label then return end
	-- 既存の delay スレッドをキャンセル
	if fadeThreads[label] then
		task.cancel(fadeThreads[label])
		fadeThreads[label] = nil
	end
	-- 実行中の Tween をキャンセル
	if fadeTweens[label] then
		fadeTweens[label]:Cancel()
		fadeTweens[label] = nil
	end
	-- 即座に表示状態に戻す
	label.TextTransparency = 0
	-- FADE_DELAY 秒後にフェードアウト開始
	fadeThreads[label] = task.delay(FADE_DELAY, function()
		local tween = TweenService:Create(label, fadeTweenInfo, { TextTransparency = 1 })
		fadeTweens[label] = tween
		tween:Play()
		tween.Completed:Connect(function()
			fadeTweens[label] = nil
		end)
		fadeThreads[label] = nil
	end)
end

local function updateButtonState(holding)
	placeBtn.BackgroundTransparency = 0.1
	placeBtn.Active = true
	if placeBtnImage then
		placeBtnImage.Image = holding and ICON_PLACE or ICON_PICKUP
	end
	if placeBtnLabel and isMobile then
		placeBtnLabel.Text = holding and "置く" or "拾う"
		if holding then fadeLabel(placeBtnLabel) end
	end

	-- 捨てるボタン: 手持ち時のみ（アクティブになった瞬間にラベル再表示）
	dropBtn.BackgroundTransparency = holding and 0.1 or 0.55
	dropBtn.Active = holding
	if holding and isMobile then
		fadeLabel(dropBtnLabel)
	end
end
updateButtonState(false)

-- 起動時: モバイルのみ全ラベルを初期フェードアウト
if isMobile then
	fadeLabel(placeBtnLabel)
	fadeLabel(dropBtnLabel)
end

-- ボタン押下
placeBtn.Activated:Connect(function()
	local actions = _G.PlayerActions
	if actions then actions.tryPlaceOrPickup() end
end)

dropBtn.Activated:Connect(function()
	local actions = _G.PlayerActions
	if actions then actions.tryDrop() end
end)

------------------------------------------------------------------------
-- カメラ切替ボタン（左下）
-- モバイルでのカメラ切替操作をサポート。PCではVキーと併用。
-- 俯瞰中は「通常視点」、通常時は「俯瞰」と表示してトグル。
------------------------------------------------------------------------

-- カメラボタン（モバイル: 置くボタン真上 / PC: 左下）
local CAM_BTN_W = 0.14
local CAM_BTN_H = 0.07

local camBtn = Instance.new("TextButton", screenGui)
camBtn.AnchorPoint = isMobile and Vector2.new(1, 1) or Vector2.new(0, 0)
camBtn.Position = isMobile
	-- 左列・上段（捨てるボタンの真上、上段シフト適用）
	and UDim2.new(1, -(M_LEFT_COL - M_UPPER_SHIFT_PX), M_UPPER_Y, 0)
	or  UDim2.fromScale(0.012, 1 - CAM_BTN_H - 0.02)
camBtn.Size = isMobile
	and UDim2.fromOffset(M_PX, M_PX)
	or  UDim2.fromScale(CAM_BTN_W, CAM_BTN_H)
-- タイル風スタイル
camBtn.BackgroundColor3       = C.tileCam
camBtn.BackgroundTransparency = 0.05
camBtn.Text                   = ""
camBtn.BorderSizePixel        = 0
camBtn.AutoButtonColor        = true
corner(camBtn, isMobile and 999 or 12)

-- アイコン画像
local camBtnIcon = Instance.new("ImageLabel", camBtn)
camBtnIcon.Size                   = UDim2.fromScale(0.65, 0.65)
camBtnIcon.Position               = UDim2.fromScale(0.175, 0.04)
camBtnIcon.BackgroundTransparency = 1
camBtnIcon.Image                  = ICON_CAM
camBtnIcon.ImageColor3            = Color3.fromRGB(255, 255, 255)
camBtnIcon.ScaleType              = Enum.ScaleType.Fit
camBtnIcon.ZIndex                 = 2

-- ラベル
local camBtnSub = Instance.new("TextLabel", camBtn)
camBtnSub.Size                   = UDim2.fromScale(1, 0.22)
camBtnSub.Position               = UDim2.fromScale(0, 0.77)
camBtnSub.BackgroundTransparency = 1
camBtnSub.Text                   = isMobile and "カメラ" or "[ V ]"
camBtnSub.TextScaled             = true
camBtnSub.TextColor3             = Color3.fromRGB(255, 255, 255)
camBtnSub.Font                   = Enum.Font.GothamBold
camBtnSub.TextXAlignment         = Enum.TextXAlignment.Center
camBtnSub.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)
camBtnSub.TextStrokeTransparency = 0.4
camBtnSub.ZIndex                 = 3

-- 俯瞰状態に応じてボタン表示を更新（俯瞰中は背景をオレンジに変えてアクティブ感を演出）
local function updateCamButton(overhead)
	camBtn.BackgroundColor3 = overhead
		and Color3.fromRGB(200, 120, 30)
		or  C.tileCam
end

-- カメラボタン初期フェード（モバイルのみ）
if isMobile then fadeLabel(camBtnSub) end

camBtn.Activated:Connect(function()
	local ctrl = _G.CameraController
	if ctrl then ctrl.toggle() end
	if isMobile then fadeLabel(camBtnSub) end
end)

-- Vキー操作との同期はペナルティループと共用する RenderStepped 内で行う（後述）

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

local lastOverheadState = false

RunService.RenderStepped:Connect(function()
	-- ペナルティカウントダウン
	if penaltyActive then
		local left = penaltyEnd - tick()
		if left <= 0 then
			penaltyActive        = false
			penaltyPanel.Visible = false
		else
			penaltyLabel.Text = string.format("ブロックを落とした！  %.1f秒", left)
		end
	end

	-- カメラボタン表示をVキー操作と同期
	local ctrl = _G.CameraController
	if ctrl then
		local overhead = ctrl.isOverhead()
		if overhead ~= lastOverheadState then
			lastOverheadState = overhead
			updateCamButton(overhead)
		end
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

-- ゲームフェーズに応じてゲームHUDを表示/非表示
RE_GameStateChanged.OnClientEvent:Connect(function(phase, _hostId)
	if phase == "InGame" then
		screenGui.Enabled = true
	elseif phase == "Lobby" then
		-- 結果画面・コンボ・ペナルティを非表示にしてスコア表示をリセット
		resultScreen.Visible  = false
		comboPanel.Visible    = false
		penaltyPanel.Visible  = false
		scoreValueLabel.Text  = "0"
		comboValueLabel.Text  = "×1.0"
		remainLabel.Text      = "残り -- マス"
		screenGui.Enabled     = true
	end
end)

print("[HUDController] loaded")
