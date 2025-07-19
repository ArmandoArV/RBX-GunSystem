-- Client-side Gun class

-- Config
local FIRE_ACTION = "Wolfram_GunFire"
local RELOAD_ACTION = "Wolfram_GunReload"

-- Services
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

-- Class Setup
local super = require(script.Parent.Weapon)
local Gun = setmetatable({}, {__index = super})
Gun.__index = Gun

local Mouse = require(script.Parent.Parent.Mouse)
local Effects = require(script.Parent.Parent.Effects)
local Keybinds = require(script.Parent.Parent.Keybinds)

function Gun.new(tool, properties)
	local self = setmetatable(super.new(tool, properties), Gun)
	
	-- Properties
	self.MaxAmmo    = properties.MaxAmmo
	self.Ammo       = self.MaxAmmo
	self.Damage     = properties.Damage
	self.FireRate   = properties.FireRate
	self.Spread     = properties.Spread
	self.ReloadTime = properties.ReloadTime
	self.Range      = properties.Range
	
	self.Firing = false
	self.CanFire = true
	self.Reloading = false
	self.CanReload = true
	
	-- References
	self.Barrel = self.Handle.Barrel
	
	-- Find Remotes
	self.ClientFired = self.Remotes:WaitForChild("ClientFired")
	self.ReplicatePlaySound = self.Remotes:WaitForChild("PlayWeaponSound")
	
	-- Create RaycastParams
	self.RaycastParams = RaycastParams.new()
	self.RaycastParams.IgnoreWater = true
	self.RaycastParams.FilterType = Enum.RaycastFilterType.Blacklist
	self.RaycastParams.FilterDescendantsInstances = {self.Character, Mouse.TargetFilter}
	
	-- Load Gun animations
	self:LoadAnimation("Idle", properties.Animations.Idle)
	self:LoadAnimation("Equip", properties.Animations.Equip)
	self:LoadAnimation("Fire", properties.Animations.Fire)
	self:LoadAnimation("Lower", properties.Animations.Lower)
	
	tool.Equipped:Connect(function()
		self.Reloading = false
		
		-- Bind Fire action
		ContextActionService:BindAction(
			FIRE_ACTION,
			function(_, inputState, inputObject)
				if inputState == Enum.UserInputState.Begin then
					if self.Humanoid.Health > 0 and self.CanFire and self.Ammo > 0 and not self.Reloading then
						self:Fire()
					end
				elseif inputState == Enum.UserInputState.End then
					self:StopFiring()
				end
			end,
			false,
			Enum.UserInputType.MouseButton1
		)
		
		ContextActionService:BindAction(
			RELOAD_ACTION,
			function(_, inputState, inputObject)
				if inputState == Enum.UserInputState.Begin then
					self:Reload()
				end
			end,
			true,
			Keybinds:GetKeybind("Reload")
		)
		
		-- Enable cursor
		Mouse:SetCursorEnabled(true)
		
		-- Update Gui
		self.Gui:SetAmmo(self.Tool.Name, self.Ammo, self.MaxAmmo)
		
		-- Play equip then idle animation
		self.Animations.Equip:Play()
		wait(self.Animations.Equip.Length - 0.1)
		if self.Equipped then
			-- Handle movement state changes
			if self.Movement:GetState() == self.Movement.MovementState.Sprinting then
				self.Animations.Lower:Play()
			else
				self.Animations.Idle:Play()
			end

			self.MovementStateChanged = self.Movement.StateChanged:Connect(function(state)
				if self.Equipped then
					if state == self.Movement.MovementState.Sprinting then
						self.Animations.Idle:Stop()
						self.Animations.Lower:Play()
						self.Firing = false
					elseif not self.Salute:IsSaluting() then
						self.Animations.Idle:Play()
						self.Animations.Lower:Stop()
					end
				end
			end)
			
			-- Handle salute state changes
			if self.Salute:IsSaluting() then
				self.Animations.Lower:Play()
			end
			
			self.SaluteStateChanged = self.Salute.SaluteChanged:Connect(function(saluting)
				if self.Equipped then
					if saluting then
						self.Animations.Lower:Play()
					elseif self.Movement:GetState() ~= self.Movement.MovementState.Sprinting then
						self.Animations.Lower:Stop()
						self.Animations.Idle:Play()
					end
				end
			end)
		end
	end)
	
	tool.Unequipped:Connect(function()
		-- Stop firing
		self.Firing = false
		
		-- Unbind actions
		ContextActionService:UnbindAction(FIRE_ACTION)
		ContextActionService:UnbindAction(RELOAD_ACTION)
		
		-- Disconnect movement state changed event handler
		if self.MovementStateChanged then
			self.MovementStateChanged:Disconnect()
			self.MovementStateChanged = nil
		end

		-- Disconnect salute state changed event handler
		if self.SaluteStateChanged then
			self.SaluteStateChanged:Disconnect()
			self.SaluteStateChanged = nil
		end
		
		-- Disable cursor
		Mouse:SetCursorEnabled(false)
		
		--
		if self.Reloading then
			self.Salute:SetCanSalute(true)
		end
	end)
	
	return self
