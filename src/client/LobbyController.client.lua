-- LobbyController
-- ロビーUI・ゲーム状態に応じた画面管理
--   - 看板 / ハンバーガーメニュー起点の設定UI
--   - カウントダウンアナウンスバナー
--   - 暗転フェード（ゲーム開始・終了時）
--   - 次ゲーム確認UI（ホスト向け）

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

------------------------------------------------------------------------
-- RemoteEvents
------------------------------------------------------------------------

local remoteFolder       = ReplicatedStorage:WaitForChild("RemoteEvents")
local RE_GameStateChanged = remoteFolder:WaitForChild("GameStateChanged")
local RE_ConfigResult     = remoteFolder:WaitForChild("ConfigResult")
local RE_OpenConfig       = remoteFolder:WaitForChild("OpenConfig")
local RE_CloseConfig      = remoteFolder:WaitForChild("CloseConfig")
local RE_RequestStart     = remoteFolder:WaitForChild("RequestStart")
local RE_CountdownUpdate  = remoteFolder:WaitForChild("CountdownUpdate")
local RE_CancelCountdown  = remoteFolder:WaitForChild("CancelCountdown")
local RE_PlayAgain        = remoteFolder:WaitForChild("PlayAgain")

------------------------------------------------------------------------
-- 状態
------------------------------------------------------------------------

local isMobile      = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local currentPhase  = "Lobby"
local currentHostId = nil
local selectedDiff  = "Normal"
local isConfigOwner = false  -- 自分が設定UIを開いているか

------------------------------------------------------------------------
-- UIヘルパー
------------------------------------------------------------------------

local function corner(inst, radius)
	Instance.new("UICorner", inst).CornerRadius = UDim.new(0, radius or 8)
end

local function makeLabel(parent, text, size, color, bold)
	local lbl = Instance.new("TextLabel", parent)
	lbl.BackgroundTransparency = 1
	lbl.Text       = text
	lbl.TextScaled = false
	lbl.TextSize   = size
	lbl.TextColor3 = color or Color3.fromRGB(255, 255, 255)
	lbl.Font       = bold and Enum.Font.GothamBold or Enum.Font.Gotham
	lbl.TextXAlignment = Enum.TextXAlignment.Center
	lbl.TextYAlignment = Enum.TextYAlignment.Center
	return lbl
end

local function makeButton(parent, text, size, bgColor)
	local btn = Instance.new("TextButton", parent)
	btn.BackgroundColor3 = bgColor or Color3.fromRGB(60, 130, 90)
	btn.Text             = text
	btn.TextSize         = size
	btn.TextColor3       = Color3.fromRGB(255, 255, 255)
	btn.Font             = Enum.Font.GothamBold
	btn.BorderSizePixel  = 0
	btn.AutoButtonColor  = true
	corner(btn, 10)
	return btn
end

------------------------------------------------------------------------
-- 暗転フェード ScreenGui
------------------------------------------------------------------------

local fadeGui = Instance.new("ScreenGui")
fadeGui.Name         = "FadeGui"
fadeGui.ResetOnSpawn = false
fadeGui.DisplayOrder = 200
fadeGui.Parent       = playerGui

local fadeFrame = Instance.new("Frame", fadeGui)
fadeFrame.Size                   = UDim2.fromScale(1, 1)
fadeFrame.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
fadeFrame.BackgroundTransparency = 1
fadeFrame.BorderSizePixel        = 0

local function fadeToBlack(dur)
	TweenService:Create(fadeFrame, TweenInfo.new(dur or 0.5, Enum.EasingStyle.Linear),
		{ BackgroundTransparency = 0 }):Play()
	task.wait(dur or 0.5)
end

local function fadeToClear(dur)
	TweenService:Create(fadeFrame, TweenInfo.new(dur or 0.5, Enum.EasingStyle.Linear),
		{ BackgroundTransparency = 1 }):Play()
	task.wait(dur or 0.5)
end

------------------------------------------------------------------------
-- カウントダウンアナウンスバナー（全員向け・画面上部）
------------------------------------------------------------------------

local bannerGui = Instance.new("ScreenGui")
bannerGui.Name         = "CountdownBanner"
bannerGui.ResetOnSpawn = false
bannerGui.DisplayOrder = 30
bannerGui.Enabled      = false
bannerGui.Parent       = playerGui

