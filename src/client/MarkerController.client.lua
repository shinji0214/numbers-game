-- MarkerController
-- 俯瞰モード中のマーカー設置・表示処理
--   - 俯瞰中にマウスクリックでマーカー設置
--   - 1人最大10個（古いものから自動消滅）
--   - プレイヤーカラー＋▲数字 で表示
--   - 本置き確定時に該当マスのマーカーを自動消滅

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

------------------------------------------------------------------------
-- RemoteEvents
------------------------------------------------------------------------

local remoteFolder = ReplicatedStorage:WaitForChild("RemoteEvents")
local RE_UpdateCell = remoteFolder:WaitForChild("UpdateCell")

------------------------------------------------------------------------
-- 定数
------------------------------------------------------------------------

local MAX_MARKERS   = 10
local MARKER_HEIGHT = 1.2   -- 盤面からの高さ
local MARKER_SIZE   = UDim2.fromOffset(70, 70)

-- プレイヤーカラーパレット（UserId % 8 で選ぶ）
local PLAYER_COLORS = {
	Color3.fromRGB(230, 60,  60),
	Color3.fromRGB(60,  130, 220),
	Color3.fromRGB(60,  190, 90),
	Color3.fromRGB(220, 180, 40),
	Color3.fromRGB(180, 60,  200),
	Color3.fromRGB(60,  200, 200),
	Color3.fromRGB(230, 120, 40),
	Color3.fromRGB(140, 200, 60),
}

local myColor = PLAYER_COLORS[(player.UserId % #PLAYER_COLORS) + 1]

------------------------------------------------------------------------
-- 状態
------------------------------------------------------------------------

local markers = {}  -- {part=Part, row=r, col=c} の配列（古い順）

-- 現在選択中の数字（持っているブロックの数字）
local selectedNumber = nil

------------------------------------------------------------------------
-- マーカーのBillboardGUI生成
------------------------------------------------------------------------

local function createMarkerGui(row, col, num)
	-- セルの上にBillboardGuiを置くAdorneeとしてPartを使う
	local cell = workspace.Board and workspace.Board:FindFirstChild(
		string.format("Cell_%d_%d", row, col)
	)
	if not cell then return nil end

	local gui = Instance.new("BillboardGui")
	gui.Name          = string.format("Marker_%d_%d", row, col)
	gui.Adornee       = cell
	gui.Size          = MARKER_SIZE
	gui.StudsOffset   = Vector3.new(0, MARKER_HEIGHT, 0)
	gui.AlwaysOnTop   = true
	gui.ResetOnSpawn  = false

	-- 背景（プレイヤーカラー）
	local bg = Instance.new("Frame", gui)
	bg.Size              = UDim2.fromScale(1, 1)
	bg.BackgroundColor3  = myColor
	bg.BackgroundTransparency = 0.2
	bg.BorderSizePixel   = 0

	local corner = Instance.new("UICorner", bg)
	corner.CornerRadius = UDim.new(0, 8)

	-- ▲ + 数字テキスト
	local label = Instance.new("TextLabel", bg)
	label.Size               = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled         = true
	label.Font               = Enum.Font.GothamBold
	label.Text               = "▲" .. tostring(num)
	label.TextColor3         = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.4

	gui.Parent = cell
	return gui
end

------------------------------------------------------------------------
-- マーカーを追加
------------------------------------------------------------------------

local function addMarker(row, col, num)
	-- 同じマスにすでに自分のマーカーがあれば削除
	for i = #markers, 1, -1 do
		local m = markers[i]
		if m.row == row and m.col == col then
			if m.gui then m.gui:Destroy() end
			table.remove(markers, i)
		end
	end

	-- 上限を超えたら最古を削除
	while #markers >= MAX_MARKERS do
		local oldest = table.remove(markers, 1)
		if oldest.gui then oldest.gui:Destroy() end
	end

	local gui = createMarkerGui(row, col, num)
	if not gui then return end

	table.insert(markers, {
		row = row,
		col = col,
		num = num,
		gui = gui,
	})
end

------------------------------------------------------------------------
-- セルが確定したらマーカーを消す
------------------------------------------------------------------------

RE_UpdateCell.OnClientEvent:Connect(function(row, col, num, state)
	if state == "correct" then
		for i = #markers, 1, -1 do
			local m = markers[i]
			if m.row == row and m.col == col then
				if m.gui then m.gui:Destroy() end
				table.remove(markers, i)
			end
		end
	end
end)

------------------------------------------------------------------------
-- 俯瞰中のクリックでマーカー設置
------------------------------------------------------------------------

-- Raycastでクリックしたセルを取得
local function raycastCell(screenPos)
	local unitRay = camera:ScreenPointToRay(screenPos.X, screenPos.Y)
	local params  = RaycastParams.new()
	params.FilterType       = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {workspace:FindFirstChild("Board")}

	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 200, params)
	if not result then return nil, nil end

	local hit = result.Instance
	if not hit then return nil, nil end

	local row = hit:GetAttribute("Row")
	local col = hit:GetAttribute("Col")
	return row, col
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	-- 俯瞰中のみ有効
	local cam = _G.CameraController
	if not cam or not cam.isOverhead() then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		-- 持っているブロックの数字を取得（PlayerControllerのheldNumberを参照）
		-- _G経由で共有する（将来ModuleScriptで整理予定）
		local num = _G.HeldNumber
		if not num then return end

		local pos = UserInputService:GetMouseLocation()
		local row, col = raycastCell(pos)
		if row and col then
			-- ロック済みのセルには置かない
			local cell = workspace.Board:FindFirstChild(
				string.format("Cell_%d_%d", row, col)
			)
			if cell and cell:GetAttribute("IsLocked") then return end

			addMarker(row, col, num)
		end
	end
end)

------------------------------------------------------------------------
-- PlayerControllerのheldNumberを_Gで受け取れるよう橋渡し
-- （将来はModuleScriptで整理）
------------------------------------------------------------------------

-- NOTE: PlayerControllerがheldNumberを更新するたびに
-- _G.HeldNumber も更新することを想定。
-- PlayerController側に以下を追記予定：
--   _G.HeldNumber = heldNumber

print("[MarkerController] loaded")
