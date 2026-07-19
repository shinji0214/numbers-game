-- PlayerController
-- プレイヤーの操作処理
--   - 盤面への本置き（Eキー / アクションボタン）
--   - ブロックのドロップ（アクションボタン）
--   - 頭上の持ち数字表示（BillboardGui）
--   ※ 拾う操作は ProximityPrompt（BlockManager）が担当

local Players                = game:GetService("Players")
local UserInputService       = game:GetService("UserInputService")
local ReplicatedStorage      = game:GetService("ReplicatedStorage")
local StarterGui             = game:GetService("StarterGui")
local ProximityPromptService = game:GetService("ProximityPromptService")

-- Roblox標準のバックパック（ホットバー）UIを非表示にする
-- Tool装備時に画面下部に "NumberBlock" が表示されるのを防ぐ
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

local player    = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()

------------------------------------------------------------------------
-- RemoteEvents
------------------------------------------------------------------------

local remoteFolder      = ReplicatedStorage:WaitForChild("RemoteEvents")
local RE_PlaceBlock     = remoteFolder:WaitForChild("PlaceBlock")
local RE_DropBlock      = remoteFolder:WaitForChild("DropBlock")
local RE_PickupNearest  = remoteFolder:WaitForChild("PickupNearest")
local RE_BlockPickedUp  = remoteFolder:WaitForChild("BlockPickedUp")
local RE_BlockDropped   = remoteFolder:WaitForChild("BlockDropped")
local RE_PenaltyNotify  = remoteFolder:WaitForChild("PenaltyNotify")

------------------------------------------------------------------------
-- 状態
------------------------------------------------------------------------

local heldNumber     = nil
local cooldownUntil  = 0
local PLACE_COOLDOWN = 3
local PLACE_RANGE    = 7

------------------------------------------------------------------------
-- 数字カラーテーブル（BlockManager と同一）
------------------------------------------------------------------------

local NUMBER_COLORS = {
	Color3.fromRGB(230, 80,  80),
	Color3.fromRGB(230, 150, 60),
	Color3.fromRGB(220, 210, 60),
	Color3.fromRGB(80,  190, 90),
	Color3.fromRGB(60,  160, 220),
	Color3.fromRGB(100, 90,  210),
	Color3.fromRGB(210, 90,  190),
	Color3.fromRGB(90,  190, 190),
	Color3.fromRGB(160, 120, 80),
}

------------------------------------------------------------------------
-- 頭上 BillboardGui
------------------------------------------------------------------------

local function removeHeadLabel()
	local char = player.Character
	if not char then return end
	local head = char:FindFirstChild("Head")
	if not head then return end
	local existing = head:FindFirstChild("HeldNumberBillboard")
	if existing then existing:Destroy() end
end

local function showHeadLabel(num)
	local char = player.Character
	if not char then return end
	local head = char:FindFirstChild("Head")
	if not head then return end

	removeHeadLabel()

	local color = NUMBER_COLORS[num] or Color3.fromRGB(255, 255, 255)

	local billboard = Instance.new("BillboardGui")
	billboard.Name            = "HeldNumberBillboard"
	billboard.Size            = UDim2.fromOffset(64, 64)
	billboard.StudsOffset     = Vector3.new(0, 2.8, 0)
	billboard.AlwaysOnTop     = false
	billboard.ResetOnSpawn    = false
	billboard.Parent          = head

	-- 背景円（数字カラー）
	local bg = Instance.new("Frame")
	bg.Size                   = UDim2.fromScale(1, 1)
	bg.BackgroundColor3       = color
	bg.BorderSizePixel        = 0
	bg.Parent                 = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius       = UDim.new(1, 0)   -- 完全な円
	corner.Parent             = bg

	-- 数字テキスト
	local label = Instance.new("TextLabel")
	label.Size                = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled          = true
	label.Text                = tostring(num)
	label.TextColor3          = Color3.fromRGB(255, 255, 255)
	label.Font                = Enum.Font.GothamBold
	label.Parent              = bg
end

------------------------------------------------------------------------
-- 最も近いセルを探す
------------------------------------------------------------------------

local function getNearestCell()
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil, nil end

	local board = workspace:FindFirstChild("Board")
	if not board then return nil, nil end

	local nearest, nearestDist = nil, PLACE_RANGE
	local nearRow, nearCol = nil, nil

	for _, cell in ipairs(board:GetChildren()) do
		if cell:IsA("BasePart") and cell.Name:match("^Cell_%d+_%d+$") then
			if not cell:GetAttribute("IsLocked") then
				local dist = (hrp.Position - cell.Position).Magnitude
				if dist < nearestDist then
					nearest     = cell
					nearestDist = dist
					nearRow     = cell:GetAttribute("Row")
					nearCol     = cell:GetAttribute("Col")
				end
			end
		end
	end

	return nearRow, nearCol
end

------------------------------------------------------------------------
-- 本置き処理
------------------------------------------------------------------------

function TryPlace()
	if not heldNumber then return end
	if tick() < cooldownUntil then return end

	local row, col = getNearestCell()
	if row and col then
		RE_PlaceBlock:FireServer(row, col, heldNumber)
		cooldownUntil = tick() + PLACE_COOLDOWN
	end
end

------------------------------------------------------------------------
-- 拾う処理（UIボタン用：最近のブロックをサーバーに拾わせる）
------------------------------------------------------------------------

function TryPickup()
	if heldNumber then return end
	RE_PickupNearest:FireServer()
end