local bannerFrame = Instance.new("Frame", bannerGui)
bannerFrame.AnchorPoint      = Vector2.new(0.5, 0)
bannerFrame.Position         = UDim2.fromScale(0.5, 0.04)
bannerFrame.Size             = UDim2.fromScale(isMobile and 0.85 or 0.5, 0)
bannerFrame.AutomaticSize    = Enum.AutomaticSize.Y
bannerFrame.BackgroundColor3 = Color3.fromRGB(15, 18, 30)
bannerFrame.BackgroundTransparency = 0.1
bannerFrame.BorderSizePixel  = 0
corner(bannerFrame, 12)

local bannerPadding = Instance.new("UIPadding", bannerFrame)
bannerPadding.PaddingTop    = UDim.new(0, 12)
bannerPadding.PaddingBottom = UDim.new(0, 12)
bannerPadding.PaddingLeft   = UDim.new(0, 16)
bannerPadding.PaddingRight  = UDim.new(0, 16)

local bannerLayout = Instance.new("UIListLayout", bannerFrame)
bannerLayout.FillDirection       = Enum.FillDirection.Vertical
bannerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
bannerLayout.Padding             = UDim.new(0, 6)

local bannerText = makeLabel(bannerFrame, "ゲームが10秒後に始まります",
	isMobile and 14 or 16, Color3.fromRGB(255, 240, 100), true)
bannerText.Size        = UDim2.new(1, 0, 0, isMobile and 22 or 26)
bannerText.LayoutOrder = 1

-- ホストのみ表示されるキャンセルボタン
local cancelBtn = makeButton(bannerFrame, "キャンセル", isMobile and 12 or 13,
	Color3.fromRGB(160, 60, 60))
cancelBtn.Size        = UDim2.new(0, isMobile and 110 or 120, 0, isMobile and 28 or 32)
cancelBtn.LayoutOrder = 2
cancelBtn.Visible     = false

cancelBtn.Activated:Connect(function()
	RE_CancelCountdown:FireServer()
end)

------------------------------------------------------------------------
-- 設定UI ScreenGui（看板・ハンバーガー起点、開いた人のみ表示）
------------------------------------------------------------------------

local configGui = Instance.new("ScreenGui")
configGui.Name         = "ConfigUI"
configGui.ResetOnSpawn = false
configGui.DisplayOrder = 20
configGui.Enabled      = false
configGui.Parent       = playerGui

local configPanel = Instance.new("Frame", configGui)
configPanel.AnchorPoint      = Vector2.new(0.5, 0.5)
configPanel.Position         = UDim2.fromScale(0.5, 0.5)
configPanel.Size             = UDim2.fromScale(isMobile and 0.78 or 0.38, 0)
configPanel.AutomaticSize    = Enum.AutomaticSize.Y
configPanel.BackgroundColor3 = Color3.fromRGB(20, 24, 36)
configPanel.BackgroundTransparency = 0.05
configPanel.BorderSizePixel  = 0
corner(configPanel, 16)

local configPad = Instance.new("UIPadding", configPanel)
configPad.PaddingTop    = UDim.new(0, 20)
configPad.PaddingBottom = UDim.new(0, 20)
configPad.PaddingLeft   = UDim.new(0, 20)
configPad.PaddingRight  = UDim.new(0, 20)

local configLayout = Instance.new("UIListLayout", configPanel)
configLayout.FillDirection       = Enum.FillDirection.Vertical
configLayout.Padding             = UDim.new(0, 12)
configLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

-- タイトル行（タイトル + 閉じるボタン）
local titleRow = Instance.new("Frame", configPanel)
titleRow.Size             = UDim2.new(1, 0, 0, isMobile and 36 or 42)
titleRow.BackgroundTransparency = 1
titleRow.LayoutOrder      = 1

local configTitle = makeLabel(titleRow, "ゲーム設定",
	isMobile and 20 or 22, Color3.fromRGB(88, 185, 114), true)
configTitle.Size     = UDim2.new(1, -40, 1, 0)
configTitle.Position = UDim2.fromOffset(0, 0)

local closeBtn = Instance.new("TextButton", titleRow)
closeBtn.Size            = UDim2.fromOffset(32, 32)
closeBtn.Position        = UDim2.new(1, -32, 0.5, -16)
closeBtn.BackgroundColor3 = Color3.fromRGB(80, 40, 40)
closeBtn.Text            = "✕"
closeBtn.TextSize        = 16
closeBtn.TextColor3      = Color3.fromRGB(220, 180, 180)
closeBtn.Font            = Enum.Font.GothamBold
closeBtn.BorderSizePixel = 0
corner(closeBtn, 6)

