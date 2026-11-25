-- CharacterController: yerel oyuncunun (kendi avatarı) karakter takibi ve hareket durumları.
-- Yürüme (Walk) / Koşma (Run, varsayılan) / Depar (Sprint).
-- Hareket animasyonları avatarın kendi Animate scriptiyle oynar; hız değişince
-- Animate otomatik olarak yürüme/koşma animasyonunu ve hızını ayarlar.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Constants = require(Shared.Constants)
local Signal = require(Shared.Utilities.Signal)
local Maid = require(Shared.Utilities.Maid)
local Log = require(Shared.Utilities.Log).new("Character")

local CharacterController = {
	Name = "CharacterController",
	Priority = 3,
	CharacterChanged = Signal.new(), -- (character | nil)
	MovementStateChanged = Signal.new(), -- (state)
}

local player = Players.LocalPlayer
local controllers
local charMaid = Maid.new()

local character: Model? = nil
local humanoid: Humanoid? = nil
local rootPart: BasePart? = nil
local walkToggled = false
local movementState = Constants.MovementStates.Run
local movementLocks: { [string]: boolean } = {} -- örn. diyalog sırasında hareketi kilitlemek için

function CharacterController:GetCharacter(): Model?
	return character
end

function CharacterController:GetHumanoid(): Humanoid?
	return humanoid
end

function CharacterController:GetRootPart(): BasePart?
	return rootPart
end

function CharacterController:GetRigType(): string
	if humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 then
		return "R15"
	end
	return "R6"
end

-- Kökten göz hizasına yükseklik. Sunucunun ölçtüğü değer yoksa yerelde ölçer.
function CharacterController:GetEyeHeight(): number
	if not character or not rootPart then
		return 1.5
	end
	local attr = character:GetAttribute(Constants.Attributes.EyeHeight)
	if type(attr) == "number" then
		return attr
	end
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return (head.Position.Y - rootPart.Position.Y) + head.Size.Y * 0.1
	end
	return 1.5
end

function CharacterController:GetMovementState(): string
	return movementState
end

function CharacterController:IsAlive(): boolean
	return humanoid ~= nil and humanoid.Health > 0
end

-- Hareketi kilitle/aç (diyalog, sinematik vb.). Birden fazla sahip olabilir.
function CharacterController:SetMovementLocked(owner: string, locked: boolean)
	movementLocks[owner] = if locked then true else nil
	CharacterController:_applySpeed()
end

function CharacterController:IsMovementLocked(): boolean
	return next(movementLocks) ~= nil
end

function CharacterController:_applySpeed()
	if not humanoid then
		return
	end
	if self:IsMovementLocked() then
		humanoid.WalkSpeed = 0
		return
	end
	local m = Config.Movement
	if movementState == Constants.MovementStates.Sprint then
		humanoid.WalkSpeed = m.SprintSpeed
	elseif movementState == Constants.MovementStates.Walk then
		humanoid.WalkSpeed = m.WalkSpeed
	else
		humanoid.WalkSpeed = m.RunSpeed
	end
end

local function setMovementState(newState: string)
	if newState == movementState then
		return
	end
	movementState = newState
	CharacterController:_applySpeed()
	CharacterController.MovementStateChanged:Fire(newState)
end

local function evaluateMovementState()
	if not humanoid then
		return
	end
	local input = controllers.InputController
	local moving = humanoid.MoveDirection.Magnitude > 0.1
	if input:IsActionActive("Sprint") and moving and humanoid.SeatPart == nil then
		setMovementState(Constants.MovementStates.Sprint)
	elseif walkToggled then
		setMovementState(Constants.MovementStates.Walk)
	else
		setMovementState(Constants.MovementStates.Run)
	end
end

local function onCharacterAdded(newCharacter: Model)
	charMaid:Clean()
	character = newCharacter
	humanoid = newCharacter:WaitForChild("Humanoid", 10) :: Humanoid?
	rootPart = newCharacter:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not humanoid or not rootPart or player.Character ~= newCharacter then
		return
	end
	movementState = Constants.MovementStates.Run
	CharacterController:_applySpeed()

	charMaid:Give(humanoid:GetPropertyChangedSignal("MoveDirection"):Connect(evaluateMovementState))
	charMaid:Give(humanoid.Died:Connect(function()
		setMovementState(Constants.MovementStates.Run)
	end))
	charMaid:Give(newCharacter.AncestryChanged:Connect(function(_, parent)
		if parent == nil and character == newCharacter then
			charMaid:Clean()
			character, humanoid, rootPart = nil, nil, nil
			CharacterController.CharacterChanged:Fire(nil)
		end
	end))

	Log.Info("Karakter yüklendi:", CharacterController:GetRigType())
	CharacterController.CharacterChanged:Fire(newCharacter)
end

function CharacterController:Init(allControllers)
	controllers = allControllers
end

function CharacterController:Start()
	local input = controllers.InputController
	input.ActionBegan:Connect(function(action)
		if action == "Sprint" then
			evaluateMovementState()
		elseif action == "WalkToggle" then
			walkToggled = not walkToggled
			evaluateMovementState()
		end
	end)
	input.ActionEnded:Connect(function(action)
		if action == "Sprint" then
			evaluateMovementState()
		end
	end)

	-- Başka bir script WalkSpeed'i değiştirirse (ör. Roblox varsayılanları) düzelt — düşük frekans
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= 0.5 then
			accumulator = 0
			if humanoid and not CharacterController:IsMovementLocked() then
				CharacterController:_applySpeed()
			end
		end
	end)

	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		task.spawn(onCharacterAdded, player.Character)
	end
end

return CharacterController
