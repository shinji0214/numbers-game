-- CameraController
-- 俯瞰カメラ切替処理
--   - Vキー（またはモバイルボタン）で俯瞰 ↔ 通常を切替
--   - 俯瞰中はキャラクター移動を無効化
--   - 俯瞰中はマーカー設置のRaycastを有効化

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")

local player    = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local camera    = workspace.CurrentCamera

------------------------------------------------------------------------
-- 定数
------------------------------------------------------------------------

local OVERHEAD_HEIGHT  = 90    -- 俯瞰カメラの高さ (studs)
local OVERHEAD_TARGET  = Vector3.new(0, 0, 0)   -- 盤面の中心
local TWEEN_TIME       = 0.4   -- カメラ切替アニメーション時間 (秒)
local OVERHEAD_KEY     = Enum.KeyCode.V

------------------------------------------------------------------------
-- 状態
------------------------------------------------------------------------

local isOverhead    = false
local tweenPlaying  = false
local savedCamCFrame = nil   -- 通常カメラのCFrameを保存

------------------------------------------------------------------------
-- 俯瞰カメラ CFrame
-- CFrame.lookAt の第3引数で up ベクトルを明示する。
-- up = Vector3.new(0, 0, -1) にすると画面上方向が盤面の -Z 方向（奥）になり
-- 歩いて盤面を見た向きと一致する。
------------------------------------------------------------------------

local function getOverheadCFrame()
	local pos = OVERHEAD_TARGET + Vector3.new(0, OVERHEAD_HEIGHT, 0)
	return CFrame.lookAt(pos, OVERHEAD_TARGET, Vector3.new(0, 0, -1))
end

------------------------------------------------------------------------
-- カメラ切替
------------------------------------------------------------------------

local function enterOverhead()
	if tweenPlaying then return end
	isOverhead      = true
	tweenPlaying    = true
	savedCamCFrame  = camera.CFrame

	camera.CameraType = Enum.CameraType.Scriptable

	-- キャラクター移動を無効化
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
	end

	-- カメラをスムーズに移動
	local tween = TweenService:Create(
		camera,
		TweenInfo.new(TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = getOverheadCFrame() }
	)
	tween.Completed:Connect(function()
		tweenPlaying = false
	end)
	tween:Play()
end

local function exitOverhead()
	if tweenPlaying then return end
	isOverhead   = false
	tweenPlaying = true

	-- キャラクター移動を復元
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 16
		humanoid.JumpPower = 50
	end

	-- カメラをスムーズに戻す
	local targetCFrame = savedCamCFrame or CFrame.new(
		(character and character.PrimaryPart and character.PrimaryPart.Position or Vector3.zero)
		+ Vector3.new(0, 5, 10)
	)

	local tween = TweenService:Create(
		camera,
		TweenInfo.new(TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = targetCFrame }
	)
	tween.Completed:Connect(function()
		tweenPlaying = false
		camera.CameraType = Enum.CameraType.Custom  -- Roblox標準カメラに戻す
	end)
	tween:Play()
end

------------------------------------------------------------------------
-- キー入力
------------------------------------------------------------------------

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == OVERHEAD_KEY then
		if isOverhead then
			exitOverhead()
		else
			enterOverhead()
		end
	end
end)

------------------------------------------------------------------------
-- キャラクター切替時のリセット
------------------------------------------------------------------------

player.CharacterAdded:Connect(function(char)
	character  = char
	isOverhead = false
	camera.CameraType = Enum.CameraType.Custom
end)

------------------------------------------------------------------------
-- 外部公開（MarkerController・HUDControllerが参照）
------------------------------------------------------------------------

local CameraController = {}

function CameraController.isOverhead()
	return isOverhead
end

function CameraController.toggle()
	if isOverhead then
		exitOverhead()
	else
		enterOverhead()
	end
end

_G.CameraController = CameraController

print("[CameraController] loaded")
