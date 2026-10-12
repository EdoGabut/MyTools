-- ============================================
-- TEXT SEARCH TOOL v2
-- - Cari di semua TextLabel/TextButton/TextBox
-- - Copy path lengkap per hasil
-- - Copy text per hasil
-- - Copy semua (path + text)
-- ============================================

local CoreGui = game:GetService("CoreGui")

-- Scope pencarian
local SEARCH_ROOT = workspace

-- ============ GUI ============

local old = CoreGui:FindFirstChild("TextSearchGUI")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "TextSearchGUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = CoreGui

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 520, 0, 620)
main.Position = UDim2.new(0, 20, 0, 60)
main.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = main

-- Title
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 32)
title.BackgroundColor3 = Color3.fromRGB(40, 40, 52)
title.BorderSizePixel = 0
title.Text = "  🔍 Text Search Tool v2"
title.TextColor3 = Color3.fromRGB(230, 230, 240)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Font = Enum.Font.GothamBold
title.TextSize = 13
title.Parent = main

local titleCorner = Instance.new("UICorner")
titleCorner.CornerRadius = UDim.new(0, 10)
titleCorner.Parent = title

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 32, 0, 32)
closeBtn.Position = UDim2.new(1, -32, 0, 0)
closeBtn.BackgroundTransparency = 1
closeBtn.Text = "✕"
closeBtn.TextColor3 = Color3.fromRGB(255, 100, 100)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 16
closeBtn.Parent = title
closeBtn.MouseButton1Click:Connect(function() gui:Destroy() end)

-- ============ SEARCH INPUT ============

local searchFrame = Instance.new("Frame")
searchFrame.Size = UDim2.new(1, -16, 0, 64)
searchFrame.Position = UDim2.new(0, 8, 0, 40)
searchFrame.BackgroundColor3 = Color3.fromRGB(32, 32, 42)
searchFrame.BorderSizePixel = 0
searchFrame.Parent = main

local sfCorner = Instance.new("UICorner")
sfCorner.CornerRadius = UDim.new(0, 6)
sfCorner.Parent = searchFrame

local keywordBox = Instance.new("TextBox")
keywordBox.Size = UDim2.new(1, -100, 0, 28)
keywordBox.Position = UDim2.new(0, 8, 0, 8)
keywordBox.BackgroundColor3 = Color3.fromRGB(45, 45, 58)
keywordBox.BorderSizePixel = 0
keywordBox.Text = ""
keywordBox.PlaceholderText = "Cari text... (misal: kg, Spirit, 14.98)"
keywordBox.TextColor3 = Color3.fromRGB(230, 230, 240)
keywordBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 140)
keywordBox.Font = Enum.Font.Code
keywordBox.TextSize = 13
keywordBox.ClearTextOnFocus = false
keywordBox.TextXAlignment = Enum.TextXAlignment.Left
keywordBox.Parent = searchFrame

local kbCorner = Instance.new("UICorner")
kbCorner.CornerRadius = UDim.new(0, 4)
kbCorner.Parent = keywordBox

local kbPad = Instance.new("UIPadding")
kbPad.PaddingLeft = UDim.new(0, 6)
kbPad.Parent = keywordBox

local searchBtn = Instance.new("TextButton")
searchBtn.Size = UDim2.new(0, 84, 0, 28)
searchBtn.Position = UDim2.new(1, -92, 0, 8)
searchBtn.BackgroundColor3 = Color3.fromRGB(40, 110, 180)
searchBtn.Text = "🔍 Cari"
searchBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
searchBtn.Font = Enum.Font.GothamBold
searchBtn.TextSize = 12
searchBtn.Parent = searchFrame

local sbCorner = Instance.new("UICorner")
sbCorner.CornerRadius = UDim.new(0, 4)
sbCorner.Parent = searchBtn

-- Options
local optFrame = Instance.new("Frame")
optFrame.Size = UDim2.new(1, -16, 0, 22)
optFrame.Position = UDim2.new(0, 8, 0, 42)
optFrame.BackgroundTransparency = 1
optFrame.Parent = searchFrame

