-- LobbyController
-- ロビーUI・ゲーム状態に応じた画面管理
--   - ロビーUI（難易度選択・スタートボタン）
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

local remoteFolder        = ReplicatedStorage:WaitForChild("RemoteEvents")
local RE_GameStateChanged = remoteFolder:WaitForChild("GameStateChanged")
local RE_RequestStart     = remoteFolder:WaitForChild("RequestStart")
local RE_PlayAgain        = remoteFolder:WaitForChild("PlayAgain")

------------------------------------------------------------------------
-- 状態
------------------------------------------------------------------------

local isMobile      = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local currentPhase  = "Lobby"
local currentHostId = nil
local selectedDiff  = "Normal"

------------------------------------------------------------------------
-- UIヘルパー
------------------------------------------------------------------------

local function corner(inst, radius)
	local c = Instance.new("UICorner", inst)
	c.CornerRadius = UDim.new(0, radius or 8)
end

local function makeLabel(parent, text, size, color, bold)
	local lbl = Instance.new("TextLabel", parent)
	lbl.BackgroundTransparency = 1
	lbl.Text                   = text
	lbl.TextScaled             = false
	lbl.TextSize               = size
	lbl.TextColor3             = color or Color3.fromRGB(255, 255, 255)
	lbl.Font                   = bold and Enum.Font.GothamBold or Enum.Font.Gotham
	lbl.TextXAlignment         = Enum.TextXAlignment.Center
	lbl.TextYAlignment         = Enum.TextYAlignment.Center
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
-- 暗転フェード ScreenGui（DisplayOrder 最高にして全UIの上に被せる）
------------------------------------------------------------------------

local fadeGui = Instance.new("ScreenGui")
fadeGui.Name          = "FadeGui"
fadeGui.ResetOnSpawn  = false
fadeGui.DisplayOrder  = 200
fadeGui.Parent        = playerGui

local fadeFrame = Instance.new("Frame", fadeGui)
fadeFrame.Size                   = UDim2.fromScale(1, 1)
fadeFrame.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
fadeFrame.BackgroundTransparency = 1
fadeFrame.BorderSizePixel        = 0

local function fadeToBlack(dur)
	local t = TweenService:Create(fadeFrame,
		TweenInfo.new(dur or 0.5, Enum.EasingStyle.Linear),
		{ BackgroundTransparency = 0 })
	t:Play()
	task.wait(dur or 0.5)
end

local function fadeToClear(dur)
	local t = TweenService:Create(fadeFrame,
		TweenInfo.new(dur or 0.5, Enum.EasingStyle.Linear),
		{ BackgroundTransparency = 1 })
	t:Play()
	task.wait(dur or 0.5)
end

------------------------------------------------------------------------
-- ロビー ScreenGui
------------------------------------------------------------------------

local lobbyGui = Instance.new("ScreenGui")
lobbyGui.Name          = "LobbyUI"
lobbyGui.ResetOnSpawn  = false
lobbyGui.DisplayOrder  = 10
lobbyGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
lobbyGui.Parent        = playerGui

-- メインパネル（画面右下・アクションボタンと被らない中央寄り）
local panel = Instance.new("Frame", lobbyGui)
panel.AnchorPoint        = Vector2.new(0.5, 0.5)
panel.Position           = UDim2.fromScale(0.5, 0.52)
panel.Size               = UDim2.fromScale(isMobile and 0.75 or 0.36, 0)
panel.AutomaticSize      = Enum.AutomaticSize.Y
panel.BackgroundColor3   = Color3.fromRGB(20, 24, 36)
panel.BackgroundTransparency = 0.1
panel.BorderSizePixel    = 0
corner(panel, 16)

local padding = Instance.new("UIPadding", panel)
padding.PaddingTop    = UDim.new(0, 20)
padding.PaddingBottom = UDim.new(0, 20)
padding.PaddingLeft   = UDim.new(0, 20)
padding.PaddingRight  = UDim.new(0, 20)

local layout = Instance.new("UIListLayout", panel)
layout.FillDirection = Enum.FillDirection.Vertical
layout.Padding       = UDim.new(0, 12)
layout.SortOrder     = Enum.SortOrder.LayoutOrder
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center