closeBtn.Activated:Connect(function()
	configGui.Enabled = false
	isConfigOwner     = false
	RE_CloseConfig:FireServer()
end)

-- 区切り線
local div = Instance.new("Frame", configPanel)
div.Size             = UDim2.new(1, 0, 0, 1)
div.BackgroundColor3 = Color3.fromRGB(50, 55, 80)
div.BorderSizePixel  = 0
div.LayoutOrder      = 2

-- 難易度ラベル
local diffLabel = makeLabel(configPanel, "難易度",
	isMobile and 13 or 14, Color3.fromRGB(130, 135, 160))
diffLabel.Size        = UDim2.new(1, 0, 0, 20)
diffLabel.LayoutOrder = 3

-- 難易度ボタン行
local diffRow = Instance.new("Frame", configPanel)
diffRow.Size             = UDim2.new(1, 0, 0, isMobile and 38 or 44)
diffRow.BackgroundTransparency = 1
diffRow.LayoutOrder      = 4

local diffBtnLayout = Instance.new("UIListLayout", diffRow)
diffBtnLayout.FillDirection       = Enum.FillDirection.Horizontal
diffBtnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
diffBtnLayout.Padding             = UDim.new(0, 6)

local DIFF_OPTIONS = { "Easy",    "Normal", "Hard"      }
local DIFF_LABELS  = { "かんたん", "ふつう",  "むずかしい" }
local diffButtons  = {}

local COLOR_DIFF_ON  = Color3.fromRGB(55, 120, 185)
local COLOR_DIFF_OFF = Color3.fromRGB(38, 44, 64)

local function updateDiffButtons()
	for i, diff in ipairs(DIFF_OPTIONS) do
		diffButtons[i].BackgroundColor3 =
			(diff == selectedDiff) and COLOR_DIFF_ON or COLOR_DIFF_OFF
	end
end

for i, diff in ipairs(DIFF_OPTIONS) do
	local btn = makeButton(diffRow, DIFF_LABELS[i], isMobile and 12 or 13, COLOR_DIFF_OFF)
	btn.Size        = UDim2.new(0, isMobile and 80 or 88, 1, 0)
	btn.LayoutOrder = i
	diffButtons[i]  = btn
	local cap = diff
	btn.Activated:Connect(function()
		selectedDiff = cap
		updateDiffButtons()
	end)
end
updateDiffButtons()

-- スタートボタン
local startBtn = makeButton(configPanel, "ゲームスタート",
	isMobile and 15 or 17, Color3.fromRGB(60, 160, 90))
startBtn.Size        = UDim2.new(1, 0, 0, isMobile and 44 or 50)
startBtn.LayoutOrder = 5

startBtn.Activated:Connect(function()
	if not isConfigOwner then return end
	RE_RequestStart:FireServer(selectedDiff)
	-- カウントダウン開始後は設定UIを閉じる
	configGui.Enabled = false
	isConfigOwner     = false
end)

------------------------------------------------------------------------
-- ハンバーガーメニュー ScreenGui（常時表示・右上）
------------------------------------------------------------------------

local hamburgerGui = Instance.new("ScreenGui")
hamburgerGui.Name         = "HamburgerMenu"
hamburgerGui.ResetOnSpawn = false
hamburgerGui.DisplayOrder = 15
hamburgerGui.Parent       = playerGui

-- ≡ ボタン
local hamburgerBtn = Instance.new("TextButton", hamburgerGui)
hamburgerBtn.AnchorPoint      = Vector2.new(1, 0)
hamburgerBtn.Position         = UDim2.fromScale(0.98, 0.02)
hamburgerBtn.Size             = UDim2.fromOffset(isMobile and 44 or 40, isMobile and 44 or 40)
hamburgerBtn.BackgroundColor3 = Color3.fromRGB(30, 34, 50)
hamburgerBtn.BackgroundTransparency = 0.2
hamburgerBtn.Text             = "≡"
hamburgerBtn.TextSize         = isMobile and 22 or 20
hamburgerBtn.TextColor3       = Color3.fromRGB(200, 205, 225)
hamburgerBtn.Font             = Enum.Font.GothamBold
hamburgerBtn.BorderSizePixel  = 0
hamburgerBtn.AutoButtonColor  = true
corner(hamburgerBtn, 8)