local function makeCheckbox(parent, xPos, labelText, default)
    local box = Instance.new("TextButton")
    box.Size = UDim2.new(0, 130, 1, 0)
    box.Position = UDim2.new(0, xPos, 0, 0)
    box.BackgroundTransparency = 1
    box.Text = (default and "☑ " or "☐ ") .. labelText
    box.TextColor3 = Color3.fromRGB(200, 200, 220)
    box.Font = Enum.Font.Gotham
    box.TextSize = 11
    box.TextXAlignment = Enum.TextXAlignment.Left
    box.Parent = parent

    box:SetAttribute("Checked", default)
    box.MouseButton1Click:Connect(function()
        local c = not box:GetAttribute("Checked")
        box:SetAttribute("Checked", c)
        box.Text = (c and "☑ " or "☐ ") .. labelText
    end)

    return box
end

local caseBox = makeCheckbox(optFrame, 0, "Case Sensitive", false)
local wsOnlyBox = makeCheckbox(optFrame, 140, "Workspace Only", true)
local showPathBox = makeCheckbox(optFrame, 280, "Show Path", true)

-- ============ RESULTS ============

local resultInfo = Instance.new("TextLabel")
resultInfo.Size = UDim2.new(1, -16, 0, 20)
resultInfo.Position = UDim2.new(0, 8, 0, 110)
resultInfo.BackgroundTransparency = 1
resultInfo.Text = "Masukkan keyword, lalu klik Cari."
resultInfo.TextColor3 = Color3.fromRGB(180, 200, 255)
resultInfo.Font = Enum.Font.Gotham
resultInfo.TextSize = 11
resultInfo.TextXAlignment = Enum.TextXAlignment.Left
resultInfo.Parent = main

local resultFrame = Instance.new("ScrollingFrame")
resultFrame.Size = UDim2.new(1, -16, 1, -180)
resultFrame.Position = UDim2.new(0, 8, 0, 134)
resultFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
resultFrame.BorderSizePixel = 0
resultFrame.ScrollBarThickness = 6
resultFrame.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 100)
resultFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
resultFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
resultFrame.Parent = main

local rfCorner = Instance.new("UICorner")
rfCorner.CornerRadius = UDim.new(0, 6)
rfCorner.Parent = resultFrame

local rfLayout = Instance.new("UIListLayout")
rfLayout.Padding = UDim.new(0, 2)
rfLayout.SortOrder = Enum.SortOrder.LayoutOrder
rfLayout.Parent = resultFrame

local rfPad = Instance.new("UIPadding")
rfPad.PaddingTop = UDim.new(0, 4)
rfPad.PaddingBottom = UDim.new(0, 4)
rfPad.PaddingLeft = UDim.new(0, 4)
rfPad.PaddingRight = UDim.new(0, 4)
rfPad.Parent = resultFrame

-- Bottom buttons
local btnFrame = Instance.new("Frame")
btnFrame.Size = UDim2.new(1, -16, 0, 64)
btnFrame.Position = UDim2.new(0, 8, 1, -72)
btnFrame.BackgroundTransparency = 1
btnFrame.Parent = main

-- Row 1: Copy All
local copyAllBtn = Instance.new("TextButton")
copyAllBtn.Size = UDim2.new(0.5, -4, 0, 28)
copyAllBtn.Position = UDim2.new(0, 0, 0, 0)
copyAllBtn.BackgroundColor3 = Color3.fromRGB(40, 120, 70)
copyAllBtn.Text = "📋 Copy Semua (Path + Text)"
copyAllBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
copyAllBtn.Font = Enum.Font.GothamBold
copyAllBtn.TextSize = 11
copyAllBtn.Parent = btnFrame

local caCorner = Instance.new("UICorner")
caCorner.CornerRadius = UDim.new(0, 5)
caCorner.Parent = copyAllBtn

local copyAllPathsBtn = Instance.new("TextButton")
copyAllPathsBtn.Size = UDim2.new(0.5, -4, 0, 28)
copyAllPathsBtn.Position = UDim2.new(0.5, 4, 0, 0)
copyAllPathsBtn.BackgroundColor3 = Color3.fromRGB(60, 80, 140)
copyAllPathsBtn.Text = "📋 Copy Semua Path"
copyAllPathsBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
copyAllPathsBtn.Font = Enum.Font.GothamBold
copyAllPathsBtn.TextSize = 11
copyAllPathsBtn.Parent = btnFrame

local capCorner = Instance.new("UICorner")
capCorner.CornerRadius = UDim.new(0, 5)
capCorner.Parent = copyAllPathsBtn