-- タイトル
local titleLbl = makeLabel(panel, "数 独", isMobile and 28 or 32,
	Color3.fromRGB(88, 185, 114), true)
titleLbl.Size        = UDim2.new(1, 0, 0, isMobile and 36 or 44)
titleLbl.LayoutOrder = 1

-- 区切り線
local divider = Instance.new("Frame", panel)
divider.Size             = UDim2.new(1, 0, 0, 1)
divider.BackgroundColor3 = Color3.fromRGB(60, 65, 90)
divider.BorderSizePixel  = 0
divider.LayoutOrder      = 2

-- 難易度ラベル
local diffLabel = makeLabel(panel, "難易度", isMobile and 13 or 14,
	Color3.fromRGB(130, 135, 160))
diffLabel.Size        = UDim2.new(1, 0, 0, 20)
diffLabel.LayoutOrder = 3

-- 難易度ボタン行
local diffRow = Instance.new("Frame", panel)
diffRow.Size             = UDim2.new(1, 0, 0, isMobile and 38 or 44)
diffRow.BackgroundTransparency = 1
diffRow.LayoutOrder      = 4

local diffLayout = Instance.new("UIListLayout", diffRow)
diffLayout.FillDirection       = Enum.FillDirection.Horizontal
diffLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
diffLayout.Padding             = UDim.new(0, 6)

local DIFF_OPTIONS = { "Easy", "Normal", "Hard" }
local DIFF_LABELS  = { "かんたん", "ふつう", "むずかしい" }
local diffButtons  = {}

local COLOR_DIFF_ACTIVE   = Color3.fromRGB(55, 120, 185)
local COLOR_DIFF_INACTIVE = Color3.fromRGB(38, 44, 64)

local function updateDiffButtons()
	for i, diff in ipairs(DIFF_OPTIONS) do
		local btn = diffButtons[i]
		btn.BackgroundColor3 = (diff == selectedDiff)
			and COLOR_DIFF_ACTIVE or COLOR_DIFF_INACTIVE
	end
end

for i, diff in ipairs(DIFF_OPTIONS) do
	local btn = makeButton(diffRow, DIFF_LABELS[i], isMobile and 12 or 13, COLOR_DIFF_INACTIVE)
	btn.Size         = UDim2.new(0, isMobile and 80 or 90, 1, 0)
	btn.LayoutOrder  = i
	diffButtons[i]   = btn
	local captured   = diff
	btn.Activated:Connect(function()
		selectedDiff = captured
		updateDiffButtons()
	end)
end
updateDiffButtons()

-- スタートボタン（ホストのみ表示）
local startBtn = makeButton(panel, "ゲームスタート", isMobile and 15 or 17,
	Color3.fromRGB(60, 160, 90))
startBtn.Size        = UDim2.new(1, 0, 0, isMobile and 44 or 50)
startBtn.LayoutOrder = 5

startBtn.Activated:Connect(function()
	if currentPhase ~= "Lobby" then return end
	if player.UserId ~= currentHostId then return end
	RE_RequestStart:FireServer(selectedDiff)
end)

-- 非ホスト向けメッセージ
local waitLabel = makeLabel(panel, "ホストの開始を待っています...",
	isMobile and 12 or 13, Color3.fromRGB(130, 135, 160))
waitLabel.Size        = UDim2.new(1, 0, 0, isMobile and 36 or 42)
waitLabel.LayoutOrder = 5  -- startBtn と同じ順位で排他表示

-- 参加人数
local playerCountLbl = makeLabel(panel, "参加者: 1人",
	isMobile and 12 or 13, Color3.fromRGB(100, 105, 130))
playerCountLbl.Size        = UDim2.new(1, 0, 0, 20)
playerCountLbl.LayoutOrder = 6

------------------------------------------------------------------------
-- 次ゲーム確認UI（ホスト向け・Result フェーズ）
------------------------------------------------------------------------

local playAgainGui = Instance.new("ScreenGui")
playAgainGui.Name          = "PlayAgainUI"
playAgainGui.ResetOnSpawn  = false
playAgainGui.DisplayOrder  = 50
playAgainGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
playAgainGui.Enabled       = false
playAgainGui.Parent        = playerGui

