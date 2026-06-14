-- BlockManager
-- 数字ブロックのスポーン・拾う・消費・ドロップ・リスポーン管理

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players             = game:GetService("Players")

------------------------------------------------------------------------
-- 定数
------------------------------------------------------------------------

local BLOCK_SIZE      = 2.5
local BLOCK_HEIGHT    = 1.2
local BLOCK_Y         = 1.0
local BOARD_SPAN      = 90
local EDGE_OFFSET     = 20
local BLOCK_SPACING   = 6
local DESPAWN_TIME    = 15
local PICKUP_DISTANCE = 10   -- ProximityPrompt の MaxActivationDistance と合わせる

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
-- ServerEvents / RemoteEvents
------------------------------------------------------------------------

local serverEventsFolder = ServerScriptService:WaitForChild("ServerEvents")
local BE_SpawnBlocks   = serverEventsFolder:WaitForChild("SpawnBlocks")
local BE_ConsumeBlock  = serverEventsFolder:WaitForChild("ConsumeBlock")
local BE_ApplyPenalty  = serverEventsFolder:WaitForChild("ApplyPenalty")
local BF_GetHeldNumber = serverEventsFolder:WaitForChild("GetHeldNumber")

local remoteFolder     = ReplicatedStorage:WaitForChild("RemoteEvents")
local RE_PenaltyNotify = remoteFolder:WaitForChild("PenaltyNotify")

local function getOrCreate(name, class)
	local r = remoteFolder:FindFirstChild(name)
	if not r then
		r = Instance.new(class)
		r.Name   = name
		r.Parent = remoteFolder
	end
	return r
end
local RE_BlockPickedUp = getOrCreate("BlockPickedUp", "RemoteEvent")
local RE_BlockDropped  = getOrCreate("BlockDropped",  "RemoteEvent")
local RE_DropBlock     = getOrCreate("DropBlock",     "RemoteEvent")  -- クライアント → サーバー: 任意ドロップ

------------------------------------------------------------------------
-- 状態管理
------------------------------------------------------------------------

local blockFolder  = Instance.new("Folder")
blockFolder.Name   = "Blocks"
blockFolder.Parent = workspace

local spawnPoints  = {}  -- [part] = originalCFrame
local heldBlocks   = {}  -- [userId] = part（ワールド上のblock Part）
local penaltyUntil = {}  -- [userId] = tick()

------------------------------------------------------------------------
-- Tool 生成・装備（手持ちモデル）
------------------------------------------------------------------------

local function createAndEquipTool(player, num)
	local char = player.Character
	if not char then return end

	-- 既存のツールがあれば削除
	for _, obj in ipairs(char:GetChildren()) do
		if obj:IsA("Tool") and obj.Name == "NumberBlock" then
			obj:Destroy()
		end
	end

	local tool = Instance.new("Tool")
	tool.Name           = "NumberBlock"
	tool.RequiresHandle = true
	tool.CanBeDropped   = false   -- バックパックUIからドロップ不可
	tool.ToolTip        = tostring(num)
	tool:SetAttribute("Number", num)

	-- ハンドル（手に持つ見た目）
	local handle = Instance.new("Part")
	handle.Name          = "Handle"
	handle.Size          = Vector3.new(BLOCK_SIZE, BLOCK_HEIGHT, BLOCK_SIZE)
	handle.Color         = NUMBER_COLORS[num]
	handle.Material      = Enum.Material.SmoothPlastic
	handle.TopSurface    = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	handle.CastShadow    = false

	-- ハンドル上面に数字表示
	local gui = Instance.new("SurfaceGui")
	gui.Name       = "BlockGui"
	gui.Face       = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(80, 80)
	gui.Parent     = handle

	local label = Instance.new("TextLabel")
	label.Size                   = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled             = true
	label.Text                   = tostring(num)
	label.TextColor3             = Color3.fromRGB(255, 255, 255)
	label.Font                   = Enum.Font.GothamBold
	label.Parent                 = gui

	handle.Parent = tool

	-- キャラクターに直接追加 → 即装備
	tool.Parent = char
end

local function removeHeldTool(player)
	local char = player.Character
	if not char then return end
	for _, obj in ipairs(char:GetChildren()) do
		if obj:IsA("Tool") and obj.Name == "NumberBlock" then
			obj:Destroy()
			return
		end
	end
end

------------------------------------------------------------------------
-- ブロック Part 生成（ProximityPrompt 付き）
------------------------------------------------------------------------

