-- PlayerController
-- プレイヤーの操作処理
--   - ブロックを拾う（Eキー / モバイルタップ）
--   - 盤面に置く（Eキー / モバイルタップ）
--   - ブロックを持っているときの頭上表示

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local player    = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local camera    = workspace.CurrentCamera

------------------------------------------------------------------------
-- RemoteEvents
------------------------------------------------------------------------

local remoteFolder  = ReplicatedStorage:WaitForChild("RemoteEvents")
local RE_PickupBlock   = remoteFolder:WaitForChild("PickupBlock")
local RE_PlaceBlock    = remoteFolder:WaitForChild("PlaceBlock")
local RE_BlockPickedUp = remoteFolder:WaitForChild("BlockPickedUp")
local RE_BlockDropped  = remoteFolder:WaitForChild("BlockDropped")
local RE_PenaltyNotify = remoteFolder:WaitForChild("PenaltyNotify")

------------------------------------------------------------------------
-- 状態
------------------------------------------------------------------------

local heldNumber   = nil    -- 現在持っているブロックの数字（nil=持っていない）
local cooldownUntil = 0     -- 本置きクールダウン終了時刻
local PLACE_COOLDOWN = 3    -- 秒
local PICKUP_RANGE   = 8    -- ブロックを拾える距離 (studs)
local PLACE_RANGE    = 5    -- マスに置ける距離 (studs)

------------------------------------------------------------------------
-- 頭上のブロック表示（BillboardGui）
------------------------------------------------------------------------

local billboard = Instance.new("BillboardGui")
billboard.Name          = "HeldBlockDisplay"
billboard.Size          = UDim2.fromOffset(60, 60)
billboard.StudsOffset   = Vector3.new(0, 3, 0)
billboard.AlwaysOnTop   = false
billboard.ResetOnSpawn  = false

local billboardLabel = Instance.new("TextLabel", billboard)
billboardLabel.Size                 = UDim2.fromScale(1, 1)
billboardLabel.BackgroundTransparency = 1
billboardLabel.TextScaled           = true
billboardLabel.Font                 = Enum.Font.GothamBold
billboardLabel.Text                 = ""
billboardLabel.TextColor3           = Color3.fromRGB(255, 255, 80)
billboardLabel.TextStrokeTransparency = 0.3

local function attachBillboard()
	character = player.Character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp then
		billboard.Adornee = hrp
		billboard.Parent  = hrp
	end
end

player.CharacterAdded:Connect(function(char)
	character = char
	heldNumber = nil
	attachBillboard()
end)
attachBillboard()

local function updateBillboard()
	if heldNumber then
		billboardLabel.Text = tostring(heldNumber)
	else
		billboardLabel.Text = ""
	end
end

------------------------------------------------------------------------
-- 最も近いブロックを探す
------------------------------------------------------------------------

local function getNearestBlock()
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end

	local blockFolder = workspace:FindFirstChild("Blocks")
	if not blockFolder then return nil end

	local nearest, nearestDist = nil, PICKUP_RANGE

	for _, block in ipairs(blockFolder:GetChildren()) do
		if block:IsA("BasePart") and not block:GetAttribute("IsHeld") then
			local dist = (hrp.Position - block.Position).Magnitude
			if dist < nearestDist then
				nearest     = block
				nearestDist = dist
			end
		end
	end

	return nearest
end

------------------------------------------------------------------------
-- 最も近いセルを探す
------------------------------------------------------------------------

local function getNearestCell()
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil, nil, nil end

	local board = workspace:FindFirstChild("Board")
	if not board then return nil, nil, nil end

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

	return nearest, nearRow, nearCol
end

------------------------------------------------------------------------
-- E キー / タップでの操作
------------------------------------------------------------------------

local function onAction()
	local now = tick()

	if heldNumber == nil then
		-- ブロックを持っていない → 拾う
		local block = getNearestBlock()
		if block then
			RE_PickupBlock:FireServer(block)
		end
	else
		-- ブロックを持っている → 置く
		if now < cooldownUntil then return end  -- クールダウン中

		local _, row, col = getNearestCell()
		if row and col then
			RE_PlaceBlock:FireServer(row, col, heldNumber)
			cooldownUntil = now + PLACE_COOLDOWN
		end
	end
end

-- キーボード（PC）
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.E then
		onAction()
	end
end)

-- モバイル用のタップはCameraControllerと共存させるため後で実装
-- TODO: モバイル対応

------------------------------------------------------------------------
-- サーバーからの通知
------------------------------------------------------------------------

RE_BlockPickedUp.OnClientEvent:Connect(function(num)
	heldNumber     = num
	_G.HeldNumber  = num  -- MarkerControllerと共有
	updateBillboard()
end)

RE_BlockDropped.OnClientEvent:Connect(function()
	heldNumber    = nil
	_G.HeldNumber = nil
	updateBillboard()
end)

RE_PenaltyNotify.OnClientEvent:Connect(function(remaining)
	heldNumber    = nil
	_G.HeldNumber = nil
	updateBillboard()
	-- TODO: HUDにペナルティ残り時間を表示
	print(string.format("[PlayerController] Penalty: %.1f sec remaining", remaining))
end)

------------------------------------------------------------------------
-- 持っているブロックをキャラクター前方に浮かせる（視覚演出）
------------------------------------------------------------------------

RunService.RenderStepped:Connect(function()
	if not heldNumber then return end
	-- TODO: 手に持ったブロックの3Dモデル演出（将来対応）
end)

print("[PlayerController] loaded")