end

	-- When the player holds Mouse1
function Gun:Fire()
	self:Shoot()
end

	-- When the player releases Mouse1
function Gun:StopFiring()
	self.Firing = false
end

function Gun:SetAmmo(ammo)
	self.Ammo = ammo
	-- Update Gui
	if self.Equipped then
		self.Gui:SetAmmo(self.Tool.Name, self.Ammo, self.MaxAmmo, true)
	end
end

	-- Reload the gun (Magazine-based system)
function Gun:Reload()
	if self.CanReload and not self.Reloading and self.Ammo < self.MaxAmmo then
		-- Reload start
		self.Reloading = true
		self.CanReload = false
		self:StopFiring()
		self.Handle.BeginReload:Play()
		self.ReplicatePlaySound:FireServer(self.Handle.BeginReload)
		-- Reload loop
		while self.Reloading do
			self.Handle.Reload:Play()
			self.ReplicatePlaySound:FireServer(self.Handle.Reload)
			wait(self.ReloadTime)
			self:SetAmmo(self.Ammo + 1)
			if self.Ammo >= self.MaxAmmo then
				self.Reloading = false
			end
		end
		-- Reload end
		self.CanReload = true
	end
end

	-- A single shot
function Gun:Shoot()
	self.CanFire = false
	
	-- Play fire animations
	self.Animations.Fire:Play()

	if self.Movement:GetState() == self.Movement.MovementState.Sprinting then
		self.Movement:SetState(self.Movement.MovementState.Walking)
	end
	
	self.Salute:SetSaluting(false)
	
	-- Calculate initial raycasting values
	local origin = self.Character.Head.Position
	local aim = Mouse:GetWorldPosition()
	
	-- Apply spread
	local distance = (aim - origin).Magnitude
	local minSpread = -(self.Spread) * distance 
	local maxSpread =  (self.Spread) * distance
	aim = Vector3.new(
		aim.X + math.random(minSpread, maxSpread), 
		aim.Y + math.random(minSpread, maxSpread), 
		aim.Z + math.random(minSpread, maxSpread)
	)
	
	-- Raycast
	local direction = (aim - origin).Unit * self.Range
	local raycastResult = workspace:Raycast(origin, direction, self.RaycastParams)
	if raycastResult then
		-- Convert RaycastResult to a table for replication
		raycastResult = {
			Position = raycastResult.Position;
			Instance = raycastResult.Instance;
			Normal = raycastResult.Normal;
		}
	else
		-- Fill in missing data if nil was returned
		raycastResult = {Position = origin + direction}
	end
	
	local humanoid
	if raycastResult.Instance then
		if raycastResult.Instance.Parent ~= workspace then
			humanoid = raycastResult.Instance.Parent:FindFirstChildOfClass("Humanoid")
			
			if not humanoid and raycastResult.Instance.Parent.Parent then
				humanoid = raycastResult.Instance.Parent.Parent:FindFirstChildOfClass("Humanoid")
			end
			
			if not humanoid and raycastResult.Instance.Parent.Parent.Parent then
				humanoid = raycastResult.Instance.Parent.Parent.Parent:FindFirstChildOfClass("Humanoid")
			end
		end
	end

	-- Handle hit response
	if humanoid and humanoid.Health > 0 then
		local damage = self:PredictDamage(humanoid, raycastResult.Instance)
		if damage ~= 0 then
			-- Effects
			Mouse:Hitmarker()
			Mouse:DamageIndicator(math.abs(damage))
			Effects:PlayHitsound()
			if damage > 0 then -- (damage)
				Effects:CreateHitbox(raycastResult.Instance, raycastResult.Instance.Name == "Head")
			else -- damage < 0 (healing)
				Effects:CreateHealbox(humanoid.Parent, raycastResult.Instance.Name == "Head" and 3 or 2)
			end
		end
	end
	
	-- Handle effects
	Effects:HandleStandardFiredGunEffects(self.Handle, raycastResult, humanoid ~= nil)
	
	-- Replicate
	self.ClientFired:FireServer(origin, raycastResult)
	
	self:SetAmmo(self.Ammo - 1)
	
	if self.Ammo <= 0 then
		self:Reload()
	else
		wait(self.FireRate)
	end
		
	self.CanFire = true
end

function Gun:IsEnemy(humanoid)
	local hitPlayer = Players:GetPlayerFromCharacter(humanoid.Parent)

	if hitPlayer then
		if not hitPlayer.Neutral and not self.Player.Neutral and hitPlayer.Team == self.Player.Team then
			return false
		end
	end
	
	return true
end

function Gun:PredictDamage(humanoid, limb)
	local damage = 0
	if self:IsEnemy(humanoid) then
		-- Determine damage
		damage = self.Damage.Torso
		if limb.Name == "Head" then
			damage = self.Damage.Head
		elseif limb.Name == "Right Arm" or limb.Name == "Left Arm" then
			damage = self.Damage.Arms
		elseif limb.Name == "Right Leg" or limb.Name == "Left Leg" then
			damage = self.Damage.Legs
		end
	end
	
	return damage
end

return Gun