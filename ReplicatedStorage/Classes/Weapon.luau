-- Client-side Weapon class
-- Services
local Players = game:GetService("Players")
local Weapon = {}
Weapon.__index = Weapon

-- Only set up GUI and Player if running on the client
if Players.LocalPlayer then
    Weapon.Player = Players.LocalPlayer
    -- Try to get the GUI module safely
    do
        local localPlayer = Players.LocalPlayer
        local gui = localPlayer:FindFirstChild("PlayerGui") and localPlayer.PlayerGui:FindFirstChild("AztecGUIGui")
        if gui and gui:FindFirstChild("AztecGUIGuiModule") then
            Weapon.Gui = require(gui.AztecGUIGuiModule)
        else
            warn("[Weapon] AztecGUIGui or AztecGUIGuiModule not found in PlayerGui. GUI features will be disabled.")
            Weapon.Gui = setmetatable({}, {
                __index = function()
                    return function()
                    end
                end
            })
        end
    end
end

function Weapon.new(tool, properties)
    local self = setmetatable({}, Weapon)

    -- References
    self.Tool = tool
    self.ToolModel = self.Tool:WaitForChild("ToolModel")
    self.Remotes = self.Tool:WaitForChild("Remotes")
    self.Handle = self.ToolModel.Handle
    self.Character = self.Player.Character
    if not self.Character or not self.Character.Parent then
        self.Character = self.Player.CharacterAdded:Wait()
    end
    self.Humanoid = self.Character:WaitForChild("Humanoid")
    self.Movement = require(self.Character:WaitForChild("Movement"))
    self.Salute = require(self.Character:WaitForChild("Salute"))

    self.Equipped = false

    -- Animation setup
    self.Animator = self.Humanoid:WaitForChild("Animator")
    self.Animations = {}

    self.Tool.Equipped:Connect(function()
        self.Equipped = true

        self.Gui:WeaponEquipped(self.Tool.Name)
    end)

    self.Tool.Unequipped:Connect(function()
        self.Equipped = false

        -- Update Gui
        self.Gui:WeaponUnequipped(self.Tool.Name)

        -- Stop all animations
        for _, animation in pairs(self.Animations) do
            animation:Stop()
        end
    end)

    return self
end

-- Loads an animation onto the local character
-- and saves the reference to the Animations table
function Weapon:LoadAnimation(animationName, animationId)
    local animation = Instance.new("Animation")
    animation.AnimationId = animationId
    self.Animations[animationName] = self.Animator:LoadAnimation(animation)
end

return Weapon