-- プルダウンメニュー
local menuPopup = Instance.new("Frame", hamburgerGui)
menuPopup.AnchorPoint      = Vector2.new(1, 0)
menuPopup.Position         = UDim2.fromScale(0.98, isMobile and 0.095 or 0.085)
menuPopup.Size             = UDim2.fromOffset(isMobile and 160 or 150, 0)
menuPopup.AutomaticSize    = Enum.AutomaticSize.Y
menuPopup.BackgroundColor3 = Color3.fromRGB(20, 24, 36)
menuPopup.BackgroundTransparency = 0.05
menuPopup.BorderSizePixel  = 0
menuPopup.Visible          = false
corner(menuPopup, 10)

local menuPad = Instance.new("UIPadding", menuPopup)
menuPad.PaddingTop    = UDim.new(0, 6)
menuPad.PaddingBottom = UDim.new(0, 6)
menuPad.PaddingLeft   = UDim.new(0, 4)
menuPad.PaddingRight  = UDim.new(0, 4)

local menuLayout = Instance.new("UIListLayout", menuPopup)
menuLayout.FillDirection = Enum.FillDirection.Vertical
menuLayout.Padding       = UDim.new(0, 2)

-- メニュー項目：ゲーム設定
local menuStartItem = makeButton(menuPopup, "⚙  ゲーム設定",
	isMobile and 13 or 13, Color3.fromRGB(38, 44, 64))
menuStartItem.Size        = UDim2.new(1, 0, 0, isMobile and 38 or 34)
menuStartItem.LayoutOrder = 1
menuStartItem.TextXAlignment = Enum.TextXAlignment.Left

local menuStartPad = Instance.new("UIPadding", menuStartItem)
menuStartPad.PaddingLeft = UDim.new(0, 10)

menuStartItem.Activated:Connect(function()
	menuPopup.Visible = false
	if currentPhase == "Lobby" then
		RE_OpenConfig:FireServer()
	end
end)

hamburgerBtn.Activated:Connect(function()
	menuPopup.Visible = not menuPopup.Visible
end)

-- メニュー外クリックで閉じる
hamburgerGui.DescendantAdded:Connect(function() end)  -- placeholder
local function closeMenuOnClick()
	if menuPopup.Visible then
		menuPopup.Visible = false
	end
end

------------------------------------------------------------------------
-- 次ゲーム確認UI（ホスト向け・Result フェーズ）
------------------------------------------------------------------------

local playAgainGui = Instance.new("ScreenGui")
playAgainGui.Name         = "PlayAgainUI"
playAgainGui.ResetOnSpawn = false
playAgainGui.DisplayOrder = 50
playAgainGui.Enabled      = false
playAgainGui.Parent       = playerGui

local agPanel = Instance.new("Frame", playAgainGui)
agPanel.AnchorPoint      = Vector2.new(0.5, 0.5)
agPanel.Position         = UDim2.fromScale(0.5, 0.72)
agPanel.Size             = UDim2.fromScale(isMobile and 0.72 or 0.32, 0)
agPanel.AutomaticSize    = Enum.AutomaticSize.Y
agPanel.BackgroundColor3 = Color3.fromRGB(20, 24, 36)
agPanel.BackgroundTransparency = 0.05
agPanel.BorderSizePixel  = 0
corner(agPanel, 14)

local agPad = Instance.new("UIPadding", agPanel)
agPad.PaddingTop    = UDim.new(0, 18)
agPad.PaddingBottom = UDim.new(0, 18)
agPad.PaddingLeft   = UDim.new(0, 18)
agPad.PaddingRight  = UDim.new(0, 18)

local agLayout = Instance.new("UIListLayout", agPanel)
agLayout.FillDirection       = Enum.FillDirection.Vertical
agLayout.Padding             = UDim.new(0, 12)
agLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

local agTitle = makeLabel(agPanel, "もう一度プレイしますか？",
	isMobile and 15 or 17, Color3.fromRGB(230, 232, 245), true)
agTitle.Size        = UDim2.new(1, 0, 0, 28)
agTitle.LayoutOrder = 1

local agBtnRow = Instance.new("Frame", agPanel)
agBtnRow.Size             = UDim2.new(1, 0, 0, isMobile and 42 or 46)
agBtnRow.BackgroundTransparency = 1
agBtnRow.LayoutOrder      = 2