-- Row 2: Copy All Texts + Clear
local copyAllTextsBtn = Instance.new("TextButton")
copyAllTextsBtn.Size = UDim2.new(0.5, -4, 0, 28)
copyAllTextsBtn.Position = UDim2.new(0, 0, 0, 32)
copyAllTextsBtn.BackgroundColor3 = Color3.fromRGB(60, 80, 140)
copyAllTextsBtn.Text = "📋 Copy Semua Text"
copyAllTextsBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
copyAllTextsBtn.Font = Enum.Font.GothamBold
copyAllTextsBtn.TextSize = 11
copyAllTextsBtn.Parent = btnFrame

local catCorner = Instance.new("UICorner")
catCorner.CornerRadius = UDim.new(0, 5)
catCorner.Parent = copyAllTextsBtn

local clearBtn = Instance.new("TextButton")
clearBtn.Size = UDim2.new(0.5, -4, 0, 28)
clearBtn.Position = UDim2.new(0.5, 4, 0, 32)
clearBtn.BackgroundColor3 = Color3.fromRGB(100, 50, 50)
clearBtn.Text = "🗑 Clear"
clearBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
clearBtn.Font = Enum.Font.GothamBold
clearBtn.TextSize = 11
clearBtn.Parent = btnFrame

local clbCorner = Instance.new("UICorner")
clbCorner.CornerRadius = UDim.new(0, 5)
clbCorner.Parent = clearBtn

-- ============ STATE ============

local results = {}  -- array of {instance, text, plain, path, className}

-- ============ UTIL ============

local function stripRichText(text)
    return text:gsub("<[^>]+>", "")
end

local function copyToClipboard(text)
    if setclipboard then
        setclipboard(text)
        return true
    elseif toclipboard then
        toclipboard(text)
        return true
    else
        print("=== CLIPBOARD ===")
        print(text)
        return false
    end
end

local function flashButton(btn, newText, color)
    local oldText = btn.Text
    local oldColor = btn.BackgroundColor3
    btn.Text = newText
    btn.BackgroundColor3 = color
    task.delay(0.8, function()
        if btn and btn.Parent then
            btn.Text = oldText
            btn.BackgroundColor3 = oldColor
        end
    end)
end

-- ============ SEARCH ============