local function createBlockPart(num, position)
	local part = Instance.new("Part")
	part.Name          = "NumberBlock_" .. num
	part.Size          = Vector3.new(BLOCK_SIZE, BLOCK_HEIGHT, BLOCK_SIZE)
	part.Position      = position
	part.Anchored      = true
	part.TopSurface    = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material      = Enum.Material.SmoothPlastic
	part.Color         = NUMBER_COLORS[num]
	part.CastShadow    = false

	part:SetAttribute("Number",      num)
	part:SetAttribute("IsHeld",      false)
	part:SetAttribute("IsDespawning", false)

	-- 上面に数字
	local gui = Instance.new("SurfaceGui")
	gui.Name       = "BlockGui"
	gui.Face       = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(80, 80)
	gui.Parent     = part

	local label = Instance.new("TextLabel")
	label.Size                   = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled             = true
	label.Text                   = tostring(num)
	label.TextColor3             = Color3.fromRGB(255, 255, 255)
	label.Font                   = Enum.Font.GothamBold
	label.Parent                 = gui

	local rot = Instance.new("UIRotation")
	rot.Rotation = -90
	rot.Parent   = label

	-- ProximityPrompt（拾うUI）
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText           = "拾う"
	prompt.ObjectText           = tostring(num)
	prompt.KeyboardKeyCode      = Enum.KeyCode.E
	prompt.MaxActivationDistance = PICKUP_DISTANCE
	prompt.HoldDuration         = 0       -- 押しっぱなし不要
	prompt.RequiresLineOfSight  = false
	prompt.Enabled              = true
	prompt.Parent               = part

	-- ProximityPrompt が Triggered されたらサーバー側で拾う処理
	prompt.Triggered:Connect(function(player)
		handlePickupBlock(player, part)
	end)

	part.Parent = blockFolder
	return part
end

------------------------------------------------------------------------
-- スポーン座標生成（四辺ランダム配置）
------------------------------------------------------------------------