local agBtnLayout = Instance.new("UIListLayout", agBtnRow)
agBtnLayout.FillDirection       = Enum.FillDirection.Horizontal
agBtnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
agBtnLayout.Padding             = UDim.new(0, 10)

local yesBtn = makeButton(agBtnRow, "はい",   isMobile and 15 or 16, Color3.fromRGB(60, 160, 90))
yesBtn.Size        = UDim2.new(0, isMobile and 100 or 110, 1, 0)
yesBtn.LayoutOrder = 1

local noBtn  = makeButton(agBtnRow, "いいえ", isMobile and 15 or 16, Color3.fromRGB(160, 60, 60))
noBtn.Size        = UDim2.new(0, isMobile and 100 or 110, 1, 0)
noBtn.LayoutOrder = 2

yesBtn.Activated:Connect(function()
	playAgainGui.Enabled = false
	RE_PlayAgain:FireServer(true)
end)

noBtn.Activated:Connect(function()
	playAgainGui.Enabled = false
	RE_PlayAgain:FireServer(false)
end)

------------------------------------------------------------------------
-- ハンバーガーメニューの表示制御（フェーズ連動）
------------------------------------------------------------------------

local function setHamburgerVisible(visible)
	hamburgerGui.Enabled = visible
end

------------------------------------------------------------------------
-- カウントダウンバナーの更新
------------------------------------------------------------------------

local function showBanner(secondsLeft)
	bannerGui.Enabled    = true
	bannerText.Text      = string.format("ゲームが %d 秒後に始まります", secondsLeft)
	cancelBtn.Visible    = (player.UserId == currentHostId)
end

local function hideBanner()
	bannerGui.Enabled = false
end

------------------------------------------------------------------------
-- イベント受信
------------------------------------------------------------------------

-- 設定UI開放結果
RE_ConfigResult.OnClientEvent:Connect(function(success, data)
	if success then
		isConfigOwner = true
		if type(data) == "string" then
			selectedDiff = data
			updateDiffButtons()
		end
		configGui.Enabled = true
	else
		-- 失敗メッセージを一瞬バナーで表示
		bannerGui.Enabled = true
		bannerText.Text   = data or "設定を開けませんでした"
		cancelBtn.Visible = false
		task.delay(2, function()
			if not (bannerGui.Enabled and cancelBtn.Visible == false) then return end
			bannerGui.Enabled = false
		end)
	end
end)

-- カウントダウン更新
RE_CountdownUpdate.OnClientEvent:Connect(function(secondsLeft)
	if secondsLeft == nil then
		-- キャンセルされた
		hideBanner()
		currentHostId = nil
		return
	end
	if secondsLeft > 0 then
		showBanner(secondsLeft)
	else
		hideBanner()
	end
end)

-- フェーズ変化
local prevPhase = "Lobby"

RE_GameStateChanged.OnClientEvent:Connect(function(phase, hostId)
	currentHostId = hostId
	currentPhase  = phase

	-- Lobby → InGame: 暗転→ワープ待機→明転
	if prevPhase == "Lobby" and phase == "InGame" then
		task.spawn(function()
			fadeToBlack(0.5)
			hideBanner()
			setHamburgerVisible(false)
			task.wait(1.5)
			fadeToClear(0.5)
		end)

	-- Result → Lobby or InGame: 暗転→ワープ待機→明転
	elseif prevPhase == "Result" and (phase == "Lobby" or phase == "InGame") then
		task.spawn(function()
			fadeToBlack(0.5)
			playAgainGui.Enabled = false
			task.wait(1.5)
			if phase == "Lobby" then
				setHamburgerVisible(true)
			end
			fadeToClear(0.5)
		end)

	elseif phase == "Lobby" then
		setHamburgerVisible(true)
		configGui.Enabled = false
		isConfigOwner     = false

	elseif phase == "InGame" then
		setHamburgerVisible(false)
		configGui.Enabled = false
		isConfigOwner     = false

	elseif phase == "Result" then
		setHamburgerVisible(false)

	elseif phase == "Result_HostPrompt" then
		if player.UserId == hostId then
			playAgainGui.Enabled = true
		end
	end

	if phase ~= "Result_HostPrompt" then
		prevPhase = phase
	end
end)

------------------------------------------------------------------------
-- 初期化
------------------------------------------------------------------------

setHamburgerVisible(true)

print("[LobbyController] loaded")
