-- Modified DUMPER v2.2.4 – Mobile Edition
-- Changes:
--   1. All scripts are now written to a single Lua file (AllScripts.lua) instead of per‑service folders.
--   2. Remote list is also written to a single text file (Remotes.txt).
--   3. Folder creation for per‑service script storage is retained for backward compatibility but no longer used for script output.
--   4. Minor clean‑up of comments.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- ==========================================
-- 1. File System & Clipboard helpers
-- ==========================================
local hasFileSystem = (typeof(writefile) == "function" and typeof(makefolder) == "function")
local hasIsFolder = (typeof(isfolder) == "function")
local hasClipboard = (typeof(setclipboard) == "function" or typeof(toclipboard) == "function")
local hasDecompile = (typeof(decompile) == "function")

local function copyToClipboard(text)
    if typeof(setclipboard) == "function" then
        pcall(setclipboard, text)
        return true
    elseif typeof(toclipboard) == "function" then
        pcall(toclipboard, text)
        return true
    end
    return false
end

local function ensureFolder(path)
    if not hasFileSystem then return false end
    local ok = pcall(function()
        if hasIsFolder then
            if not isfolder(path) then
                makefolder(path)
            end
        else
            makefolder(path)
        end
    end)
    return ok
end

local function safeWriteFile(path, content)
    if not hasFileSystem then return false end
    local ok = pcall(function()
        writefile(path, content)
    end)
    return ok
end

local function sanitizeFileName(name)
    return (string.gsub(name, '[\\/:*?"<>|%c]', "_"))
end

-- ==========================================
-- 2. Configuration
-- ==========================================
local Config = {
    Scripts = { LocalScript = true, ModuleScript = true, ClientRunScript = true },
    Remotes = { RemoteEvent = true, RemoteFunction = true, Bindables = false },
    Services = { ReplicatedFirst = true, StarterGui = true, StarterPack = true, StarterPlayer = true, Lighting = true },
    Reports = { ScriptIndex = true, HierarchyTree = true, GameInfo = true },
    Performance = { ChunkYield = true },
    Advanced = {
        OutputFormat = ".lua",
        DecompileTimeout = false,
        TimeoutDuration = 60,
        MaxFileSizeIndex = 1, -- 1 = OFF, 2 = 50KB, 3 = 100KB, 4 = 500KB
        IncludeDisabledScripts = false,
        DumpProperties = false,
        DetectObfuscation = true,
        AutoCopySummary = false,
    },
    ReportsAdvanced = { JSONExport = true, DependencyGraph = true, SizeBreakdown = true },
}

local Formats = {".lua", ".txt", ".json"}
local FormatIndex = 1
local FileSizes = {"OFF", "50KB", "100KB", "500KB"}
local FileSizeBytes = {math.huge, 50 * 1024, 100 * 1024, 500 * 1024}

-- ==========================================
-- 3. UI creation (unchanged)
-- ==========================================
local function getParentGui()
    local ok, gui = pcall(function()
        return (typeof(gethui) == "function" and gethui()) or CoreGui
    end)
    if ok and gui then return gui end
    return LocalPlayer:WaitForChild("PlayerGui")
end

local parentGui = getParentGui()
local oldGui = parentGui:FindFirstChild("DumperMobileUI")
if oldGui then oldGui:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "DumperMobileUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = parentGui

-- Floating button (unchanged)
local FloatBtn = Instance.new("TextButton")
FloatBtn.Name = "FloatToggle"
FloatBtn.Size = UDim2.new(0, 86, 0, 32)
FloatBtn.Position = UDim2.new(0, 16, 0.5, -16)
FloatBtn.BackgroundColor3 = Color3.fromRGB(24, 25, 36)
FloatBtn.Text = "📦 DUMPER"
FloatBtn.TextColor3 = Color3.fromRGB(235, 238, 255)
FloatBtn.Font = Enum.Font.GothamBold
FloatBtn.TextSize = 11
FloatBtn.Visible = UserInputService.TouchEnabled
FloatBtn.Parent = ScreenGui

local FloatCorner = Instance.new("UICorner")
FloatCorner.CornerRadius = UDim.new(1, 0)
FloatCorner.Parent = FloatBtn

local FloatStroke = Instance.new("UIStroke")
FloatStroke.Color = Color3.fromRGB(114, 105, 227)
FloatStroke.Thickness = 1.5
FloatStroke.Parent = FloatBtn

-- Main window (unchanged)
local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
MainFrame.Size = UDim2.new(0, 320, 0, 420)
MainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
MainFrame.BackgroundColor3 = Color3.fromRGB(24, 25, 36)
MainFrame.BorderSizePixel = 0
MainFrame.ClipsDescendants = true
MainFrame.Active = true
MainFrame.Parent = ScreenGui