local function clearResults()
    for _, c in ipairs(resultFrame:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
    results = {}
end

local function searchText(root, keyword, caseSensitive, showPath)
    results = {}

    for _, desc in ipairs(root:GetDescendants()) do
        if desc:IsA("TextLabel") or desc:IsA("TextButton") or desc:IsA("TextBox") then
            local rawText = desc.Text or ""
            if rawText ~= "" then
                local plainText = stripRichText(rawText)

                local haystack = plainText
                local needle = keyword
                if not caseSensitive then
                    haystack = haystack:lower()
                    needle = needle:lower()
                end

                if haystack:find(needle, 1, true) then
                    table.insert(results, {
                        instance = desc,
                        text = rawText,
                        plain = plainText,
                        path = desc:GetFullName(),
                        className = desc.ClassName,
                    })
                end
            end
        end
    end

    return #results
end

local function renderResults(showPath)
    clearResults()

    -- Note: results udah diisi sebelum render
    -- Kita re-render pakai results yang ada
    local count = #results

    for i, r in ipairs(results) do
        local rowHeight = showPath and 60 or 40

        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, rowHeight)
        row.BackgroundColor3 = (i % 2 == 0)
            and Color3.fromRGB(28, 28, 36)
            or Color3.fromRGB(22, 22, 30)
        row.BorderSizePixel = 0
        row.LayoutOrder = i
        row.Parent = resultFrame

        local rowCorner = Instance.new("UICorner")
        rowCorner.CornerRadius = UDim.new(0, 4)
        rowCorner.Parent = row

        -- Nomor
        local numLbl = Instance.new("TextLabel")
        numLbl.Size = UDim2.new(0, 30, 1, 0)
        numLbl.Position = UDim2.new(0, 4, 0, 0)
        numLbl.BackgroundTransparency = 1
        numLbl.Text = "#" .. i
        numLbl.TextColor3 = Color3.fromRGB(150, 150, 170)
        numLbl.Font = Enum.Font.Code
        numLbl.TextSize = 10
        numLbl.TextXAlignment = Enum.TextXAlignment.Left
        numLbl.TextYAlignment = Enum.TextYAlignment.Top
        numLbl.Parent = row

        -- Text content (yang beneran tampil)
        local textLbl = Instance.new("TextLabel")
        textLbl.Size = UDim2.new(1, -140, 0, 18)
        textLbl.Position = UDim2.new(0, 36, 0, 4)
        textLbl.BackgroundTransparency = 1
        textLbl.Text = r.plain
        textLbl.TextColor3 = Color3.fromRGB(200, 255, 200)
        textLbl.Font = Enum.Font.Code
        textLbl.TextSize = 11
        textLbl.TextXAlignment = Enum.TextXAlignment.Left
        textLbl.TextTruncate = Enum.TextTruncate.AtEnd
        textLbl.Parent = row

        -- ClassName
        local classLbl = Instance.new("TextLabel")
        classLbl.Size = UDim2.new(1, -140, 0, 14)
        classLbl.Position = UDim2.new(0, 36, 0, 22)
        classLbl.BackgroundTransparency = 1
        classLbl.Text = r.className
        classLbl.TextColor3 = Color3.fromRGB(140, 140, 180)
        classLbl.Font = Enum.Font.Gotham
        classLbl.TextSize = 9
        classLbl.TextXAlignment = Enum.TextXAlignment.Left
        classLbl.Parent = row

        -- Path (kalau showPath)
        if showPath then
            local pathLbl = Instance.new("TextLabel")
            pathLbl.Size = UDim2.new(1, -40, 0, 16)
            pathLbl.Position = UDim2.new(0, 36, 0, 38)
            pathLbl.BackgroundTransparency = 1
            pathLbl.Text = r.path
            pathLbl.TextColor3 = Color3.fromRGB(120, 120, 150)
            pathLbl.Font = Enum.Font.Code
            pathLbl.TextSize = 9
            pathLbl.TextXAlignment = Enum.TextXAlignment.Left
            pathLbl.TextTruncate = Enum.TextTruncate.AtEnd
            pathLbl.Parent = row
        end

        -- Tombol Copy Path (kanan atas)
        local copyPathBtn = Instance.new("TextButton")
        copyPathBtn.Size = UDim2.new(0, 48, 0, 20)
        copyPathBtn.Position = UDim2.new(1, -54, 0, 4)
        copyPathBtn.BackgroundColor3 = Color3.fromRGB(50, 80, 120)
        copyPathBtn.Text = "Path"
        copyPathBtn.TextColor3 = Color3.fromRGB(220, 220, 240)
        copyPathBtn.Font = Enum.Font.GothamBold
        copyPathBtn.TextSize = 10
        copyPathBtn.Parent = row

        local cpbCorner = Instance.new("UICorner")
        cpbCorner.CornerRadius = UDim.new(0, 3)
        cpbCorner.Parent = copyPathBtn

        copyPathBtn.MouseButton1Click:Connect(function()
            local ok = copyToClipboard(r.path)
            flashButton(copyPathBtn,
                ok and "✓" or "!",
                ok and Color3.fromRGB(40, 140, 70) or Color3.fromRGB(140, 60, 60))
        end)

        -- Tombol Copy Text (kanan bawah)
        local copyTextBtn = Instance.new("TextButton")
        copyTextBtn.Size = UDim2.new(0, 48, 0, 20)
        copyTextBtn.Position = UDim2.new(1, -54, 0, 28)
        copyTextBtn.BackgroundColor3 = Color3.fromRGB(80, 60, 120)
        copyTextBtn.Text = "Text"
        copyTextBtn.TextColor3 = Color3.fromRGB(220, 220, 240)
        copyTextBtn.Font = Enum.Font.GothamBold
        copyTextBtn.TextSize = 10
        copyTextBtn.Parent = row

        local ctbCorner = Instance.new("UICorner")
        ctbCorner.CornerRadius = UDim.new(0, 3)
        ctbCorner.Parent = copyTextBtn

        copyTextBtn.MouseButton1Click:Connect(function()
            local ok = copyToClipboard(r.plain)
            flashButton(copyTextBtn,
                ok and "✓" or "!",
                ok and Color3.fromRGB(40, 140, 70) or Color3.fromRGB(140, 60, 60))
        end)
    end
end

-- ============ EVENTS ============

