-- PlayerController
-- プレイヤーの操作処理
--   - 盤面への本置き（Eキー / アクションボタン）
--   - ブロックのドロップ（アクションボタン）
--   ※ 拾う操作は ProximityPrompt（BlockManager）が担当

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()

------------------------------------------------------------------------
-- RemoteEvents
------------------------------------------------------------------------

local remoteFolder     = ReplicatedStorage:WaitForChild("RemoteEvents")
local RE_PlaceBlock    = remoteFolder:WaitForChild("PlaceBlock")
local RE_DropBlock     = remoteFolder:WaitForChild("DropBlock")
local RE_BlockPickedUp = remoteFolder:WaitForChild("BlockPickedUp")
local RE_BlockDropped  = remoteFolder:WaitForChild("BlockDropped")
local RE_PenaltyNotify = remoteFolder:WaitForChild("PenaltyNotify")

------------------------------------------------------------------------
-- 状態
------------------------------------------------------------------------

local heldNumber     = nil
local cooldownUntil  = 0
local PLACE_COOLDOWN = 3
local PLACE_RANGE    = 7

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
-- ドロップ処理
------------------------------------------------------------------------

function TryDrop()
	if not heldNumber then return end
	RE_DropBlock:FireServer()
end

------------------------------------------------------------------------
-- キーボード操作（PC）
-- E: 本置き
-- Q: ドロップ
------------------------------------------------------------------------

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.E then TryPlace() end
	if input.KeyCode == Enum.KeyCode.Q then TryDrop()  end
end)

------------------------------------------------------------------------
-- サーバーからの通知
------------------------------------------------------------------------

RE_BlockPickedUp.OnClientEvent:Connect(function(num)
	heldNumber    = num
	_G.HeldNumber = num
end)

RE_BlockDropped.OnClientEvent:Connect(function()
	heldNumber    = nil
	_G.HeldNumber = nil
end)

RE_PenaltyNotify.OnClientEvent:Connect(function(remaining)
	heldNumber    = nil
	_G.HeldNumber = nil
end)

------------------------------------------------------------------------
-- キャラクター切替時リセット
------------------------------------------------------------------------

player.CharacterAdded:Connect(function(char)
	character  = char
	heldNumber = nil
	_G.HeldNumber = nil
end)

------------------------------------------------------------------------
-- 外部公開（HUDControllerのアクションボタンから呼ばれる）
------------------------------------------------------------------------

_G.PlayerActions = {
	tryPlace = TryPlace,
	tryDrop  = TryDrop,
	getHeldNumber = function() return heldNumber end,
}

print("[PlayerController] loaded")