local MainScale = Instance.new("UIScale")
MainScale.Parent = MainFrame

local function updateResponsiveScale()
    if not Camera then Camera = Workspace.CurrentCamera end
    if not Camera then return end
    local vp = Camera.ViewportSize
    local margin = 24
    local scaleX = (vp.X - margin) / 320
    local scaleY = (vp.Y - margin) / 420
    local targetScale = math.min(1, scaleX, scaleY)
    MainScale.Scale = math.clamp(targetScale, 0.55, 1)
end

updateResponsiveScale()
if Camera then
    Camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsiveScale)
end

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 8)
MainCorner.Parent = MainFrame

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(48, 51, 72)
MainStroke.Thickness = 1
MainStroke.Parent = MainFrame

-- Top bar, etc. (omitted for brevity – unchanged UI code continues below)…

-- ==========================================
-- 4. UI helpers (category headers, toggles, etc.) – unchanged
-- ==========================================
local layoutOrder = 0
local function nextOrder()
    layoutOrder += 1
    return layoutOrder
end

local function createCategoryHeader(titleText)
    local HeaderFrame = Instance.new("Frame")
    HeaderFrame.Size = UDim2.new(1, 0, 0, 24)
    HeaderFrame.BackgroundTransparency = 1
    HeaderFrame.LayoutOrder = nextOrder()
    HeaderFrame.Parent = ScrollFrame

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(1, 0, 1, -4)
    Label.Position = UDim2.new(0, 0, 0, 4)
    Label.BackgroundTransparency = 1
    Label.Text = string.upper(titleText)
    Label.TextColor3 = Color3.fromRGB(95, 100, 125)
    Label.Font = Enum.Font.GothamBold
    Label.TextSize = 9
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.Parent = HeaderFrame

    local Divider = Instance.new("Frame")
    Divider.Size = UDim2.new(1, 0, 0, 1)
    Divider.Position = UDim2.new(0, 0, 1, -1)
    Divider.BackgroundColor3 = Color3.fromRGB(36, 38, 54)
    Divider.BorderSizePixel = 0
    Divider.Parent = HeaderFrame
end

local function createToggle(labelText, defaultState, callback)
    local RowBtn = Instance.new("TextButton")
    RowBtn.Size = UDim2.new(1, 0, 0, 32)
    RowBtn.BackgroundTransparency = 1
    RowBtn.Text = ""
    RowBtn.AutoButtonColor = false
    RowBtn.LayoutOrder = nextOrder()
    RowBtn.Parent = ScrollFrame

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(0.74, 0, 1, 0)
    Label.BackgroundTransparency = 1
    Label.Text = labelText
    Label.TextColor3 = Color3.fromRGB(205, 210, 230)
    Label.Font = Enum.Font.Gotham
    Label.TextSize = 11
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.Parent = RowBtn

    local ToggleBg = Instance.new("Frame")
    ToggleBg.Size = UDim2.new(0, 38, 0, 20)
    ToggleBg.Position = UDim2.new(1, -38, 0.5, -10)
    ToggleBg.BackgroundColor3 = defaultState and Color3.fromRGB(114, 105, 227) or Color3.fromRGB(50, 53, 72)
    ToggleBg.Parent = RowBtn

    local ToggleCorner = Instance.new("UICorner")
    ToggleCorner.CornerRadius = UDim.new(1, 0)
    ToggleCorner.Parent = ToggleBg

    local Knob = Instance.new("Frame")
    Knob.Size = UDim2.new(0, 16, 0, 16)
    Knob.Position = defaultState and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
    Knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    Knob.BorderSizePixel = 0
    Knob.Parent = ToggleBg

    local KnobCorner = Instance.new("UICorner")
    KnobCorner.CornerRadius = UDim.new(1, 0)
    KnobCorner.Parent = Knob

    local state = defaultState
    RowBtn.Activated:Connect(function()
        state = not state
        TweenService:Create(ToggleBg, TweenInfo.new(0.15), {BackgroundColor3 = state and Color3.fromRGB(114, 105, 227) or Color3.fromRGB(50, 53, 72)}):Play()
        TweenService:Create(Knob, TweenInfo.new(0.15), {Position = state and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)}):Play()
        callback(state)
    end)
end