local function doSearch()
    local keyword = keywordBox.Text
    if keyword == "" then
        resultInfo.Text = "⚠️ Masukkan keyword dulu."
        resultInfo.TextColor3 = Color3.fromRGB(255, 180, 100)
        return
    end

    clearResults()

    local caseSensitive = caseBox:GetAttribute("Checked")
    local wsOnly = wsOnlyBox:GetAttribute("Checked")
    local showPath = showPathBox:GetAttribute("Checked")

    local root = wsOnly and workspace or game

    resultInfo.Text = "⏳ Mencari..."
    resultInfo.TextColor3 = Color3.fromRGB(180, 200, 255)

    local t0 = tick()
    local count = 0
    local ok, err = pcall(function()
        count = searchText(root, keyword, caseSensitive, showPath)
    end)
    local dt = tick() - t0

    if not ok then
        resultInfo.Text = "❌ Error: " .. tostring(err)
        resultInfo.TextColor3 = Color3.fromRGB(255, 130, 130)
        return
    end

    renderResults(showPath)

    if count == 0 then
        resultInfo.Text = string.format("🔍 '%s' → gak ada hasil (%.2fs)", keyword, dt)
        resultInfo.TextColor3 = Color3.fromRGB(255, 180, 100)
    else
        resultInfo.Text = string.format("✅ '%s' → %d hasil (%.2fs)", keyword, count, dt)
        resultInfo.TextColor3 = Color3.fromRGB(150, 255, 150)
    end
end

searchBtn.MouseButton1Click:Connect(doSearch)

keywordBox.FocusLost:Connect(function(enterPressed)
    if enterPressed then doSearch() end
end)

-- Copy All (Path + Text)
copyAllBtn.MouseButton1Click:Connect(function()
    if #results == 0 then
        resultInfo.Text = "⚠️ Belum ada hasil."
        return
    end

    local lines = {}
    table.insert(lines, "=== SEARCH RESULTS ===")
    table.insert(lines, "Keyword: " .. keywordBox.Text)
    table.insert(lines, "Total: " .. #results)
    table.insert(lines, "")

    for i, r in ipairs(results) do
        table.insert(lines, string.format("[%d] %s", i, r.className))
        table.insert(lines, "Text: " .. r.plain)
        table.insert(lines, "Path: " .. r.path)
        table.insert(lines, "")
    end

    local text = table.concat(lines, "\n")
    local ok = copyToClipboard(text)

    if ok then
        resultInfo.Text = "✅ Copied " .. #results .. " results (Path + Text)"
        resultInfo.TextColor3 = Color3.fromRGB(150, 255, 150)
    else
        resultInfo.Text = "⚠️ setclipboard gak ada, cek console (F9)"
    end
end)

-- Copy All Paths only
copyAllPathsBtn.MouseButton1Click:Connect(function()
    if #results == 0 then
        resultInfo.Text = "⚠️ Belum ada hasil."
        return
    end

    local lines = {}
    for _, r in ipairs(results) do
        table.insert(lines, r.path)
    end

    local text = table.concat(lines, "\n")
    local ok = copyToClipboard(text)

    if ok then
        resultInfo.Text = "✅ Copied " .. #results .. " paths"
        resultInfo.TextColor3 = Color3.fromRGB(150, 255, 150)
    else
        resultInfo.Text = "⚠️ setclipboard gak ada, cek console (F9)"
    end
end)

-- Copy All Texts only
copyAllTextsBtn.MouseButton1Click:Connect(function()
    if #results == 0 then
        resultInfo.Text = "⚠️ Belum ada hasil."
        return
    end

    local lines = {}
    for _, r in ipairs(results) do
        table.insert(lines, r.plain)
    end

    local text = table.concat(lines, "\n")
    local ok = copyToClipboard(text)

    if ok then
        resultInfo.Text = "✅ Copied " .. #results .. " texts"
        resultInfo.TextColor3 = Color3.fromRGB(150, 255, 150)
    else
        resultInfo.Text = "⚠️ setclipboard gak ada, cek console (F9)"
    end
end)

clearBtn.MouseButton1Click:Connect(function()
    clearResults()
    resultInfo.Text = "Cleared."
    resultInfo.TextColor3 = Color3.fromRGB(180, 200, 255)
end)

-- Init
resultInfo.Text = "Masukkan keyword, lalu klik Cari."
