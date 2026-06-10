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
local BOARD_SPAN      = 90      -- 9 × 10studs
local EDGE_OFFSET     = 20      -- 盤面端からブロックエリアまでの距離 (studs)
local BLOCK_SPACING   = 6       -- ブロック間隔 (studs)
local DESPAWN_TIME    = 15      -- 落としたブロックが消えるまでの時間 (秒)
local PICKUP_DISTANCE = 10      -- 拾える距離 (studs)

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
-- ① ServerEvents を GameManager が作るまで待つ
------------------------------------------------------------------------

local serverEventsFolder = ServerScriptService:WaitForChild("ServerEvents")
local BE_SpawnBlocks     = serverEventsFolder:WaitForChild("SpawnBlocks")
local BE_ConsumeBlock    = serverEventsFolder:WaitForChild("ConsumeBlock")
local BE_ApplyPenalty    = serverEventsFolder:WaitForChild("ApplyPenalty")
local BF_GetHeldNumber   = serverEventsFolder:WaitForChild("GetHeldNumber")

------------------------------------------------------------------------
-- RemoteEvents（クライアント通信）
------------------------------------------------------------------------

local remoteFolder    = ReplicatedStorage:WaitForChild("RemoteEvents")
local RE_PickupBlock  = remoteFolder:WaitForChild("PickupBlock")
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

------------------------------------------------------------------------
-- 状態管理
------------------------------------------------------------------------

local blockFolder = Instance.new("Folder")
blockFolder.Name   = "Blocks"
blockFolder.Parent = workspace

local spawnPoints  = {}   -- [part] = originalCFrame
local heldBlocks   = {}   -- [userId] = part
local penaltyUntil = {}   -- [userId] = tick()

------------------------------------------------------------------------
-- ブロック Part 生成
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

	-- 上面に数字を表示
	local gui = Instance.new("SurfaceGui")
	gui.Name       = "BlockGui"
	gui.Face       = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(80, 80)
	gui.Parent     = part

	local label = Instance.new("TextLabel")
	label.Name                   = "NumLabel"
	label.Size                   = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled             = true
	label.Text                   = tostring(num)
	label.TextColor3             = Color3.fromRGB(255, 255, 255)
	label.Font                   = Enum.Font.GothamBold
	label.Parent                 = gui

	part.Parent = blockFolder
	return part
end

------------------------------------------------------------------------
-- スポーン座標の生成（四辺にランダム配置）
------------------------------------------------------------------------

local function generateSpawnPositions(blockList)
	local half  = BOARD_SPAN / 2 + EDGE_OFFSET

	local sides = {
		function(t) return Vector3.new(t,     BLOCK_Y,  half) end,
		function(t) return Vector3.new(t,     BLOCK_Y, -half) end,
		function(t) return Vector3.new( half, BLOCK_Y,  t)    end,
		function(t) return Vector3.new(-half, BLOCK_Y,  t)    end,
	}

	-- シャッフル
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
		local pos = sides[sideIndex](posInSide * BLOCK_SPACING)
		table.insert(result, {num = num, pos = pos})

		countInSide += 1
		if countInSide >= perSide then
			countInSide = 0
			sideIndex   = math.min(sideIndex + 1, 4)
		end
	end

	return result
end

------------------------------------------------------------------------
-- ① ブロックをスポーン（GameManager から BE_SpawnBlocks で呼ばれる）
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
-- リスポーン（元の位置に戻す）
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
end

------------------------------------------------------------------------
-- ③ ブロック消費（本置き後に呼ばれる）
--    正解・不正解問わず、本置きしたら手持ちブロックを消費して
--    リスポーンキューに入れる
------------------------------------------------------------------------

local function consumeHeldBlock(player)
	local userId = player.UserId
	local held   = heldBlocks[userId]
	if not held then return end

	heldBlocks[userId] = nil
	held:SetAttribute("IsHeld", false)
	held:SetAttribute("IsDespawning", true)

	-- クライアントに「ブロックを手放した」を通知
	RE_BlockDropped:FireClient(player)

	-- フェードアウトしてリスポーン
	task.spawn(function()
		task.wait(DESPAWN_TIME - 1.5)  -- リスポーン直前まで待機
		if held and held.Parent then
			-- フェードアウト
			for i = 1, 5 do
				if held and held.Parent then
					held.Transparency = i / 5
				end
				task.wait(0.3)
			end
			respawnBlock(held)
		end
	end)
end

BE_ConsumeBlock.Event:Connect(consumeHeldBlock)

------------------------------------------------------------------------
-- ④ ペナルティ適用（GameManager から BE_ApplyPenalty で呼ばれる）
------------------------------------------------------------------------

local function applyPenalty(player, duration)
	local userId = player.UserId
	penaltyUntil[userId] = tick() + duration

	local held = heldBlocks[userId]
	if not held then return end

	-- 足元に落とす
	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		held.CFrame   = CFrame.new(hrp.Position + Vector3.new(0, 1, 0))
		held.Anchored = false
	end

	held:SetAttribute("IsHeld",       false)
	held:SetAttribute("IsDespawning", true)
	heldBlocks[userId] = nil

	RE_BlockDropped:FireClient(player)

	-- フェードアウトしてリスポーン
	task.spawn(function()
		task.wait(DESPAWN_TIME - 1.5)
		if held and held.Parent then
			for i = 1, 5 do
				if held and held.Parent then
					held.Transparency = i / 5
				end
				task.wait(0.3)
			end
			respawnBlock(held)
		end
	end)
end

BE_ApplyPenalty.Event:Connect(applyPenalty)

------------------------------------------------------------------------
-- ⑤ 持っている数字を返す（GameManager から BF_GetHeldNumber で問い合わせ）
------------------------------------------------------------------------

BF_GetHeldNumber.OnInvoke = function(userId)
	local held = heldBlocks[userId]
	if held then
		return held:GetAttribute("Number")
	end
	return nil
end

------------------------------------------------------------------------
-- ブロックを拾う処理
------------------------------------------------------------------------

local function handlePickupBlock(player, blockPart)
	if not blockPart or not blockPart:IsA("BasePart") then return end

	local userId = player.UserId

	-- すでに持っていたら無視
	if heldBlocks[userId] then return end

	-- ペナルティ中は拾えない
	if tick() < (penaltyUntil[userId] or 0) then
		RE_PenaltyNotify:FireClient(player, (penaltyUntil[userId] or 0) - tick())
		return
	end

	-- 誰かが持っていたら無視
	if blockPart:GetAttribute("IsHeld") then return end

	-- デスポーン中は拾えない
	if blockPart:GetAttribute("IsDespawning") then return end

	-- 距離チェック
	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	if (hrp.Position - blockPart.Position).Magnitude > PICKUP_DISTANCE then return end

	-- 拾う
	blockPart:SetAttribute("IsHeld", true)
	blockPart.Anchored   = true
	blockPart.CanCollide = false
	heldBlocks[userId]   = blockPart

	RE_BlockPickedUp:FireClient(player, blockPart:GetAttribute("Number"))
end

RE_PickupBlock.OnServerEvent:Connect(handlePickupBlock)

------------------------------------------------------------------------
-- プレイヤー退出時クリーンアップ
------------------------------------------------------------------------

Players.PlayerRemoving:Connect(function(player)
	local userId = player.UserId
	local held   = heldBlocks[userId]
	if held then respawnBlock(held) end
	heldBlocks[userId]   = nil
	penaltyUntil[userId] = nil
end)

print("[BlockManager] loaded")