local function createCycleSelector(labelText, initialText, onClick)
    local Row = Instance.new("Frame")
    Row.Size = UDim2.new(1, 0, 0, 32)
    Row.BackgroundTransparency = 1
    Row.LayoutOrder = nextOrder()
    Row.Parent = ScrollFrame

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(0.65, 0, 1, 0)
    Label.BackgroundTransparency = 1
    Label.Text = labelText
    Label.TextColor3 = Color3.fromRGB(205, 210, 230)
    Label.Font = Enum.Font.Gotham
    Label.TextSize = 11
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.Parent = Row

    local PillBtn = Instance.new("TextButton")
    PillBtn.Size = UDim2.new(0, 54, 0, 24)
    PillBtn.Position = UDim2.new(1, -54, 0.5, -12)
    PillBtn.BackgroundColor3 = Color3.fromRGB(38, 41, 60)
    PillBtn.Text = initialText
    PillBtn.TextColor3 = Color3.fromRGB(140, 130, 245)
    PillBtn.Font = Enum.Font.GothamBold
    PillBtn.TextSize = 11
    PillBtn.Parent = Row

    local PillCorner = Instance.new("UICorner")
    PillCorner.CornerRadius = UDim.new(0, 5)
    PillCorner.Parent = PillBtn

    PillBtn.Activated:Connect(function()
        PillBtn.Text = onClick()
    end)
end

local function createStepper(labelText, initialValueText, onStep)
    local Row = Instance.new("Frame")
    Row.Size = UDim2.new(1, 0, 0, 32)
    Row.BackgroundTransparency = 1
    Row.LayoutOrder = nextOrder()
    Row.Parent = ScrollFrame

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(0.58, 0, 1, 0)
    Label.BackgroundTransparency = 1
    Label.Text = labelText
    Label.TextColor3 = Color3.fromRGB(205, 210, 230)
    Label.Font = Enum.Font.Gotham
    Label.TextSize = 11
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.Parent = Row

    local StepperBox = Instance.new("Frame")
    StepperBox.Size = UDim2.new(0, 88, 0, 24)
    StepperBox.Position = UDim2.new(1, -88, 0.5, -12)
    StepperBox.BackgroundColor3 = Color3.fromRGB(36, 38, 54)
    StepperBox.Parent = Row

    local BoxCorner = Instance.new("UICorner")
    BoxCorner.CornerRadius = UDim.new(0, 5)
    BoxCorner.Parent = StepperBox

    local MinusBtn = Instance.new("TextButton")
    MinusBtn.Size = UDim2.new(0, 26, 1, 0)
    MinusBtn.BackgroundTransparency = 1
    MinusBtn.Text = "-"
    MinusBtn.TextColor3 = Color3.fromRGB(180, 185, 210)
    MinusBtn.Font = Enum.Font.GothamBold
    MinusBtn.TextSize = 14
    MinusBtn.Parent = StepperBox

    local ValueLabel = Instance.new("TextLabel")
    ValueLabel.Size = UDim2.new(1, -52, 1, 0)
    ValueLabel.Position = UDim2.new(0, 26, 0, 0)
    ValueLabel.BackgroundTransparency = 1
    ValueLabel.Text = initialValueText
    ValueLabel.TextColor3 = Color3.fromRGB(230, 235, 250)
    ValueLabel.Font = Enum.Font.GothamBold
    ValueLabel.TextSize = 10
    ValueLabel.Parent = StepperBox

    local PlusBtn = Instance.new("TextButton")
    PlusBtn.Size = UDim2.new(0, 26, 1, 0)
    PlusBtn.Position = UDim2.new(1, -26, 0, 0)
    PlusBtn.BackgroundTransparency = 1
    PlusBtn.Text = "+"
    PlusBtn.TextColor3 = Color3.fromRGB(180, 185, 210)
    PlusBtn.Font = Enum.Font.GothamBold
    PlusBtn.TextSize = 14
    PlusBtn.Parent = StepperBox

    MinusBtn.Activated:Connect(function()
        ValueLabel.Text = onStep(-1)
    end)
    PlusBtn.Activated:Connect(function()
        ValueLabel.Text = onStep(1)
    end)
end

-- ==========================================
-- 5. Populate UI (unchanged)
-- ==========================================
createCategoryHeader("SCRIPTS")
createToggle("LocalScript", Config.Scripts.LocalScript, function(v) Config.Scripts.LocalScript = v end)
createToggle("ModuleScript", Config.Scripts.ModuleScript, function(v) Config.Scripts.ModuleScript = v end)
createToggle("Script (Client Run)", Config.Scripts.ClientRunScript, function(v) Config.Scripts.ClientRunScript = v end)

createCategoryHeader("REMOTES")
createToggle("RemoteEvent", Config.Remotes.RemoteEvent, function(v) Config.Remotes.RemoteEvent = v end)
createToggle("RemoteFunction", Config.Remotes.RemoteFunction, function(v) Config.Remotes.RemoteFunction = v end)
createToggle("Bindables", Config.Remotes.Bindables, function(v) Config.Remotes.Bindables = v end)

