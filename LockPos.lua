-- Variabel Konfigurasi & Status Toggle
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")
local Humanoid = Character:WaitForChild("Humanoid")

-- Simpan posisi awal (Garden)
local savedPosition = HumanoidRootPart.CFrame
local antiMoveEnabled = false -- Status awal toggle mati

-- 1. Fitur Anti-Sit (Mencegah karakter duduk/di-sit player lain)
Humanoid.Seated:Connect(function(isSeated)
    if antiMoveEnabled and isSeated then
        Humanoid.Sit = false
    end
end)

-- 2. Tombol Toggle sederhana (bisa disesuaikan dengan UI library yang kamu pakai)
local ScreenGui = Instance.new("ScreenGui", game.CoreGui)
local ToggleButton = Instance.new("TextButton", ScreenGui)

ToggleButton.Size = UDim2.new(0, 150, 0, 50)
ToggleButton.Position = UDim2.new(0, 50, 0, 50)
ToggleButton.Text = "Anti-Move: OFF"
ToggleButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
ToggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleButton.TextScaled = true

ToggleButton.MouseButton1Click:Connect(function()
    antiMoveEnabled = not antiMoveEnabled
    if antiMoveEnabled then
        savedPosition = HumanoidRootPart.CFrame -- Simpan posisi saat diaktifkan
        ToggleButton.Text = "Anti-Move: ON"
        ToggleButton.BackgroundColor3 = Color3.fromRGB(50, 200, 50)
    else
        ToggleButton.Text = "Anti-Move: OFF"
        ToggleButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
    end
end)

-- 3. Loop untuk mengecek dan mengembalikan posisi jika bergeser
game:GetService("RunService").Stepped:Connect(function()
    if antiMoveEnabled then
        -- Jika karakter terduduk paksa, langsung paksa bangun
        if Humanoid.Sit then
            Humanoid.Sit = false
        end
        
        -- Cek jarak posisi saat ini dengan posisi tersimpan
        if (HumanoidRootPart.Position - savedPosition.Position).Magnitude > 3 then
            -- Jika bergeser lebih dari 3 stud, kembalikan posisi secara paksa
            HumanoidRootPart.CFrame = savedPosition
        end
    end
end)
