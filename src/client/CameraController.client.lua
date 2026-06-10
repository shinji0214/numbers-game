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
------------------------------------------------------------------------

local function getOverheadCFrame()
	return CFrame.new(
		OVERHEAD_TARGET + Vector3.new(0, OVERHEAD_HEIGHT, 0),
		OVERHEAD_TARGET
	)
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
-- 外部公開：俯瞰中かどうかを返す（MarkerControllerが参照）
------------------------------------------------------------------------

local CameraController = {}

function CameraController.isOverhead()
	return isOverhead
end

-- MarkerControllerが参照できるようにModuleScriptとして公開する場合は
-- ReplicatedStorageに移動する。現段階ではシンプルにグローバル変数で共有。
_G.CameraController = CameraController

print("[CameraController] loaded")