------------------------------------------------------------------------
-- 置く / 拾うの統合（手持ちがあれば置く、なければ拾う）
------------------------------------------------------------------------

function TryPlaceOrPickup()
	if heldNumber then
		TryPlace()
	else
		TryPickup()
	end
end

------------------------------------------------------------------------
-- ドロップ処理
------------------------------------------------------------------------

function TryDrop()
	if not heldNumber then return end
	RE_DropBlock:FireServer()
end

------------------------------------------------------------------------
-- キーボード操作（PC）
-- E: 置く / 拾う（統合）
-- Q: ドロップ
------------------------------------------------------------------------

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.E then TryPlaceOrPickup() end
	if input.KeyCode == Enum.KeyCode.Q then TryDrop()          end
end)

------------------------------------------------------------------------
-- サーバーからの通知
------------------------------------------------------------------------

RE_BlockPickedUp.OnClientEvent:Connect(function(num)
	heldNumber    = num
	_G.HeldNumber = num
	showHeadLabel(num)
end)

RE_BlockDropped.OnClientEvent:Connect(function()
	heldNumber    = nil
	_G.HeldNumber = nil
	removeHeadLabel()
end)

RE_PenaltyNotify.OnClientEvent:Connect(function(remaining)
	heldNumber    = nil
	_G.HeldNumber = nil
	removeHeadLabel()
end)

------------------------------------------------------------------------
-- キャラクター切替時リセット
------------------------------------------------------------------------

player.CharacterAdded:Connect(function(char)
	character  = char
	heldNumber = nil
	_G.HeldNumber = nil
	-- リスポーン後にラベルが残ることを防ぐ（新しいcharacterには存在しないが念のため）
	removeHeadLabel()
end)

------------------------------------------------------------------------
-- 外部公開（HUDControllerのアクションボタンから呼ばれる）
------------------------------------------------------------------------

_G.PlayerActions = {
	tryPlace          = TryPlace,
	tryPickup         = TryPickup,
	tryPlaceOrPickup  = TryPlaceOrPickup,
	tryDrop           = TryDrop,
	getHeldNumber     = function() return heldNumber end,
}

------------------------------------------------------------------------
-- カスタム ProximityPrompt UI（数字カラー付きBillboardGui）
-- BlockManager で Style=Custom にしているため、
-- PromptShown/PromptHidden でオリジナルUIを表示・非表示する
------------------------------------------------------------------------

local PROMPT_BILLBOARD_NAME = "PickupPromptBillboard"
local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local function createPromptBillboard(part, num)
	-- 既存があれば削除
	local existing = part:FindFirstChild(PROMPT_BILLBOARD_NAME)
	if existing then existing:Destroy() end

	local color = NUMBER_COLORS[num] or Color3.fromRGB(255, 255, 255)

	local billboard = Instance.new("BillboardGui")
	billboard.Name         = PROMPT_BILLBOARD_NAME
	billboard.Size         = UDim2.fromOffset(90, 44)
	billboard.StudsOffset  = Vector3.new(0, 2.5, 0)
	billboard.AlwaysOnTop  = false
	billboard.ResetOnSpawn = false
	billboard.Parent       = part

	-- 背景
	local bg = Instance.new("Frame", billboard)
	bg.Size                   = UDim2.fromScale(1, 1)
	bg.BackgroundColor3       = color
	bg.BackgroundTransparency = 0.1
	bg.BorderSizePixel        = 0
	local c = Instance.new("UICorner", bg)
	c.CornerRadius = UDim.new(0, 8)

	-- 数字（左側）
	local numLbl = Instance.new("TextLabel", bg)
	numLbl.Size                   = UDim2.fromScale(0.32, 1)
	numLbl.Position               = UDim2.fromScale(0, 0)
	numLbl.BackgroundTransparency = 1
	numLbl.Text                   = tostring(num)
	numLbl.TextScaled             = true
	numLbl.TextColor3             = Color3.fromRGB(255, 255, 255)
	numLbl.Font                   = Enum.Font.GothamBold

	-- 区切り線
	local divider = Instance.new("Frame", bg)
	divider.Size              = UDim2.fromScale(0.02, 0.7)
	divider.Position          = UDim2.fromScale(0.33, 0.15)
	divider.BackgroundColor3  = Color3.fromRGB(255, 255, 255)
	divider.BackgroundTransparency = 0.5
	divider.BorderSizePixel   = 0

	-- 右側テキスト（"拾う" / "[E] 拾う"）
	local actionLbl = Instance.new("TextLabel", bg)
	actionLbl.Size                   = UDim2.fromScale(0.62, 1)
	actionLbl.Position               = UDim2.fromScale(0.36, 0)
	actionLbl.BackgroundTransparency = 1
	actionLbl.Text                   = isMobile and "拾う" or "[E] 拾う"
	actionLbl.TextScaled             = true
	actionLbl.TextColor3             = Color3.fromRGB(255, 255, 255)
	actionLbl.Font                   = Enum.Font.GothamBold
end

local function removePromptBillboard(part)
	local b = part:FindFirstChild(PROMPT_BILLBOARD_NAME)
	if b then b:Destroy() end
end

ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
	local part = prompt.Parent
	if not part or not part:IsA("BasePart") then return end
	local num = part:GetAttribute("Number")
	if not num then return end
	createPromptBillboard(part, num)
end)

ProximityPromptService.PromptHidden:Connect(function(prompt)
	local part = prompt.Parent
	if part then removePromptBillboard(part) end
end)

print("[PlayerController] loaded")