createCategoryHeader("SERVICES")
createToggle("ReplicatedFirst", Config.Services.ReplicatedFirst, function(v) Config.Services.ReplicatedFirst = v end)
createToggle("StarterGui", Config.Services.StarterGui, function(v) Config.Services.StarterGui = v end)
createToggle("StarterPack", Config.Services.StarterPack, function(v) Config.Services.StarterPack = v end)
createToggle("StarterPlayer", Config.Services.StarterPlayer, function(v) Config.Services.StarterPlayer = v end)
createToggle("Lighting", Config.Services.Lighting, function(v) Config.Services.Lighting = v end)

createCategoryHeader("REPORTS")
createToggle("Script Index", Config.Reports.ScriptIndex, function(v) Config.Reports.ScriptIndex = v end)
createToggle("Hierarchy Tree", Config.Reports.HierarchyTree, function(v) Config.Reports.HierarchyTree = v end)
createToggle("Game Info", Config.Reports.GameInfo, function(v) Config.Reports.GameInfo = v end)

createCategoryHeader("PERFORMANCE")
createToggle("Chunk Yield (no freeze)", Config.Performance.ChunkYield, function(v) Config.Performance.ChunkYield = v end)

createCategoryHeader("ADVANCED")
createCycleSelector("Output Format", Config.Advanced.OutputFormat, function()
    FormatIndex = (FormatIndex % #Formats) + 1
    Config.Advanced.OutputFormat = Formats[FormatIndex]
    return Config.Advanced.OutputFormat
end)
createToggle("Decompile Timeout", Config.Advanced.DecompileTimeout, function(v) Config.Advanced.DecompileTimeout = v end)
createStepper("Timeout Duration", tostring(Config.Advanced.TimeoutDuration) .. "s", function(delta)
    Config.Advanced.TimeoutDuration = math.clamp(Config.Advanced.TimeoutDuration + (delta * 10), 10, 300)
    return tostring(Config.Advanced.TimeoutDuration) .. "s"
end)
createStepper("Max File Size", FileSizes[Config.Advanced.MaxFileSizeIndex], function(delta)
    Config.Advanced.MaxFileSizeIndex = math.clamp(Config.Advanced.MaxFileSizeIndex + delta, 1, #FileSizes)
    return FileSizes[Config.Advanced.MaxFileSizeIndex]
end)
createToggle("Include Disabled Scripts", Config.Advanced.IncludeDisabledScripts, function(v) Config.Advanced.IncludeDisabledScripts = v end)
createToggle("Dump Properties", Config.Advanced.DumpProperties, function(v) Config.Advanced.DumpProperties = v end)
createToggle("Detect Obfuscation", Config.Advanced.DetectObfuscation, function(v) Config.Advanced.DetectObfuscation = v end)
createToggle("Auto-copy Summary", Config.Advanced.AutoCopySummary, function(v) Config.Advanced.AutoCopySummary = v end)

createCategoryHeader("REPORTS (ADVANCED)")
createToggle("JSON Export", Config.ReportsAdvanced.JSONExport, function(v) Config.ReportsAdvanced.JSONExport = v end)
createToggle("Dependency Graph", Config.ReportsAdvanced.DependencyGraph, function(v) Config.ReportsAdvanced.DependencyGraph = v end)
createToggle("Size Breakdown", Config.ReportsAdvanced.SizeBreakdown, function(v) Config.ReportsAdvanced.SizeBreakdown = v end)

-- ==========================================
-- 6. Overlay for summary (unchanged)
-- ==========================================
local OutputOverlay = Instance.new("Frame")
OutputOverlay.Size = UDim2.new(1, 0, 1, -38)
OutputOverlay.Position = UDim2.new(0, 0, 0, 38)
OutputOverlay.BackgroundColor3 = Color3.fromRGB(18, 19, 28)
OutputOverlay.BorderSizePixel = 0
OutputOverlay.Visible = false
OutputOverlay.ZIndex = 10
OutputOverlay.Parent = MainFrame

local OverlayHeader = Instance.new("Frame")
OverlayHeader.Size = UDim2.new(1, 0, 0, 32)
OverlayHeader.BackgroundColor3 = Color3.fromRGB(28, 30, 44)
OverlayHeader.BorderSizePixel = 0
OverlayHeader.ZIndex = 11
OverlayHeader.Parent = OutputOverlay

local OverlayTitle = Instance.new("TextLabel")
OverlayTitle.Size = UDim2.new(1, -130, 1, 0)
OverlayTitle.Position = UDim2.new(0, 12, 0, 0)
OverlayTitle.BackgroundTransparency = 1
OverlayTitle.Text = "DUMP SUMMARY"
OverlayTitle.TextColor3 = Color3.fromRGB(235, 240, 255)
OverlayTitle.Font = Enum.Font.GothamBold
OverlayTitle.TextSize = 11
OverlayTitle.TextXAlignment = Enum.TextXAlignment.Left
OverlayTitle.ZIndex = 11
OverlayTitle.Parent = OverlayHeader

local CopySummaryBtn = Instance.new("TextButton")
CopySummaryBtn.Size = UDim2.new(0, 56, 0, 22)
CopySummaryBtn.Position = UDim2.new(1, -118, 0.5, -11)
CopySummaryBtn.BackgroundColor3 = Color3.fromRGB(114, 105, 227)
CopySummaryBtn.Text = "COPY"
CopySummaryBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopySummaryBtn.Font = Enum.Font.GothamBold
CopySummaryBtn.TextSize = 10
CopySummaryBtn.ZIndex = 11
CopySummaryBtn.Parent = OverlayHeader

local CopyBtnCorner = Instance.new("UICorner")
CopyBtnCorner.CornerRadius = UDim.new(0, 4)
CopyBtnCorner.Parent = CopySummaryBtn

local BackToSettingsBtn = Instance.new("TextButton")
BackToSettingsBtn.Size = UDim2.new(0, 52, 0, 22)
BackToSettingsBtn.Position = UDim2.new(1, -58, 0.5, -11)
BackToSettingsBtn.BackgroundColor3 = Color3.fromRGB(52, 55, 76)
BackToSettingsBtn.Text = "BACK"
BackToSettingsBtn.TextColor3 = Color3.fromRGB(220, 225, 245)
BackToSettingsBtn.Font = Enum.Font.GothamBold
BackToSettingsBtn.TextSize = 10
BackToSettingsBtn.ZIndex = 11
BackToSettingsBtn.Parent = OverlayHeader

local BackBtnCorner = Instance.new("UICorner")
BackBtnCorner.CornerRadius = UDim.new(0, 4)
BackBtnCorner.Parent = BackToSettingsBtn

local OutputScroll = Instance.new("ScrollingFrame")
OutputScroll.Size = UDim2.new(1, -16, 1, -40)
OutputScroll.Position = UDim2.new(0, 8, 0, 36)
OutputScroll.BackgroundColor3 = Color3.fromRGB(14, 15, 22)
OutputScroll.BorderSizePixel = 0
OutputScroll.ScrollBarThickness = 5
OutputScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
OutputScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
OutputScroll.ZIndex = 11
OutputScroll.Parent = OutputOverlay

local OutputBox = Instance.new("TextBox")
OutputBox.Size = UDim2.new(1, -12, 0, 0)
OutputBox.Position = UDim2.new(0, 6, 0, 6)
OutputBox.AutomaticSize = Enum.AutomaticSize.Y
OutputBox.BackgroundTransparency = 1
OutputBox.TextEditable = false
OutputBox.ClearTextOnFocus = false
OutputBox.MultiLine = true
OutputBox.TextWrapped = true
OutputBox.Text = ""
OutputBox.TextColor3 = Color3.fromRGB(210, 220, 245)
OutputBox.Font = Enum.Font.Code
OutputBox.TextSize = 10
OutputBox.TextXAlignment = Enum.TextXAlignment.Left
OutputBox.TextYAlignment = Enum.TextYAlignment.Top
OutputBox.ZIndex = 11
OutputBox.Parent = OutputScroll

BackToSettingsBtn.Activated:Connect(function()
    OutputOverlay.Visible = false
end)

CopySummaryBtn.Activated:Connect(function()
    if copyToClipboard(OutputBox.Text) then
        CopySummaryBtn.Text = "COPIED!"
        task.delay(1.2, function()
            CopySummaryBtn.Text = "COPY"
        end)
    end
end)

-- ==========================================
-- 7. Dump engine – modified to produce single files
-- ==========================================
local function isObfuscated(sourceCode)
    if not sourceCode or #sourceCode == 0 then return false end
    if string.find(sourceCode, "IronBrew") or string.find(sourceCode, "MoonSec") or string.find(sourceCode, "Luraph") then
        return true
    end
    local _, escapeCount = string.gsub(sourceCode, "\\%d%d%d", "")
    return escapeCount > 40
end

local function extractRequires(sourceCode)
    local deps = {}
    if not sourceCode then return deps end
    for match in string.gmatch(sourceCode, "require%s*%(([^%)]+)%)") do
        table.insert(deps, match)
    end
    return deps
end

local function getScriptContent(scriptInstance, timeoutSec)
    local okSrc, src = pcall(function() return scriptInstance.Source end)
    if okSrc and typeof(src) == "string" and #src > 0 then
        return src
    end
    if hasDecompile then
        local result = nil
        local finished = false
        task.spawn(function()
            local okDec, dec = pcall(decompile, scriptInstance)
            if okDec and typeof(dec) == "string" then
                result = dec
            end
            finished = true
        end)
        local waited = 0
        local maxWait = Config.Advanced.DecompileTimeout and timeoutSec or 10
        while not finished and waited < maxWait do
            waited += task.wait(0.05)
        end
        if result then return result end
    end
    return "-- [Source unavailable or protected in current environment]\n-- Path: " .. scriptInstance:GetFullName()
end

local isDumping = false

StartDumpBtn.Activated:Connect(function()
    if isDumping then return end
    isDumping = true
    StartDumpBtn.BackgroundColor3 = Color3.fromRGB(75, 70, 150)
    StartDumpBtn.Text = "DUMPING..."
    StatusLabel.Text = "Preparing workspace..."

    task.spawn(function()
        local startTime = os.clock()
        local cleanPlaceName = sanitizeFileName(PlaceNameText)
        local rootFolderName = string.format("Dump_%s_%d", cleanPlaceName, game.PlaceId)

        -- Filesystem folder (still created for compatibility)
        local fsReady = ensureFolder(rootFolderName)
        if fsReady then
            ensureFolder(rootFolderName .. "/Reports")
        end

        -- In‑game folder (unchanged)
        local oldWsFolder = Workspace:FindFirstChild(rootFolderName)
        if oldWsFolder then oldWsFolder:Destroy() end
        local wsRootFolder = Instance.new("Folder")
        wsRootFolder.Name = rootFolderName
        wsRootFolder.Parent = Workspace
        local wsScriptsFolder = Instance.new("Folder")
        wsScriptsFolder.Name = "Scripts"
        wsScriptsFolder.Parent = wsRootFolder
        local wsRemotesFolder = Instance.new("Folder")
        wsRemotesFolder.Name = "Remotes"
        wsRemotesFolder.Parent = wsRootFolder
        local wsReportsFolder = Instance.new("Folder")
        wsReportsFolder.Name = "Reports"
        wsReportsFolder.Parent = wsRootFolder

        -- Helper to write reports both to FS and in‑game (unchanged)
        local function saveReportBoth(fileName, content)
            if fsReady then
                safeWriteFile(rootFolderName .. "/Reports/" .. fileName, content)
            end
            local val = Instance.new("StringValue")
            val.Name = fileName
            val.Value = string.sub(content, 1, 190000)
            val.Parent = wsReportsFolder
        end

        local targetServices = {}
        for serviceName, enabled in pairs(Config.Services) do
            if enabled then
                local ok, srv = pcall(function() return game:GetService(serviceName) end)
                if ok and srv then table.insert(targetServices, srv) end
            end
        end

        local collectedScripts = {}
        local collectedRemotes = {}
        local treeLines = {}
        local processedCount = 0
        local allScriptContent = "" -- accumulator for single script file
        local remoteListContent = "" -- accumulator for remote list file

        for _, srv in ipairs(targetServices) do
            table.insert(treeLines, "[" .. srv.Name .. "]")
            local srvFolderInWs = Instance.new("Folder")
            srvFolderInWs.Name = srv.Name
            srvFolderInWs.Parent = wsScriptsFolder
            local descendants = srv:GetDescendants()
            for _, inst in ipairs(descendants) do
                processedCount += 1
                if Config.Performance.ChunkYield and (processedCount % 120 == 0) then
                    StatusLabel.Text = string.format("Scanning (%d items)...", processedCount)
                    task.wait()
                end

                if Config.Advanced.DecompileTimeout and (os.clock() - startTime > Config.Advanced.TimeoutDuration) then
                    table.insert(treeLines, "  [!] Global Timeout Reached")
                    break
                end

                -- --- SCRIPT HANDLING -------------------------------------------------
                local isTargetScript = false
                if inst:IsA("LocalScript") and Config.Scripts.LocalScript then
                    isTargetScript = true
                elseif inst:IsA("ModuleScript") and Config.Scripts.ModuleScript then
                    isTargetScript = true
                elseif inst:IsA("Script") and Config.Scripts.ClientRunScript then
                    local okRun, runCtx = pcall(function() return inst.RunContext end)
                    if okRun and runCtx == Enum.RunContext.Client then isTargetScript = true end
                end

                if isTargetScript then
                    local isDisabled = false
                    pcall(function() isDisabled = inst.Disabled end)
                    if not isDisabled or Config.Advanced.IncludeDisabledScripts then
                        local src = getScriptContent(inst, Config.Advanced.TimeoutDuration)
                        local sourceLen = #src
                        local maxAllowed = FileSizeBytes[Config.Advanced.MaxFileSizeIndex]
                        if sourceLen <= maxAllowed then
                            local obf = Config.Advanced.DetectObfuscation and isObfuscated(src)
                            local propStr = ""
                            if Config.Advanced.DumpProperties then
                                propStr = string.format(" [Class=%s, Disabled=%s]", inst.ClassName, tostring(isDisabled))
                            end
                            local headerComment = string.format(
                                "-- Path: %s\n-- Class: %s | Size: %d bytes%s\n\n",
                                inst:GetFullName(),
                                inst.ClassName,
                                sourceLen,
                                obf and " | [OBFUSCATED]" or ""
                            )
                            local fileContent = headerComment .. src

                            -- Append to the single Lua dump file (only for .lua output)
                            allScriptContent = allScriptContent .. "\n" .. fileContent

                            local entry = {
                                Path = inst:GetFullName(),
                                ClassName = inst.ClassName,
                                Size = sourceLen,
                                Obfuscated = obf,
                                Properties = propStr,
                                Dependencies = extractRequires(src),
                            }
                            table.insert(collectedScripts, entry)
                            table.insert(treeLines, "  ├─ 📜 " .. inst:GetFullName() .. (obf and " [⚠️ OBF]" or ""))
                        end
                    end
                end

                -- --- REMOTE HANDLING -------------------------------------------------
                local isTargetRemote = (inst:IsA("RemoteEvent") and Config.Remotes.RemoteEvent) or
                    (inst:IsA("RemoteFunction") and Config.Remotes.RemoteFunction) or
                    ((inst:IsA("BindableEvent") or inst:IsA("BindableFunction")) and Config.Remotes.Bindables)
                if isTargetRemote then
                    local rmEntry = { Path = inst:GetFullName(), ClassName = inst.ClassName }
                    table.insert(collectedRemotes, rmEntry)
                    table.insert(treeLines, "  ├─ 📡 " .. inst:GetFullName() .. " (" .. inst.ClassName .. ")")
                    -- Add to remote list string (plain text)
                    remoteListContent = remoteListContent .. string.format("%s (%s)\n", inst:GetFullName(), inst.ClassName)
                    -- In‑game representation (unchanged)
                    local rVal = Instance.new("ObjectValue")
                    rVal.Name = inst.Name .. " [" .. inst.ClassName .. "]"
                    rVal.Value = inst
                    rVal.Parent = wsRemotesFolder
                end
            end
        end

        -- ------------------- REPORTS ----------------------------------------
        local summaryLines = {}
        local function addSummary(line) table.insert(summaryLines, line) end
        addSummary("========================================")
        addSummary("WORKSPACE DUMP COMPLETED")
        addSummary("========================================")
        addSummary("Game          : " .. PlaceNameText .. " (#" .. tostring(game.PlaceId) .. ")")
        addSummary("In-Game Save  : workspace." .. rootFolderName)
        addSummary("Executor Save : " .. (fsReady and ("workspace/" .. rootFolderName .. "/") or "Not supported (Saved in game.Workspace only)"))
        addSummary("Total Scripts : " .. tostring(#collectedScripts))
        addSummary("Total Remotes : " .. tostring(#collectedRemotes))
        addSummary("Elapsed Time  : " .. string.format("%.2fs", os.clock() - startTime))
        addSummary("")

        if Config.Reports.GameInfo then
            local gameInfoText = table.concat({
                "Place Name : " .. PlaceNameText,
                "Place ID   : " .. tostring(game.PlaceId),
                "Job ID     : " .. tostring(game.JobId),
                "Format     : " .. Config.Advanced.OutputFormat,
                "Scripts    : " .. tostring(#collectedScripts),
                "Remotes    : " .. tostring(#collectedRemotes),
            }, "\n")
            saveReportBoth("GameInfo.txt", gameInfoText)
        end

        if Config.Reports.ScriptIndex then
            local idxLines = {"SCRIPT INDEX (" .. #collectedScripts .. " found)", "----------------------------------------"}
            for i, sc in ipairs(collectedScripts) do
                local line = string.format("[%d] %s (%d B)%s%s", i, sc.Path, sc.Size, sc.Properties, sc.Obfuscated and " [OBFUSCATED]" or "")
                table.insert(idxLines, line)
                addSummary(line)
            end
            addSummary("")
            saveReportBoth("ScriptIndex.txt", table.concat(idxLines, "\n"))
        end

        if #collectedRemotes > 0 then
            local rmLines = {"REMOTES INDEX (" .. #collectedRemotes .. " found)", "----------------------------------------"}
            for i, rm in ipairs(collectedRemotes) do
                table.insert(rmLines, string.format("[%d] [%s] %s", i, rm.ClassName, rm.Path))
            end
            local rmText = table.concat(rmLines, "\n")
            saveReportBoth("RemotesIndex.txt", rmText)
            if fsReady then
                safeWriteFile(rootFolderName .. "/Remotes/RemotesList.txt", rmText)
            end
            -- Also write the simple remote list (single file)
            if fsReady then
                safeWriteFile(rootFolderName .. "/AllRemotes.txt", remoteListContent)
            end
        end

        if Config.Reports.HierarchyTree then
            local treeText = table.concat(treeLines, "\n")
            saveReportBoth("HierarchyTree.txt", treeText)
        end

        if Config.ReportsAdvanced.DependencyGraph then
            local depLines = {"DEPENDENCY GRAPH", "----------------------------------------"}
            for _, sc in ipairs(collectedScripts) do
                if #sc.Dependencies > 0 then
                    table.insert(depLines, sc.Path .. " -> requires:")
                    for _, dep in ipairs(sc.Dependencies) do
                        table.insert(depLines, "   └── " .. dep)
                    end
                end
            end
            saveReportBoth("DependencyGraph.txt", table.concat(depLines, "\n"))
        end

        if Config.ReportsAdvanced.SizeBreakdown then
            local sizeLines = {"SIZE BREAKDOWN", "----------------------------------------"}
            local sorted = table.clone(collectedScripts)
            table.sort(sorted, function(a, b) return a.Size > b.Size end)
            for _, sc in ipairs(sorted) do
                table.insert(sizeLines, string.format("%7d bytes | %s", sc.Size, sc.Path))
            end
            saveReportBoth("SizeBreakdown.txt", table.concat(sizeLines, "\n"))
        end

        if Config.ReportsAdvanced.JSONExport then
            local okJson, encoded = pcall(function()
                return HttpService:JSONEncode({
                    PlaceId = game.PlaceId,
                    PlaceName = PlaceNameText,
                    Scripts = collectedScripts,
                    Remotes = collectedRemotes,
                })
            end)
            if okJson then
                saveReportBoth("Export.json", encoded)
            end
        end

        -- Write the combined script dump (single Lua file)
        if fsReady then
            local scriptFilePath = rootFolderName .. "/AllScripts" .. Config.Advanced.OutputFormat
            safeWriteFile(scriptFilePath, allScriptContent)
        end

        local finalSummary = table.concat(summaryLines, "\n")
        OutputBox.Text = finalSummary
        OutputOverlay.Visible = true
        if Config.Advanced.AutoCopySummary then
            copyToClipboard(finalSummary)
        end
        StatusLabel.Text = "Saved to " .. rootFolderName
        StartDumpBtn.BackgroundColor3 = Color3.fromRGB(114, 105, 227)
        StartDumpBtn.Text = "START DUMP"
        isDumping = false
    end)
end)

-- ==========================================
-- 8. Draggable UI (unchanged)
-- ==========================================
local function makeDraggable(dragHandle, targetFrame)
    local dragging = false
    local dragInput = nil
    local dragStart = nil
    local startPos = nil

    dragHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = targetFrame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    dragHandle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            local vp = Camera and Camera.ViewportSize or Vector2.new(1280, 720)
            local absSize = targetFrame.AbsoluteSize
            local anchor = targetFrame.AnchorPoint

            local newX = startPos.X.Scale * vp.X + startPos.X.Offset + delta.X
            local newY = startPos.Y.Scale * vp.Y + startPos.Y.Offset + delta.Y

            local minX = absSize.X * anchor.X + 6
            local maxX = vp.X - absSize.X * (1 - anchor.X) - 6
            local minY = absSize.Y * anchor.Y + 6
            local maxY = vp.Y - absSize.Y * (1 - anchor.Y) - 6

            newX = math.clamp(newX, math.min(minX, maxX), math.max(minX, maxX))
            newY = math.clamp(newY, math.min(minY, maxY), math.max(minY, maxY))

            targetFrame.Position = UDim2.new(0, newX, 0, newY)
        end
    end)
end

makeDraggable(TopBar, MainFrame)
makeDraggable(FloatBtn, FloatBtn)

-- Minimize / Close handling (unchanged)
local isMinimized = false
MinimizeBtn.Activated:Connect(function()
    isMinimized = not isMinimized
    if isMinimized then
        OutputOverlay.Visible = false
    end
    TweenService:Create(MainFrame, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = isMinimized and UDim2.new(0, 320, 0, 38) or UDim2.new(0, 320, 0, 420)
    }):Play()
end)

FloatBtn.Activated:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

CloseBtn.Activated:Connect(function()
    if UserInputService.TouchEnabled then
        MainFrame.Visible = false
        FloatBtn.Visible = true
    else
        ScreenGui:Destroy()
    end
end)

-- End of modified script