local function generateSpawnPositions(blockList)
	local half  = BOARD_SPAN / 2 + EDGE_OFFSET
	local sides = {
		function(t) return Vector3.new(t,     BLOCK_Y,  half) end,
		function(t) return Vector3.new(t,     BLOCK_Y, -half) end,
		function(t) return Vector3.new( half, BLOCK_Y,  t)    end,
		function(t) return Vector3.new(-half, BLOCK_Y,  t)    end,
	}

	local shuffled = {table.unpack(blockList)}
	for k = #shuffled, 2, -1 do
		local r = math.random(k)
		shuffled[k], shuffled[r] = shuffled[r], shuffled[k]
	end

	local perSide     = math.ceil(#shuffled / 4)
	local sideIndex   = 1
	local countInSide = 0
	local result      = {}

	for _, num in ipairs(shuffled) do
		local posInSide = countInSide - math.floor(perSide / 2)
		table.insert(result, {num = num, pos = sides[sideIndex](posInSide * BLOCK_SPACING)})
		countInSide += 1
		if countInSide >= perSide then
			countInSide = 0
			sideIndex   = math.min(sideIndex + 1, 4)
		end
	end

	return result
end

------------------------------------------------------------------------
-- ブロックをスポーン
------------------------------------------------------------------------

local function spawnBlocks(blockList)
	blockFolder:ClearAllChildren()
	spawnPoints = {}
	heldBlocks  = {}

	local spawnData = generateSpawnPositions(blockList)
	for _, data in ipairs(spawnData) do
		local part = createBlockPart(data.num, data.pos)
		spawnPoints[part] = part.CFrame
	end
	print(string.format("[BlockManager] Spawned %d blocks", #spawnData))
end

BE_SpawnBlocks.Event:Connect(spawnBlocks)

------------------------------------------------------------------------
-- リスポーン
------------------------------------------------------------------------

local function respawnBlock(part)
	if not part or not part.Parent then return end
	local origin = spawnPoints[part]
	if not origin then return end

	part:SetAttribute("IsHeld",       false)
	part:SetAttribute("IsDespawning", false)
	part.Transparency = 0
	part.Anchored     = true
	part.CanCollide   = true
	part.CFrame       = origin

	-- ProximityPrompt を再有効化
	local prompt = part:FindFirstChildOfClass("ProximityPrompt")
	if prompt then prompt.Enabled = true end
end

local function startDespawnTimer(part, onPlayer)
	task.spawn(function()
		task.wait(DESPAWN_TIME - 1.5)
		if not part or not part.Parent then return end
		for i = 1, 5 do
			if part and part.Parent then
				part.Transparency = i / 5
			end
			task.wait(0.3)
		end
		respawnBlock(part)
	end)
end

------------------------------------------------------------------------
-- ブロックを拾う
------------------------------------------------------------------------

-- forward declaration（createBlockPart内のprompt.Triggeredで参照するため）
handlePickupBlock = function(player, blockPart)
	if not blockPart or not blockPart:IsA("BasePart") then return end

	local userId = player.UserId

	-- すでに持っていたら無視
	if heldBlocks[userId] then return end

	-- ペナルティ中は拾えない
	if tick() < (penaltyUntil[userId] or 0) then
		RE_PenaltyNotify:FireClient(player, (penaltyUntil[userId] or 0) - tick())
		return
	end

	-- 誰かが持っている / デスポーン中は無視
	if blockPart:GetAttribute("IsHeld") then return end
	if blockPart:GetAttribute("IsDespawning") then return end

	-- 拾う：ワールドから非表示にして heldBlocks に登録
	blockPart:SetAttribute("IsHeld", true)
	blockPart.Transparency = 1
	blockPart.CanCollide   = false

	-- ProximityPrompt を無効化（他のプレイヤーに表示されないように）
	local prompt = blockPart:FindFirstChildOfClass("ProximityPrompt")
	if prompt then prompt.Enabled = false end

	heldBlocks[userId] = blockPart

	-- Tool を生成して手に持たせる
	createAndEquipTool(player, blockPart:GetAttribute("Number"))

	RE_BlockPickedUp:FireClient(player, blockPart:GetAttribute("Number"))
end

------------------------------------------------------------------------
-- ブロックを消費（本置き後）
------------------------------------------------------------------------

local function consumeHeldBlock(player)
	local userId = player.UserId
	local held   = heldBlocks[userId]
	if not held then return end

	heldBlocks[userId] = nil
	removeHeldTool(player)
	RE_BlockDropped:FireClient(player)

	-- ブロック Part をフェードしてリスポーン
	startDespawnTimer(held)
end

BE_ConsumeBlock.Event:Connect(consumeHeldBlock)

------------------------------------------------------------------------
-- ペナルティ適用
------------------------------------------------------------------------

local function applyPenalty(player, duration)
	local userId = player.UserId
	penaltyUntil[userId] = tick() + duration

	local held = heldBlocks[userId]
	if held then
		-- 足元に落とす
		local char = player.Character
		local hrp  = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			held.CFrame       = CFrame.new(hrp.Position + Vector3.new(0, 1, 0))
			held.Transparency = 0
		end
		held:SetAttribute("IsHeld",       false)
		held:SetAttribute("IsDespawning", true)
		held.Anchored  = false
		heldBlocks[userId] = nil
		startDespawnTimer(held)
	end

	removeHeldTool(player)
	RE_BlockDropped:FireClient(player)
end

BE_ApplyPenalty.Event:Connect(applyPenalty)

------------------------------------------------------------------------
-- 任意ドロップ（捨てるボタン）
------------------------------------------------------------------------

local function handleDropBlock(player)
	local userId = player.UserId
	local held   = heldBlocks[userId]
	if not held then return end

	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		held.CFrame       = CFrame.new(hrp.Position + Vector3.new(0, 1, 2))
		held.Transparency = 0
	end

	held:SetAttribute("IsHeld",       false)
	held:SetAttribute("IsDespawning", true)
	held.Anchored  = false
	heldBlocks[userId] = nil

	removeHeldTool(player)
	RE_BlockDropped:FireClient(player)
	startDespawnTimer(held)
end

RE_DropBlock.OnServerEvent:Connect(handleDropBlock)

------------------------------------------------------------------------
-- 持っている数字を返す（GameManager → BF_GetHeldNumber）
------------------------------------------------------------------------

BF_GetHeldNumber.OnInvoke = function(userId)
	local held = heldBlocks[userId]
	return held and held:GetAttribute("Number") or nil
end

------------------------------------------------------------------------
-- プレイヤー退出時クリーンアップ
------------------------------------------------------------------------

Players.PlayerRemoving:Connect(function(player)
	local userId = player.UserId
	local held   = heldBlocks[userId]
	if held then respawnBlock(held) end
	removeHeldTool(player)
	heldBlocks[userId]   = nil
	penaltyUntil[userId] = nil
end)

------------------------------------------------------------------------
-- 準備完了フラグ
------------------------------------------------------------------------

local readyFlag = Instance.new("BoolValue")
readyFlag.Name   = "BlockManagerReady"
readyFlag.Value  = true
readyFlag.Parent = serverEventsFolder

print("[BlockManager] loaded – ready flag set")