local agPanel = Instance.new("Frame", playAgainGui)
agPanel.AnchorPoint      = Vector2.new(0.5, 0.5)
agPanel.Position         = UDim2.fromScale(0.5, 0.72)
agPanel.Size             = UDim2.fromScale(isMobile and 0.7 or 0.3, 0)
agPanel.AutomaticSize    = Enum.AutomaticSize.Y
agPanel.BackgroundColor3 = Color3.fromRGB(20, 24, 36)
agPanel.BackgroundTransparency = 0.05
agPanel.BorderSizePixel  = 0
corner(agPanel, 14)

local agPadding = Instance.new("UIPadding", agPanel)
agPadding.PaddingTop    = UDim.new(0, 18)
agPadding.PaddingBottom = UDim.new(0, 18)
agPadding.PaddingLeft   = UDim.new(0, 18)
agPadding.PaddingRight  = UDim.new(0, 18)

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

local yesBtn = makeButton(agBtnRow, "はい", isMobile and 15 or 16,
	Color3.fromRGB(60, 160, 90))
yesBtn.Size        = UDim2.new(0, isMobile and 100 or 110, 1, 0)
yesBtn.LayoutOrder = 1

local noBtn = makeButton(agBtnRow, "いいえ", isMobile and 15 or 16,
	Color3.fromRGB(160, 60, 60))
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
-- UI表示切替
------------------------------------------------------------------------

local function updatePlayerCount()
	local count = #Players:GetPlayers()
	playerCountLbl.Text = string.format("参加者: %d人", count)
end

local function applyPhase(phase, hostId)
	local isHost = (player.UserId == hostId)

	if phase == "Lobby" then
		lobbyGui.Enabled    = true
		startBtn.Visible    = isHost
		waitLabel.Visible   = not isHost
		playAgainGui.Enabled = false

	elseif phase == "InGame" then
		lobbyGui.Enabled    = false
		playAgainGui.Enabled = false

	elseif phase == "Result" then
		lobbyGui.Enabled    = false
		playAgainGui.Enabled = false  -- 通常は非表示。Result_HostPrompt で表示

	elseif phase == "Result_HostPrompt" then
		-- ホストのみ次ゲーム確認UIを表示
		if isHost then
			playAgainGui.Enabled = true
		end
	end
end

------------------------------------------------------------------------
-- 状態変化時の暗転処理
------------------------------------------------------------------------

local prevPhase = "Lobby"

RE_GameStateChanged.OnClientEvent:Connect(function(phase, hostId)
	currentHostId = hostId
	currentPhase  = phase

	local isHost = (player.UserId == hostId)

	-- Lobby → InGame: 暗転→ワープ（サーバー側）→明転
	if prevPhase == "Lobby" and phase == "InGame" then
		task.spawn(function()
			fadeToBlack(0.5)
			task.wait(1.5)  -- ワープ完了を待つ
			applyPhase(phase, hostId)
			fadeToClear(0.5)
		end)

	-- InGame → Result: 暗転なし（結果画面がそのまま表示される）
	elseif prevPhase == "InGame" and phase == "Result" then
		applyPhase(phase, hostId)

	-- Result → Lobby or InGame（次ゲーム）: 暗転→ワープ→明転
	elseif prevPhase == "Result" and (phase == "Lobby" or phase == "InGame") then
		task.spawn(function()
			fadeToBlack(0.5)
			task.wait(1.5)
			applyPhase(phase, hostId)
			fadeToClear(0.5)
		end)

	else
		applyPhase(phase, hostId)
	end

	prevPhase = (phase ~= "Result_HostPrompt") and phase or prevPhase
	updatePlayerCount()
end)

------------------------------------------------------------------------
-- プレイヤー人数の追従
------------------------------------------------------------------------

Players.PlayerAdded:Connect(updatePlayerCount)
Players.PlayerRemoving:Connect(updatePlayerCount)

------------------------------------------------------------------------
-- 初期化
------------------------------------------------------------------------

updatePlayerCount()
applyPhase("Lobby", nil)

print("[LobbyController] loaded")
