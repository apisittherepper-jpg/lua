local function showFatal(msg)
    warn("[DUMPER] " .. tostring(msg))
    pcall(function()
        local p = (typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui")
        local g = Instance.new("ScreenGui")
        g.Name = "DumperFatal"
        g.ResetOnSpawn = false
        g.Parent = p
        local t = Instance.new("TextLabel")
        t.Size = UDim2.new(1, -20, 0, 130)
        t.Position = UDim2.fromOffset(10, 10)
        t.BackgroundColor3 = Color3.fromRGB(90, 20, 20)
        t.TextColor3 = Color3.new(1, 1, 1)
        t.TextWrapped = true
        t.TextSize = 12
        t.Font = Enum.Font.Code
        t.TextXAlignment = Enum.TextXAlignment.Left
        t.TextYAlignment = Enum.TextYAlignment.Top
        t.Text = "DUMPER ERROR:\n" .. string.sub(tostring(msg), 1, 700)
        t.Parent = g
        task.delay(40, function() g:Destroy() end)
    end)
end

local mainOk, mainErr = xpcall(function()

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local Market = game:GetService("MarketplaceService")
local CoreGui = game:GetService("CoreGui")
local WS = game:GetService("Workspace")
local CS = game:GetService("CollectionService")

repeat task.wait() until Players.LocalPlayer
local LP = Players.LocalPlayer
local Camera = WS.CurrentCamera
local genv = (typeof(getgenv) == "function" and getgenv()) or {}

-- ==========================================
-- 1. Helpers
-- ==========================================
local hasWrite = (typeof(writefile) == "function")
local hasDecompile = (typeof(decompile) == "function")
local hasBytecode = (typeof(getscriptbytecode) == "function")
local hasNilInstances = (typeof(getnilinstances) == "function")

local function copyToClipboard(text)
    if #text > 450 * 1024 then
        text = string.sub(text, 1, 450 * 1024) .. "\n-- [TRUNCATED FOR CLIPBOARD SAFETY]"
    end
    if typeof(setclipboard) == "function" then
        return (pcall(setclipboard, text))
    elseif typeof(toclipboard) == "function" then
        return (pcall(toclipboard, text))
    end
    return false
end

local function safeWrite(path, content)
    if not hasWrite then return false end
    content = string.gsub(content, "%z", "\\000")
    return (pcall(writefile, path, content))
end

local IgnoredNames = {
    PlayerModule = true, ControlModule = true, CameraModule = true, ChatScript = true,
    BubbleChat = true, Animate = true, RbxCharacterSounds = true, AtomicBinding = true,
    DefaultChatSystemChatEvents = true, RobloxGui = true, Freecam = true, PlayerScriptsLoader = true,
    RbxCharacterSoundsAtomic = true, CorePackages = true,
}

local function shouldIgnore(inst)
    local cur = inst
    while cur and cur ~= game do
        if IgnoredNames[cur.Name] then return true end
        cur = cur.Parent
    end
    return false
end

local function isCoreDescendant(inst)
    if inst == CoreGui or inst:IsDescendantOf(CoreGui) then return true end
    local ok, cp = pcall(game.GetService, game, "CorePackages")
    if ok and cp and (inst == cp or inst:IsDescendantOf(cp)) then return true end
    return false
end

local function formatLuaPath(inst)
    if inst == game then return "game" end
    local segs, cur = {}, inst
    while cur and cur ~= game do
        table.insert(segs, 1, cur)
        cur = cur.Parent
    end
    if #segs == 0 then return "nil" end

    local isRooted = (cur == game)
    local result
    local start = 2

    if isRooted then
        local svc = segs[1].ClassName
        result = string.format('game:GetService("%s")', svc)
        if svc == "Players" and segs[2] == LP then
            result = result .. ".LocalPlayer"
            start = 3
        elseif svc == "Workspace" and segs[2] ~= nil and segs[2] == LP.Character then
            result = 'game:GetService("Players").LocalPlayer.Character'
            start = 3
        end
    else
        local rootName = segs[1].Name
        if string.match(rootName, "^[_%a][_%w]*$") then
            result = "nil." .. rootName
        else
            local esc = string.gsub(rootName, '[\\"]', "\\%0")
            result = 'nil["' .. esc .. '"]'
        end
    end

    for i = start, #segs do
        local name = segs[i].Name
        if string.match(name, "^[_%a][_%w]*$") then
            result = result .. "." .. name
        else
            local esc = string.gsub(name, '[\\"]', "\\%0")
            esc = string.gsub(esc, "%c", function(c) return string.format("\\%03d", string.byte(c)) end)
            result = result .. '["' .. esc .. '"]'
        end
    end
    return result
end

-- ==========================================
-- 2. Config
-- ==========================================
local Config = {
    Scripts = { LocalScript = true, ModuleScript = true, ClientRunScript = true },
    Remotes = { RemoteEvent = true, RemoteFunction = true, Bindables = false },
    Services = {
        ReplicatedStorage = true, Workspace = true, StarterPlayer = true, StarterGui = true,
        StarterPack = true, ReplicatedFirst = true, Lighting = false,
    },
    Reports = { ScriptIndex = true, HierarchyTree = true, GameInfo = true },
    Performance = { ChunkYield = true },
    Advanced = {
        SkipDefaultScripts = true, OutputFormat = ".lua", DecompileTimeout = true,
        TimeoutDuration = 10, MaxFileSizeIndex = 3, IncludeDisabledScripts = false,
        DumpProperties = false, DetectObfuscation = true, AutoCopySummary = false,
        SplitParts = 1,
    },
    ReportsAdvanced = { DependencyGraph = true, SizeBreakdown = true },
    Extras = {
        ServiceAttributes = true, UIHierarchy = true, UIConnections = true, UIHideDecor = true,
        RSValues = true, RSForceRequire = false, RemoteLog = false, IncomingLog = false,
        GameInfo = true, PlayerData = true, WorldOverview = true, Interactables = true,
        NPCCensus = true, LoadedModules = true, LiveScripts = true, NilInstances = true,
    },
}

local Formats = { ".lua", ".txt" }
local FormatIndex = 1
local FileSizes = { "OFF", "50KB", "100KB", "500KB" }
local FileSizeBytes = { math.huge, 50 * 1024, 100 * 1024, 500 * 1024 }

-- ==========================================
-- 3. UI (Dear ImGui Compact)
-- ==========================================
local IG = {
    WindowBg = Color3.fromRGB(15, 15, 15), ChildBg = Color3.fromRGB(20, 20, 20),
    Border = Color3.fromRGB(67, 67, 77), Title = Color3.fromRGB(41, 74, 122),
    MenuBar = Color3.fromRGB(36, 36, 36), Header = Color3.fromRGB(38, 73, 118),
    HeaderOff = Color3.fromRGB(28, 46, 72), FrameBg = Color3.fromRGB(29, 46, 72),
    FrameBgActive = Color3.fromRGB(41, 74, 122), Check = Color3.fromRGB(66, 150, 250),
    Button = Color3.fromRGB(41, 74, 122), ButtonActive = Color3.fromRGB(15, 135, 250),
    Text = Color3.fromRGB(255, 255, 255), Dim = Color3.fromRGB(128, 128, 128),
    Font = Enum.Font.RobotoMono,
}

local function mk(class, props, parent)
    local o = Instance.new(class)
    for k, v in next, props do o[k] = v end
    o.Parent = parent
    return o
end

local function stroke(inst, color)
    return mk("UIStroke", {
        Color = color or IG.Border, Thickness = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    }, inst)
end

local function label(parent, text, size, pos, color, align, ts)
    return mk("TextLabel", {
        Size = size, Position = pos or UDim2.new(), BackgroundTransparency = 1, Text = text,
        TextColor3 = color or IG.Text, Font = IG.Font, TextSize = ts or 11,
        TextXAlignment = align or Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
    }, parent)
end

local parentGui
do
    local ok, g = pcall(function() return (typeof(gethui) == "function" and gethui()) or CoreGui end)
    parentGui = (ok and g) or LP:WaitForChild("PlayerGui")
end
pcall(function()
    local old = parentGui:FindFirstChild("DumperMobileUI")
    if old then old:Destroy() end
end)

local ScreenGui = mk("ScreenGui", {
    Name = "DumperMobileUI", ResetOnSpawn = false, IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 999
}, nil)
local okParent = pcall(function() ScreenGui.Parent = parentGui end)
if not okParent then ScreenGui.Parent = LP:WaitForChild("PlayerGui") end

local FloatBtn = mk("TextButton", {
    Name = "FloatToggle", Size = UDim2.fromOffset(96, 22), Position = UDim2.new(0, 12, 0.5, -11),
    BackgroundColor3 = IG.Title, BorderSizePixel = 0, AutoButtonColor = false,
    Text = " [+] Dumper", TextColor3 = IG.Text, Font = IG.Font, TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 50,
}, ScreenGui)
stroke(FloatBtn)

local MainFrame = mk("Frame", {
    Name = "MainFrame", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(265, 310),
    Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = IG.WindowBg, BackgroundTransparency = 0.03,
    BorderSizePixel = 0, ClipsDescendants = true, Active = true,
}, ScreenGui)
stroke(MainFrame)
local MainScale = mk("UIScale", {}, MainFrame)

local function updateScale()
    Camera = WS.CurrentCamera or Camera
    if not Camera then return end
    local vp = Camera.ViewportSize
    MainScale.Scale = math.clamp(math.min(0.95, (vp.X - 24) / 265, (vp.Y - 24) / 310), 0.5, 0.95)
end
updateScale()
if Camera then Camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale) end

local TopBar = mk("Frame", {
    Name = "TitleBar", Size = UDim2.new(1, 0, 0, 20), BackgroundColor3 = IG.Title,
    BorderSizePixel = 0, Active = true
}, MainFrame)
label(TopBar, "v", UDim2.new(0, 14, 1, 0), UDim2.new(0, 5, 0, 0), IG.Text, nil, 10)
label(TopBar, "DUMPER v2.7", UDim2.new(1, -90, 1, 0), UDim2.new(0, 18, 0, 0), IG.Text, nil, 11)
local ModeBadge = label(TopBar, "Single-File", UDim2.new(0, 72, 1, 0), UDim2.new(1, -76, 0, 0),
    Color3.fromRGB(200, 220, 255), Enum.TextXAlignment.Right, 10)

local InfoBar = mk("Frame", {
    Size = UDim2.new(1, 0, 0, 17), Position = UDim2.new(0, 0, 0, 20),
    BackgroundColor3 = IG.MenuBar, BorderSizePixel = 0
}, MainFrame)
mk("Frame", {
    Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -1),
    BackgroundColor3 = IG.Border, BorderSizePixel = 0
}, InfoBar)

local PlaceNameText = tostring(game.Name)
local PlaceInfo = nil
local PlaceNameLabel = label(InfoBar, "Place: " .. PlaceNameText, UDim2.new(0.6, -6, 1, 0), UDim2.new(0, 5, 0, 0), IG.Text, nil, 10)
label(InfoBar, "ID: " .. tostring(game.PlaceId), UDim2.new(0.4, -5, 1, 0), UDim2.new(0.6, 0, 0, 0),
    IG.Dim, Enum.TextXAlignment.Right, 10)

task.spawn(function()
    local ok, info = pcall(function() return Market:GetProductInfo(game.PlaceId) end)
    if ok and type(info) == "table" and info.Name then
        PlaceInfo = info
        PlaceNameText = info.Name
        PlaceNameLabel.Text = "Place: " .. info.Name
    end
end)

local Scroll = mk("ScrollingFrame", {
    Size = UDim2.new(1, -6, 1, -64), Position = UDim2.new(0, 3, 0, 40), BackgroundTransparency = 1,
    BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = IG.Check,
    ScrollingDirection = Enum.ScrollingDirection.Y, CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, MainFrame)
mk("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 1) }, Scroll)
mk("UIPadding", {
    PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 6),
    PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 5)
}, Scroll)

local BottomBar = mk("Frame", {
    Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 1, -24),
    BackgroundColor3 = IG.MenuBar, BorderSizePixel = 0
}, MainFrame)
mk("Frame", { Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = IG.Border, BorderSizePixel = 0 }, BottomBar)
local StatusLabel = label(BottomBar, "Ready", UDim2.new(1, -86, 1, 0), UDim2.new(0, 5, 0, 0), IG.Dim, nil, 10)
local StartBtn = mk("TextButton", {
    Size = UDim2.fromOffset(78, 18), Position = UDim2.new(1, -82, 0.5, -9), BackgroundColor3 = IG.Button,
    BorderSizePixel = 0, AutoButtonColor = false, Text = "Start Dump", TextColor3 = IG.Text,
    Font = IG.Font, TextSize = 11,
}, BottomBar)
stroke(StartBtn)

-- ===== ImGui widgets =====
local order, section = 0, nil
local function nextOrder() order += 1 return order end
local function reg(x) if section then table.insert(section, x) end end

local function header(title)
    local btn = mk("TextButton", {
        Size = UDim2.new(1, 0, 0, 19), BackgroundColor3 = IG.Header,
        BorderSizePixel = 0, AutoButtonColor = false, Text = "", LayoutOrder = nextOrder()
    }, Scroll)
    local arrow = label(btn, "v", UDim2.new(0, 14, 1, 0), UDim2.new(0, 4, 0, 0), IG.Text, nil, 10)
    label(btn, title, UDim2.new(1, -20, 1, 0), UDim2.new(0, 18, 0, 0), IG.Text, nil, 11)
    local items, open = {}, true
    section = items
    btn.Activated:Connect(function()
        open = not open
        arrow.Text = open and "v" or ">"
        btn.BackgroundColor3 = open and IG.Header or IG.HeaderOff
        for _, it in ipairs(items) do it.Visible = open end
    end)
end

local function toggle(text, tbl, key, cb)
    local row = mk("TextButton", {
        Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, Text = "",
        AutoButtonColor = false, LayoutOrder = nextOrder()
    }, Scroll)
    reg(row)
    local box = mk("Frame", {
        Size = UDim2.fromOffset(13, 13), Position = UDim2.new(0, 3, 0.5, -6),
        BackgroundColor3 = IG.FrameBg, BorderSizePixel = 0
    }, row)
    stroke(box)
    local mark = mk("Frame", {
        Size = UDim2.fromOffset(7, 7), Position = UDim2.fromOffset(3, 3),
        BackgroundColor3 = IG.Check, BorderSizePixel = 0, Visible = tbl[key] == true
    }, box)
    label(row, text, UDim2.new(1, -22, 1, 0), UDim2.new(0, 21, 0, 0), IG.Text, nil, 11)
    row.Activated:Connect(function()
        local v = not tbl[key]
        tbl[key] = v
        if cb then
            local r = cb(v)
            if r ~= nil then tbl[key] = r end
        end
        mark.Visible = tbl[key] == true
    end)
end

local function cycle(text, initial, onClick)
    local row = mk("Frame", {
        Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1,
        LayoutOrder = nextOrder()
    }, Scroll)
    reg(row)
    local combo = mk("TextButton", {
        Size = UDim2.fromOffset(58, 15), Position = UDim2.new(0, 3, 0.5, -7),
        BackgroundColor3 = IG.FrameBg, BorderSizePixel = 0, AutoButtonColor = false,
        Text = tostring(initial) .. " v", TextColor3 = IG.Text, Font = IG.Font, TextSize = 10
    }, row)
    stroke(combo)
    label(row, text, UDim2.new(1, -66, 1, 0), UDim2.new(0, 65, 0, 0), IG.Text, nil, 11)
    combo.Activated:Connect(function()
        combo.BackgroundColor3 = IG.ButtonActive
        combo.Text = tostring(onClick()) .. " v"
        task.delay(0.12, function() combo.BackgroundColor3 = IG.FrameBg end)
    end)
end

local function stepper(text, initial, onStep)
    local row = mk("Frame", {
        Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1,
        LayoutOrder = nextOrder()
    }, Scroll)
    reg(row)
    local vf = mk("Frame", {
        Size = UDim2.fromOffset(42, 15), Position = UDim2.new(0, 3, 0.5, -7),
        BackgroundColor3 = IG.FrameBg, BorderSizePixel = 0
    }, row)
    stroke(vf)
    local val = label(vf, tostring(initial), UDim2.new(1, 0, 1, 0), nil, IG.Text, Enum.TextXAlignment.Center, 10)
    for i, sym in ipairs({ "-", "+" }) do
        local b = mk("TextButton", {
            Size = UDim2.fromOffset(16, 15), Position = UDim2.new(0, 47 + (i - 1) * 18, 0.5, -7),
            BackgroundColor3 = IG.Button, BorderSizePixel = 0, AutoButtonColor = false, Text = sym,
            TextColor3 = IG.Text, Font = IG.Font, TextSize = 11
        }, row)
        stroke(b)
        b.Activated:Connect(function() val.Text = tostring(onStep(i == 1 and -1 or 1)) end)
    end
    label(row, text, UDim2.new(1, -86, 1, 0), UDim2.new(0, 85, 0, 0), IG.Text, nil, 11)
end

local function makeDraggable(handle, target, scaled)
    local st = { moved = false }
    local dragging, dStart, sPos = false, nil, nil
    handle.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging, st.moved = true, false
            dStart, sPos = i.Position, target.Position
            i.Changed:Connect(function()
                if i.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    UIS.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
            or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dStart
            if d.Magnitude > 6 then st.moved = true end
            local sc = scaled and MainScale.Scale or 1
            target.Position = UDim2.new(sPos.X.Scale, sPos.X.Offset + d.X / sc,
                sPos.Y.Scale, sPos.Y.Offset + d.Y / sc)
        end
    end)
    return st
end
makeDraggable(TopBar, MainFrame, true)
local floatDrag = makeDraggable(FloatBtn, FloatBtn, false)
FloatBtn.Activated:Connect(function()
    if floatDrag.moved then return end
    MainFrame.Visible = not MainFrame.Visible
end)

-- ==========================================
-- 4. XD ENGINE
-- ==========================================
local XD = {
    LIM = { depth = 4, items = 40, str = 160 }, NODE_CAP = 2000, nodes = 0,
    RS_CAP = 6000, ATTR_CAP = 1500, MOD_CAP = 150, NIL_CAP = 400,
    LIMITS = { prompts = 800, clicks = 400, spawns = 200, mobs = 300, top = 80, classes = 30, player = 600 },
    genv = genv, busy = false, hold = 0, uiCount = 0,
    UI_SKIP = { Chat = true, TouchGui = true, Freecam = true, BubbleChat = true },
    NOISE = {
        "BasePart", "Attachment", "JointInstance", "Constraint", "WeldConstraint", "DataModelMesh",
        "FaceInstance", "SurfaceAppearance", "ParticleEmitter", "Light", "Beam", "Trail", "Highlight",
        "CharacterAppearance", "Humanoid", "Animator"
    },
    SERVICE_PROPS = {
        Lighting = {
            "Ambient", "OutdoorAmbient", "Brightness", "ClockTime", "TimeOfDay", "FogStart", "FogEnd",
            "FogColor", "GlobalShadows", "ExposureCompensation"
        },
        SoundService = { "AmbientReverb", "DistanceFactor", "DopplerScale", "RolloffScale" },
        Workspace = { "Gravity", "FallenPartsDestroyHeight", "StreamingEnabled", "StreamingMinRadius" },
        Players = { "RespawnTime", "CharacterAutoLoads" },
        StarterPlayer = {
            "CharacterWalkSpeed", "CharacterJumpPower", "CharacterJumpHeight",
            "CharacterUseJumpPower", "CameraMode", "CameraMaxZoomDistance"
        },
    },
    CLASS_PROPS = {
        Team = { "TeamColor", "AutoAssignable" },
        Sound = { "SoundId", "Volume", "Looped", "PlaybackSpeed" },
        Atmosphere = { "Density", "Offset", "Color", "Decay", "Glare", "Haze" },
        Sky = { "SkyboxBk", "SkyboxFt", "CelestialBodiesShown", "StarCount" },
        BloomEffect = { "Enabled", "Intensity", "Size", "Threshold" },
        ColorCorrectionEffect = { "Enabled", "Brightness", "Contrast", "Saturation", "TintColor" },
        SunRaysEffect = { "Enabled", "Intensity", "Spread" },
        DepthOfFieldEffect = { "Enabled", "FarIntensity", "FocusDistance", "InFocusRadius" },
    },
    ATTR_ROOTS = {
        "Workspace", "ReplicatedStorage", "ReplicatedFirst", "StarterGui", "StarterPlayer",
        "StarterPack", "Lighting", "Teams", "SoundService"
    },
    PROMPT_PROPS = {
        "ActionText", "ObjectText", "HoldDuration", "MaxActivationDistance",
        "RequiresLineOfSight", "Enabled", "KeyboardKeyCode"
    },
    FUNC_LIST = {
        "writefile", "readfile", "isfile", "isfolder", "makefolder", "listfiles", "decompile",
        "getscriptbytecode", "getscripts", "getloadedmodules", "getnilinstances", "getconnections",
        "getgc", "hookmetamethod", "getnamecallmethod", "checkcaller", "newcclosure", "iscclosure",
        "getrawmetatable", "setclipboard", "gethui", "saveinstance", "request", "firesignal",
        "fireproximityprompt", "fireclickdetector", "firetouchinterest"
    },
}

XD.RL = genv.__DumperRL
if not XD.RL then
    XD.RL = { on = false, list = {}, seen = {}, per = {}, max = 500, perMax = 12 }
    genv.__DumperRL = XD.RL
end
XD.hooked = (genv.__DumperHooked == true)
Config.Extras.RemoteLog = (XD.RL.on == true)

XD.IN = genv.__DumperIN
if not XD.IN then
    XD.IN = {
        on = false, list = {}, seen = {}, per = {}, max = 500, perMax = 12, conns = {},
        listened = setmetatable({}, { __mode = "k" })
    }
    genv.__DumperIN = XD.IN
end
Config.Extras.IncomingLog = (XD.IN.on == true)

function XD.quote(s)
    if #s > XD.LIM.str then
        s = string.gsub(string.sub(s, 1, XD.LIM.str), "[\192-\255][\128-\191]*$", "") .. "..."
    end
    s = string.gsub(s, '[%c"\\]', function(c) return string.format("\\%03d", string.byte(c)) end)
    return '"' .. s .. '"'
end

function XD.ser(v, level, seen, compact)
    local t = typeof(v)
    if t == "string" then return XD.quote(v) end
    if t == "number" or t == "boolean" or t == "nil" or t == "EnumItem" then return tostring(v) end
    if t == "function" then return "<function>" end
    if t == "Vector3" then return string.format("Vector3.new(%.3g, %.3g, %.3g)", v.X, v.Y, v.Z) end
    if t == "Vector2" then return string.format("Vector2.new(%.3g, %.3g)", v.X, v.Y) end
    if t == "Color3" then
        return string.format("Color3.fromRGB(%d, %d, %d)",
            math.floor(v.R * 255 + 0.5), math.floor(v.G * 255 + 0.5), math.floor(v.B * 255 + 0.5))
    end
    if t == "Instance" then
        local ok, p = pcall(function()
            return formatLuaPath(v)
        end)
        return ok and p or "<Instance>"
    end
    if t ~= "table" then return t .. "(" .. tostring(v) .. ")" end
    if seen[v] then return "<cycle>" end
    if level >= XD.LIM.depth then return "{...}" end
    XD.nodes += 1
    if XD.nodes > XD.NODE_CAP then return "{...}" end
    seen[v] = true
    local parts, n = {}, 0
    local okLen, len = pcall(rawlen, v)
    len = (okLen and type(len) == "number") and len or 0
    local isArr = len > 0 and next(v, len) == nil
    for k, val in next, v do
        n += 1
        if n > XD.LIM.items then parts[#parts + 1] = "..." break end
        local s = XD.ser(val, level + 1, seen, compact)
        if not isArr then
            local key
            if type(k) == "string" and string.match(k, "^[%a_][%w_]*$") then
                key = k
            else
                key = "[" .. XD.ser(k, level + 1, seen, compact) .. "]"
            end
            s = key .. " = " .. s
        end
        parts[#parts + 1] = s
    end
    seen[v] = nil
    if #parts == 0 then return "{}" end
    if compact then return "{" .. table.concat(parts, ", ") .. "}" end
    local pad = string.rep("  ", level + 1)
    return "{\n" .. pad .. table.concat(parts, ",\n" .. pad) .. "\n" .. string.rep("  ", level) .. "}"
end

function XD.serialize(v, compact)
    XD.nodes = 0
    local ok, res = pcall(XD.ser, v, 0, {}, compact)
    return ok and res or "<serialize error>"
end

function XD.head(emit, title)
    local rule = string.rep("=", 60)
    emit(rule) emit(title) emit(rule)
end

function XD.get(inst, name)
    local ok, v = pcall(function() return inst[name] end)
    if ok then return v end
    return nil
end

function XD.props(inst, names)
    local out = {}
    for _, n in ipairs(names) do
        local ok, val = pcall(function() return inst[n] end)
        if ok then out[#out + 1] = n .. "=" .. XD.serialize(val, true) end
    end
    return table.concat(out, "; ")
end

function XD.attrText(inst)
    local okA, attrs = pcall(inst.GetAttributes, inst)
    local okT, tags = pcall(CS.GetTags, CS, inst)
    local parts = {}
    if okA and type(attrs) == "table" and next(attrs) ~= nil then
        parts[#parts + 1] = "Attributes=" .. XD.serialize(attrs, true)
    end
    if okT and type(tags) == "table" and #tags > 0 then
        parts[#parts + 1] = "Tags=" .. table.concat(tags, ",")
    end
    if #parts == 0 then return nil end
    return table.concat(parts, "  ")
end

function XD.oneLine(s, max)
    s = tostring(s == nil and "" or s)
    s = string.gsub(s, "%c+", " ")
    max = max or 200
    if #s > max then s = string.gsub(string.sub(s, 1, max), "[\192-\255][\128-\191]*$", "") .. "..." end
    return s
end

function XD.posOf(inst)
    local ok, v = pcall(function()
        local p = inst.Parent
        if p then
            if p:IsA("BasePart") then return p.Position end
            if p:IsA("Attachment") then return p.WorldPosition end
            if p:IsA("Model") then return p:GetPivot().Position end
        end
        if inst:IsA("BasePart") then return inst.Position end
        if inst:IsA("Model") then return inst:GetPivot().Position end
        return nil
    end)
    if ok and typeof(v) == "Vector3" then
        return string.format("(%d, %d, %d)", math.floor(v.X + 0.5), math.floor(v.Y + 0.5), math.floor(v.Z + 0.5))
    end
    return "-"
end

function XD.hasFunc(name)
    local ok, v = pcall(function()
        local g = genv[name]
        if g ~= nil then return g end
        return getfenv()[name]
    end)
    return ok and type(v) == "function"
end

function XD.mapName(raw)
    local s = tostring(raw or "")
    s = string.gsub(s, "[\128-\255]", "")
    s = string.gsub(s, "[^%w%.%-%+]+", "_")
    s = string.gsub(s, "^[_%.]+", "")
    s = string.gsub(s, "[_%.]+$", "")
    if #s > 60 then s = string.gsub(string.sub(s, 1, 60), "[_%.]+$", "") end
    if s == "" then s = "Place_" .. tostring(game.PlaceId) end
    return s
end

-- ----- [5a] -----
function XD.services(emit)
    XD.head(emit, "[5a] SERVICE PROPERTIES / ATTRIBUTES / TAGS")
    for _, name in ipairs({ "Lighting", "SoundService", "Teams", "Workspace", "Players", "StarterPlayer" }) do
        local okS, svc = pcall(game.GetService, game, name)
        if okS and svc then
            emit(string.format("== %s  %s", name, XD.props(svc, XD.SERVICE_PROPS[name] or {})))
            if name == "Lighting" or name == "SoundService" or name == "Teams" then
                for _, ch in ipairs(svc:GetChildren()) do
                    emit(string.format("  - %s [%s] %s", ch.Name, ch.ClassName,
                        XD.props(ch, XD.CLASS_PROPS[ch.ClassName] or {})))
                end
            end
        end
    end
    emit("== INSTANCES WITH ATTRIBUTES / TAGS")
    local found = 0
    local g = XD.attrText(game)
    if g then emit("game  " .. g) end
    for _, rn in ipairs(XD.ATTR_ROOTS) do
        local on = Config.Services[rn]
        local okR, root = pcall(game.GetService, game, rn)
        if okR and root and (rn == "Lighting" or on == nil or on) then
            local list = root:GetDescendants()
            table.insert(list, 1, root)
            for i, inst in ipairs(list) do
                if i % 500 == 0 then task.wait() end
                local ok, txt = pcall(XD.attrText, inst)
                if ok and txt then
                    found += 1
                    if found > XD.ATTR_CAP then
                        emit("(stopped at " .. XD.ATTR_CAP .. " entries)")
                        return
                    end
                    emit(string.format("%s [%s]  %s", formatLuaPath(inst), inst.ClassName, txt))
                end
            end
        end
    end
    emit(string.format("(%d instances with Attributes/Tags)", found))
end

-- ----- [5b] -----
function XD.links(btn)
    if typeof(getconnections) ~= "function" then return nil end
    local isc = (typeof(iscclosure) == "function") and iscclosure or nil
    local found = {}
    for _, sig in ipairs({ "Activated", "MouseButton1Click", "MouseButton1Down" }) do
        local okS, signal = pcall(function() return btn[sig] end)
        if okS and signal then
            local ok, conns = pcall(getconnections, signal)
            if ok and type(conns) == "table" then
                for _, c in ipairs(conns) do
                    local okF, fn = pcall(function() return c.Function end)
                    if okF and type(fn) == "function" and not (isc and isc(fn)) then
                        local okE, env = pcall(getfenv, fn)
                        local s = okE and type(env) == "table" and rawget(env, "script")
                        if typeof(s) == "Instance" then found[formatLuaPath(s)] = true end
                    end
                end
            end
        end
    end
    local list = {}
    for p in next, found do list[#list + 1] = p end
    table.sort(list)
    return #list > 0 and table.concat(list, ", ") or nil
end

function XD.gui(root, emit, depth, live)
    if depth > 12 then return end
    for _, ch in ipairs(root:GetChildren()) do
        local skip = (ch == ScreenGui)
        if not skip and live and depth == 1 and Config.Advanced.SkipDefaultScripts then
            skip = (XD.UI_SKIP[ch.Name] == true) or (IgnoredNames[ch.Name] == true)
        end
        if not skip and Config.Extras.UIHideDecor and ch:IsA("UIComponent") then skip = true end
        if not skip then
            XD.uiCount += 1
            if XD.uiCount % 300 == 0 then task.wait() end
            local info = {}
            if ch:IsA("GuiObject") then
                info[#info + 1] = "Visible=" .. tostring(ch.Visible)
            elseif ch:IsA("LayerCollector") then
                info[#info + 1] = "Enabled=" .. tostring(ch.Enabled)
            end
            if ch:IsA("TextLabel") or ch:IsA("TextButton") or ch:IsA("TextBox") then
                info[#info + 1] = "Text=" .. XD.quote(ch.Text)
            elseif ch:IsA("ImageLabel") or ch:IsA("ImageButton") then
                info[#info + 1] = "Image=" .. XD.quote(ch.Image)
            end
            if Config.Extras.UIConnections and ch:IsA("GuiButton") then
                local l = XD.links(ch)
                if l then info[#info + 1] = "Scripts=" .. l end
            end
            emit(string.format("%s%s [%s] %s", string.rep("  ", depth), ch.Name, ch.ClassName,
                table.concat(info, " ")))
            XD.gui(ch, emit, depth + 1, live)
        end
    end
end

function XD.ui(emit)
    XD.uiCount = 0
    XD.head(emit, "[5b] UI HIERARCHY  (Scripts= means a script connected to that button)")
    emit("== StarterGui")
    XD.gui(game:GetService("StarterGui"), emit, 1, false)
    local pg = LP:FindFirstChildOfClass("PlayerGui")
    if pg then
        emit("== PlayerGui (live)")
        XD.gui(pg, emit, 1, true)
    end
end

-- ----- [5c] -----
function XD.isNoise(inst)
    for _, cn in ipairs(XD.NOISE) do
        if inst:IsA(cn) then return true end
    end
    return false
end

function XD.tryRequire(mod, timeout)
    local done, ok, res = false, false, nil
    task.spawn(function()
        ok, res = pcall(require, mod)
        done = true
    end)
    local t0 = os.clock()
    while not done and os.clock() - t0 < timeout do task.wait() end
    return done and ok, res
end

function XD.rs(emit)
    XD.head(emit, "[5c] REPLICATEDSTORAGE FULL DUMP")
    local loaded, hasLoaded = {}, false
    if typeof(getloadedmodules) == "function" then
        local ok, mods = pcall(getloadedmodules)
        if ok and type(mods) == "table" then
            hasLoaded = true
            for _, m in ipairs(mods) do loaded[m] = true end
        end
    end
    if not hasLoaded and not Config.Extras.RSForceRequire then
        emit("(no getloadedmodules: turn on 'Force require() unloaded' to read ModuleScript values)")
    end
    local shown, skipped = 0, 0
    for i, inst in ipairs(game:GetService("ReplicatedStorage"):GetDescendants()) do
        if i % 300 == 0 then task.wait() end
        local at = XD.attrText(inst)
        if XD.isNoise(inst) and not at then
            skipped += 1
        else
            shown += 1
            if shown > XD.RS_CAP then emit("(stopped at " .. XD.RS_CAP .. " entries)") break end
            local line = string.format("%s [%s]", formatLuaPath(inst), inst.ClassName)
            if inst:IsA("ValueBase") then line ..= " = " .. XD.serialize(inst.Value, true) end
            if at then line ..= "  " .. at end
            local isMod = inst:IsA("ModuleScript")
            local canReq = isMod and (loaded[inst] or Config.Extras.RSForceRequire)
            if isMod and not canReq then line ..= "  (not loaded yet: skipped)" end
            emit(line)
            if canReq then
                local ok, res = XD.tryRequire(inst, 3)
                emit(ok and ("return " .. XD.serialize(res)) or "  (require failed or timed out)")
            end
        end
    end
    if skipped > 0 then emit(string.format("(%d Part/Mesh/Joint-type instances hidden)", skipped)) end
end

-- ----- [5d] Outgoing remote logger -----
function XD.logCall(remote, method, args)
    if typeof(remote) ~= "Instance" then return end
    local RL = XD.RL
    local rkey = formatLuaPath(remote) .. ":" .. method
    local a = {}
    for i = 1, args.n do a[i] = XD.serialize(args[i], true) end
    local key = rkey .. "(" .. table.concat(a, ", ") .. ")"
    local e = RL.seen[key]
    if e then e.count += 1 return end
    local p = RL.per[rkey]
    if not p then p = { n = 0, extra = 0 } RL.per[rkey] = p end
    if p.n >= RL.perMax or #RL.list >= RL.max then p.extra += 1 return end
    p.n += 1
    e = { key = key, count = 1 }
    RL.seen[key] = e
    RL.list[#RL.list + 1] = e
end

function XD.installHook()
    if XD.hooked then return true end
    if typeof(hookmetamethod) ~= "function" or typeof(getnamecallmethod) ~= "function"
        or typeof(checkcaller) ~= "function" or typeof(newcclosure) ~= "function" then
        return false
    end
    local RL, logCall = XD.RL, XD.logCall
    local old
    local ok = pcall(function()
        old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
            local method = getnamecallmethod()
            if RL.on and (method == "FireServer" or method == "InvokeServer") and not checkcaller() then
                local args = table.pack(...)
                task.defer(function() pcall(logCall, self, method, args) end)
            end
            return old(self, ...)
        end))
    end)
    if ok and old then
        XD.hooked = true
        genv.__DumperHooked = true
        return true
    end
    return false
end

function XD.poll()
    if XD.polling then return end
    XD.polling = true
    task.spawn(function()
        while (XD.RL.on or XD.IN.on) and ScreenGui.Parent do
            if not XD.busy and os.clock() > XD.hold then
                StatusLabel.Text = string.format("Log: out %d | in %d", #XD.RL.list, #XD.IN.list)
            end
            task.wait(1)
        end
        XD.polling = false
    end)
end

function XD.setLogger(on)
    if on and not XD.installHook() then
        XD.RL.on = false
        StatusLabel.Text = "Logger: unsupported"
        return false
    end
    XD.RL.on = on
    if on then XD.poll() else StatusLabel.Text = "Logger OFF" end
    return on
end

function XD.remotes(emit)
    local RL = XD.RL
    XD.head(emit, string.format("[5d] REMOTE CALL LOG - Client -> Server (%d unique)", #RL.list))
    emit(string.format("(logger %s | hook %s | limit %d arg-sets per remote, %d total | xN = same call N times)",
        RL.on and "ON" or "OFF", XD.hooked and "ready" or "NOT available", RL.perMax, RL.max))
    for i, e in ipairs(RL.list) do emit(string.format("#%d x%d  %s", i, e.count, e.key)) end
    for rkey, p in next, RL.per do
        if p.extra > 0 then emit(string.format("(+%d more calls of %s not listed)", p.extra, rkey)) end
    end
end

-- ----- [5e] Incoming remote logger -----
function XD.inLog(remote, args)
    local IN = XD.IN
    if not IN.on or typeof(remote) ~= "Instance" then return end
    local rkey = formatLuaPath(remote) .. ":OnClientEvent"
    local p = IN.per[rkey]
    if not p then p = { n = 0, extra = 0, calls = 0 } IN.per[rkey] = p end
    p.calls += 1
    if p.calls > 3000 then p.extra += 1 return end
    local a = {}
    for i = 1, args.n do a[i] = XD.serialize(args[i], true) end
    local key = rkey .. "(" .. table.concat(a, ", ") .. ")"
    local e = IN.seen[key]
    if e then e.count += 1 return end
    if p.n >= IN.perMax or #IN.list >= IN.max then p.extra += 1 return end
    p.n += 1
    e = { key = key, count = 1 }
    IN.seen[key] = e
    IN.list[#IN.list + 1] = e
end

function XD.inConnect(remote)
    local IN = XD.IN
    if IN.listened[remote] then return end
    IN.listened[remote] = true
    local ok, conn = pcall(function()
        return remote.OnClientEvent:Connect(function(...)
            if not IN.on then return end
            local args = table.pack(...)
            task.defer(function() pcall(XD.inLog, remote, args) end)
        end)
    end)
    if ok and conn then IN.conns[#IN.conns + 1] = conn end
end

local IN_SERVICES = { "ReplicatedStorage", "ReplicatedFirst", "Workspace", "Players", "StarterGui" }

function XD.inScan()
    local IN = XD.IN
    for _, rn in ipairs(IN_SERVICES) do
        local okR, root = pcall(game.GetService, game, rn)
        if okR and root then
            local okD, list = pcall(root.GetDescendants, root)
            if okD and type(list) == "table" then
                for i, inst in ipairs(list) do
                    if not IN.on then return end
                    if inst.ClassName == "RemoteEvent" and not isCoreDescendant(inst) then
                        XD.inConnect(inst)
                    end
                    if i % 2000 == 0 then task.wait() end
                end
            end
        end
    end
end

function XD.inStop()
    local IN = XD.IN
    IN.on = false
    for _, c in ipairs(IN.conns) do pcall(function() c:Disconnect() end) end
    table.clear(IN.conns)
    table.clear(IN.listened)
end

function XD.inStart()
    local IN = XD.IN
    XD.inStop()
    IN.on = true
    for _, rn in ipairs(IN_SERVICES) do
        local okS, svc = pcall(game.GetService, game, rn)
        if okS and svc then
            IN.conns[#IN.conns + 1] = svc.DescendantAdded:Connect(function(inst)
                if IN.on and inst.ClassName == "RemoteEvent" and not isCoreDescendant(inst) then
                    XD.inConnect(inst)
                end
            end)
        end
    end
    task.spawn(XD.inScan)
end

function XD.setIncoming(on)
    if on then
        XD.inStart()
        XD.poll()
    else
        XD.inStop()
        StatusLabel.Text = "Incoming log OFF"
    end
    return on
end

function XD.incoming(emit)
    local IN = XD.IN
    XD.head(emit, string.format("[5e] INCOMING REMOTE LOG - Server -> Client (%d unique)", #IN.list))
    local n = 0
    for _ in next, IN.listened do n += 1 end
    emit(string.format("(logger %s | %d RemoteEvent listened | limit %d arg-sets per remote, %d total)",
        IN.on and "ON" or "OFF", n, IN.perMax, IN.max))
    for i, e in ipairs(IN.list) do emit(string.format("#%d x%d  %s", i, e.count, e.key)) end
    for rkey, p in next, IN.per do
        if p.extra > 0 then emit(string.format("(+%d more calls of %s not listed)", p.extra, rkey)) end
    end
end

-- ----- [5f] Game / Server / Executor -----
function XD.gameInfo(emit)
    XD.head(emit, "[5f] GAME / SERVER / EXECUTOR INFO")
    local info = PlaceInfo
    if type(info) ~= "table" then
        local ok, res = pcall(function() return Market:GetProductInfo(game.PlaceId) end)
        if ok and type(res) == "table" then info = res end
    end
    emit("Place Name     : " .. XD.oneLine(PlaceNameText, 120))
    emit("Place Id       : " .. tostring(game.PlaceId))
    emit("Universe Id    : " .. tostring(XD.get(game, "GameId")))
    emit("Place Version  : " .. tostring(XD.get(game, "PlaceVersion")))
    emit("Job Id         : " .. tostring(game.JobId))
    if type(info) == "table" then
        local cr = type(info.Creator) == "table" and info.Creator or {}
        emit(string.format("Creator        : %s (%s, id %s)", XD.oneLine(cr.Name, 60),
            tostring(cr.CreatorType), tostring(cr.CreatorTargetId or cr.Id)))
        emit("Created        : " .. tostring(info.Created))
        emit("Updated        : " .. tostring(info.Updated))
        emit("Description    : " .. XD.oneLine(info.Description, 400))
    else
        emit("(GetProductInfo unavailable)")
    end
    emit(string.format("Players        : %d / %s", #Players:GetPlayers(), tostring(XD.get(Players, "MaxPlayers"))))
    local priv = tostring(XD.get(game, "PrivateServerId") or "")
    emit("Server Type    : " .. (priv ~= "" and "Private / VIP" or "Public"))
    emit(string.format("Input          : Touch=%s Keyboard=%s Gamepad=%s", tostring(UIS.TouchEnabled),
        tostring(UIS.KeyboardEnabled), tostring(UIS.GamepadEnabled)))
    local exName, exVer = "unknown", ""
    if typeof(identifyexecutor) == "function" then
        local ok, n, v = pcall(identifyexecutor)
        if ok then exName = tostring(n) exVer = tostring(v or "") end
    elseif typeof(getexecutorname) == "function" then
        local ok, n = pcall(getexecutorname)
        if ok then exName = tostring(n) end
    end
    emit("Executor       : " .. exName .. (exVer ~= "" and (" " .. exVer) or ""))
    local caps = {}
    for _, name in ipairs(XD.FUNC_LIST) do caps[#caps + 1] = name .. "=" .. (XD.hasFunc(name) and "Y" or "N") end
    emit("Executor functions (Y = available):")
    for i = 1, #caps, 4 do emit("  " .. table.concat(caps, "  ", i, math.min(i + 3, #caps))) end
end

-- ----- [5g] Local player -----
function XD.player(emit)
    XD.head(emit, "[5g] LOCAL PLAYER DATA (account name hidden as LocalPlayer)")
    local team = XD.get(LP, "Team")
    emit(string.format("Team: %s | Neutral: %s", team and XD.oneLine(XD.get(team, "Name"), 60) or "none",
        tostring(XD.get(LP, "Neutral"))))
    local pa = XD.attrText(LP)
    if pa then emit("LocalPlayer  " .. pa) end

    local function line(inst)
        local s = string.format("%s [%s]", formatLuaPath(inst), inst.ClassName)
        if inst:IsA("ValueBase") then s ..= " = " .. XD.serialize(inst.Value, true) end
        local a = XD.attrText(inst)
        if a then s ..= "  " .. a end
        emit(s)
    end

    emit("== VALUES / FOLDERS UNDER LocalPlayer (leaderstats, Data, ...)")
    local skip = { PlayerGui = true, PlayerScripts = true, Backpack = true, StarterGear = true }
    local count, cap, stopped = 0, XD.LIMITS.player, false
    for _, ch in ipairs(LP:GetChildren()) do
        if stopped then break end
        if not skip[ch.ClassName] then
            local list = ch:GetDescendants()
            table.insert(list, 1, ch)
            for i, inst in ipairs(list) do
                count += 1
                if count > cap then emit("(stopped at " .. cap .. " entries)") stopped = true break end
                pcall(line, inst)
                if i % 300 == 0 then task.wait() end
            end
        end
    end
    if count == 0 then emit("(none)") end

    local char = XD.get(LP, "Character")
    emit("== BACKPACK / EQUIPPED TOOLS")
    local tools = {}
    local bp = LP:FindFirstChildOfClass("Backpack")
    if bp then for _, t in ipairs(bp:GetChildren()) do tools[#tools + 1] = t end end
    if char then
        for _, t in ipairs(char:GetChildren()) do
            if t:IsA("Tool") then tools[#tools + 1] = t end
        end
    end
    if #tools == 0 then emit("(none)") end
    for _, t in ipairs(tools) do
        local extra = t:IsA("Tool") and XD.props(t, { "ToolTip", "CanBeDropped", "RequiresHandle" }) or ""
        local a = XD.attrText(t)
        emit(string.format("%s [%s] %s%s", XD.oneLine(t.Name, 60), t.ClassName, extra, a and ("  " .. a) or ""))
    end

    emit("== CHARACTER")
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            emit("Humanoid  " .. XD.props(hum, {
                "Health", "MaxHealth", "WalkSpeed", "JumpPower", "JumpHeight",
                "UseJumpPower", "HipHeight", "RigType"
            }))
            local ha = XD.attrText(hum)
            if ha then emit("Humanoid  " .. ha) end
        end
        local ca = XD.attrText(char)
        if ca then emit("Character  " .. ca) end
        for _, c in ipairs(char:GetChildren()) do
            if c:IsA("ValueBase") or c:IsA("Folder") or c:IsA("Configuration") then pcall(line, c) end
        end
    else
        emit("(no character yet)")
    end
end

-- ----- [5h] [5i] [5j] Workspace scan -----
function XD.world(emit)
    local E = Config.Extras
    if not Config.Services.Workspace then
        XD.head(emit, "[5h] WORKSPACE SCAN")
        emit("(skipped: turn on Workspace in Services to scan it)")
        return
    end
    local L = XD.LIMITS
    local census, topList = {}, {}
    local prompts, clicks, spawns = {}, {}, {}
    local more = { prompts = 0, clicks = 0, spawns = 0, mobs = 0 }
    local mobs, mobOrder = {}, {}
    local total, since = 0, 0

    local function visit(inst)
        total += 1
        local cn = inst.ClassName
        census[cn] = (census[cn] or 0) + 1
        if cn == "ProximityPrompt" then
            if #prompts < L.prompts then
                prompts[#prompts + 1] = string.format("%s  Pos=%s  %s", formatLuaPath(inst), XD.posOf(inst),
                    XD.props(inst, XD.PROMPT_PROPS))
            else more.prompts += 1 end
        elseif cn == "ClickDetector" then
            if #clicks < L.clicks then
                clicks[#clicks + 1] = string.format("%s  Pos=%s  %s", formatLuaPath(inst), XD.posOf(inst),
                    XD.props(inst, { "MaxActivationDistance" }))
            else more.clicks += 1 end
        elseif cn == "SpawnLocation" then
            if #spawns < L.spawns then
                spawns[#spawns + 1] = string.format("%s  Pos=%s  %s", formatLuaPath(inst), XD.posOf(inst),
                    XD.props(inst, { "Neutral", "TeamColor", "Enabled", "Duration" }))
            else more.spawns += 1 end
        elseif cn == "Humanoid" then
            local mdl = inst.Parent
            if mdl and mdl:IsA("Model") and not Players:GetPlayerFromCharacter(mdl) then
                local g = mobs[mdl.Name]
                if g then
                    g.count += 1
                elseif #mobOrder < L.mobs then
                    mobs[mdl.Name] = {
                        count = 1, ex = formatLuaPath(mdl), pos = XD.posOf(inst),
                        stats = XD.props(inst, { "Health", "MaxHealth", "WalkSpeed" })
                    }
                    mobOrder[#mobOrder + 1] = mdl.Name
                else more.mobs += 1 end
            end
        end
    end

    for _, c in ipairs(WS:GetChildren()) do
        local okD, list = pcall(c.GetDescendants, c)
        if not okD or type(list) ~= "table" then list = {} end
        topList[#topList + 1] = { name = c.Name, class = c.ClassName, n = #list }
        pcall(visit, c)
        for i = 1, #list do
            pcall(visit, list[i])
            since += 1
            if since >= 1500 then
                since = 0
                StatusLabel.Text = string.format("Workspace: %d", total)
                task.wait()
            end
        end
    end

    if E.WorldOverview then
        XD.head(emit, string.format("[5h] WORKSPACE OVERVIEW (%d instances)", total))
        table.sort(topList, function(a, b)
            if a.n ~= b.n then return a.n > b.n end
            return a.name < b.name
        end)
        emit("== TOP-LEVEL CHILDREN (by descendant count)")
        for i = 1, math.min(#topList, L.top) do
            local e = topList[i]
            emit(string.format("%7d  %s [%s]", e.n, XD.oneLine(e.name, 60), e.class))
        end
        if #topList > L.top then emit(string.format("(+%d more top-level children)", #topList - L.top)) end
        local cls = {}
        for k, v in next, census do cls[#cls + 1] = { k, v } end
        table.sort(cls, function(a, b)
            if a[2] ~= b[2] then return a[2] > b[2] end
            return a[1] < b[1]
        end)
        emit("== CLASS CENSUS (top " .. L.classes .. ")")
        for i = 1, math.min(#cls, L.classes) do emit(string.format("%7d  %s", cls[i][2], cls[i][1])) end
    end

    if E.Interactables then
        XD.head(emit, string.format("[5i] INTERACTABLES (ProximityPrompt %d | ClickDetector %d | SpawnLocation %d)",
            census.ProximityPrompt or 0, census.ClickDetector or 0, census.SpawnLocation or 0))
        emit("== PROXIMITY PROMPTS")
        if #prompts == 0 then emit("(none)") end
        for _, s in ipairs(prompts) do emit(s) end
        if more.prompts > 0 then emit(string.format("(+%d more prompts not listed)", more.prompts)) end
        emit("== CLICK DETECTORS")
        if #clicks == 0 then emit("(none)") end
        for _, s in ipairs(clicks) do emit(s) end
        if more.clicks > 0 then emit(string.format("(+%d more click detectors not listed)", more.clicks)) end
        emit("== SPAWN LOCATIONS")
        if #spawns == 0 then emit("(none)") end
        for _, s in ipairs(spawns) do emit(s) end
        if more.spawns > 0 then emit(string.format("(+%d more spawn locations not listed)", more.spawns)) end
    end

    if E.NPCCensus then
        XD.head(emit, string.format("[5j] NPC / MOB CENSUS (%d groups; Humanoid models that are not players)", #mobOrder))
        table.sort(mobOrder, function(a, b)
            local ca, cb = mobs[a].count, mobs[b].count
            if ca ~= cb then return ca > cb end
            return a < b
        end)
        for _, name in ipairs(mobOrder) do
            local g = mobs[name]
            emit(string.format("x%d  %s  e.g. %s  Pos=%s  %s", g.count, XD.quote(name), g.ex, g.pos, g.stats))
        end
        if more.mobs > 0 then emit(string.format("(+%d more groups not listed)", more.mobs)) end
        if #mobOrder == 0 then emit("(none found: mobs may spawn later or be simulated on the client)") end
    end
end

-- ----- [5k] Loaded modules outside ReplicatedStorage -----
function XD.loaded(emit)
    XD.head(emit, "[5k] LOADED MODULES OUTSIDE REPLICATEDSTORAGE (return values)")
    if typeof(getloadedmodules) ~= "function" then
        emit("(getloadedmodules is not supported by this executor)")
        return
    end
    local okM, mods = pcall(getloadedmodules)
    if not okM or type(mods) ~= "table" then emit("(getloadedmodules failed)") return end
    local rs = game:GetService("ReplicatedStorage")
    local shown, skipped = 0, 0
    for i, m in ipairs(mods) do
        if i % 100 == 0 then task.wait() end
        local keep = false
        if typeof(m) == "Instance" and m.ClassName == "ModuleScript" and m.Parent ~= nil then
            keep = not isCoreDescendant(m)
                and not (Config.Extras.RSValues and m:IsDescendantOf(rs))
                and not (Config.Advanced.SkipDefaultScripts and shouldIgnore(m))
        end
        if keep then
            shown += 1
            if shown > XD.MOD_CAP then emit("(stopped at " .. XD.MOD_CAP .. " modules)") break end
            emit(string.format("%s [ModuleScript]", formatLuaPath(m)))
            local ok, res = XD.tryRequire(m, 3)
            emit(ok and ("return " .. XD.serialize(res)) or "  (require failed or timed out)")
        else
            skipped += 1
        end
    end
    emit(string.format("(%d modules shown, %d skipped)", math.min(shown, XD.MOD_CAP), skipped))
end

-- ----- Static copy check -----
function XD.isStaticCopy(inst, liveRoot, staticRoot)
    if not staticRoot then return false end
    local names, cur = {}, inst
    while cur and cur ~= liveRoot do
        table.insert(names, 1, cur.Name)
        cur = cur.Parent
    end
    if cur ~= liveRoot then return false end
    local node = staticRoot
    for _, n in ipairs(names) do
        node = node:FindFirstChild(n)
        if not node then return false end
    end
    return node.ClassName == inst.ClassName
end

-- ----- File splitter (1-10 files) -----
function XD.safeAt(L, i)
    local a = L[i]
    if type(a) ~= "string" then return false end
    if string.find(a, "^%-%- =+$") then
        local c = L[i + 2]
        return type(c) == "string" and string.find(c, "^%-%- =+$") ~= nil
    end
    if string.find(a, "^%-%- %-+$") then
        local b = L[i + 1]
        return type(b) == "string" and string.find(b, "^%-%- SCRIPT %[") ~= nil
    end
    return false
end

function XD.splitPlan(L, parts)
    local n, total = #L, 0
    for i = 1, n do total += #L[i] + 1 end
    local target = total / parts
    local cuts, acc = { 1 }, 0
    for i = 1, n do
        if i > 1 and #cuts < parts and acc >= target * #cuts and XD.safeAt(L, i) then
            cuts[#cuts + 1] = i
        end
        acc += #L[i] + 1
    end
    local ranges = {}
    for k = 1, #cuts do ranges[k] = { cuts[k], (cuts[k + 1] or (n + 1)) - 1 } end
    return ranges
end

function XD.writeSplit(L, base, ext, parts)
    parts = math.clamp(math.floor(tonumber(parts) or 1), 1, 10)
    local ranges = XD.splitPlan(L, parts)
    local N = #ranges
    local folder = "NEXUS/" .. base
    local useFolder = false
    if typeof(makefolder) == "function" then
        pcall(function()
            if typeof(isfolder) ~= "function" or not isfolder("NEXUS") then makefolder("NEXUS") end
            if typeof(isfolder) ~= "function" or not isfolder(folder) then makefolder(folder) end
        end)
        if typeof(isfolder) == "function" then
            local ok, ex = pcall(isfolder, folder)
            useFolder = ok and ex == true
        end
    end
    local names = {}
    for k = 1, N do
        local fname = (N == 1) and (base .. ext) or string.format("%s_part%02dof%02d%s", base, k, N, ext)
        names[k] = useFolder and (folder .. "/" .. fname) or ("Dump_" .. fname)
    end
    local written, allOk = {}, true
    for k = 1, N do
        local r = ranges[k]
        local head = ""
        if N > 1 then
            local idx = { "-- DUMPER PART " .. k .. "/" .. N }
            if k == 1 then
                idx[#idx + 1] = "-- ALL PARTS:"
                for j = 1, N do idx[#idx + 1] = "--   " .. names[j] end
            end
            head = table.concat(idx, "\n") .. "\n\n"
        end
        local okC, body = pcall(table.concat, L, "\n", r[1], r[2])
        local ok = okC and safeWrite(names[k], head .. body)
        body = nil
        if ok then written[#written + 1] = names[k] else allOk = false end
        task.wait()
    end
    return allOk and #written > 0, written, not useFolder
end

-- ==========================================
-- 5. Controls
-- ==========================================
header("SCRIPTS")
toggle("LocalScript", Config.Scripts, "LocalScript")
toggle("ModuleScript", Config.Scripts, "ModuleScript")
toggle("Script (Client Run)", Config.Scripts, "ClientRunScript")

header("REMOTES")
toggle("RemoteEvent", Config.Remotes, "RemoteEvent")
toggle("RemoteFunction", Config.Remotes, "RemoteFunction")
toggle("Bindables", Config.Remotes, "Bindables")

header("SERVICES")
for _, s in ipairs({
    "ReplicatedStorage", "Workspace", "StarterPlayer", "StarterGui", "StarterPack",
    "ReplicatedFirst", "Lighting"
}) do
    toggle(s, Config.Services, s)
end

header("REPORTS")
toggle("Script Index", Config.Reports, "ScriptIndex")
toggle("Hierarchy Tree", Config.Reports, "HierarchyTree")
toggle("Game Info (header)", Config.Reports, "GameInfo")
toggle("Dependency Graph", Config.ReportsAdvanced, "DependencyGraph")
toggle("Size Breakdown", Config.ReportsAdvanced, "SizeBreakdown")

header("PERFORMANCE")
toggle("Chunk Yield (no freeze)", Config.Performance, "ChunkYield")

header("ADVANCED")
toggle("Skip Default Roblox Scripts", Config.Advanced, "SkipDefaultScripts")
cycle("Output Format", Config.Advanced.OutputFormat, function()
    FormatIndex = (FormatIndex % #Formats) + 1
    Config.Advanced.OutputFormat = Formats[FormatIndex]
    return Config.Advanced.OutputFormat
end)
cycle("Split files (1 = single)", Config.Advanced.SplitParts, function()
    Config.Advanced.SplitParts = (Config.Advanced.SplitParts % 10) + 1
    ModeBadge.Text = Config.Advanced.SplitParts == 1 and "Single-File" or ("Split x" .. Config.Advanced.SplitParts)
    return Config.Advanced.SplitParts
end)
toggle("Decompile Timeout", Config.Advanced, "DecompileTimeout")
stepper("Timeout Duration (s)", Config.Advanced.TimeoutDuration, function(d)
    Config.Advanced.TimeoutDuration = math.clamp(Config.Advanced.TimeoutDuration + d * 5, 5, 120)
    return Config.Advanced.TimeoutDuration
end)
stepper("Max File Size", FileSizes[Config.Advanced.MaxFileSizeIndex], function(d)
    Config.Advanced.MaxFileSizeIndex = math.clamp(Config.Advanced.MaxFileSizeIndex + d, 1, #FileSizes)
    return FileSizes[Config.Advanced.MaxFileSizeIndex]
end)
toggle("Include Disabled Scripts", Config.Advanced, "IncludeDisabledScripts")
toggle("Dump Properties", Config.Advanced, "DumpProperties")
toggle("Detect Obfuscation", Config.Advanced, "DetectObfuscation")
toggle("Auto-copy Summary", Config.Advanced, "AutoCopySummary")

header("EXTRAS")
toggle("[5a] Service Props + Attributes", Config.Extras, "ServiceAttributes")
toggle("[5b] UI Hierarchy (GUI tree)", Config.Extras, "UIHierarchy")
toggle("    UI -> Script links", Config.Extras, "UIConnections")
toggle("    Hide UI decor", Config.Extras, "UIHideDecor")
toggle("[5c] ReplicatedStorage Values", Config.Extras, "RSValues")
toggle("    Force require() unloaded", Config.Extras, "RSForceRequire")
toggle("[5f] Game / Executor info", Config.Extras, "GameInfo")
toggle("[5g] Local Player data", Config.Extras, "PlayerData")
toggle("[5h] Workspace overview", Config.Extras, "WorldOverview")
toggle("[5i] Interactables", Config.Extras, "Interactables")
toggle("[5j] NPC / Mob census", Config.Extras, "NPCCensus")
toggle("[5k] Loaded modules", Config.Extras, "LoadedModules")
toggle("Live scripts (PlayerGui...)", Config.Extras, "LiveScripts")
toggle("Nil instances (hidden)", Config.Extras, "NilInstances")

header("REMOTE LOGGERS (turn ON before playing)")
toggle("[5d] Outgoing (Client->Server)", Config.Extras, "RemoteLog", function(v) return XD.setLogger(v) end)
toggle("[5e] Incoming (Server->Client)", Config.Extras, "IncomingLog", function(v) return XD.setIncoming(v) end)
cycle("Clear logs", "CLEAR", function()
    table.clear(XD.RL.list) table.clear(XD.RL.seen) table.clear(XD.RL.per)
    table.clear(XD.IN.list) table.clear(XD.IN.seen) table.clear(XD.IN.per)
    return "DONE"
end)

if XD.RL.on or XD.IN.on then XD.poll() end

-- ==========================================
-- 6. Result Overlay
-- ==========================================
local Overlay = mk("Frame", {
    Size = UDim2.new(1, 0, 1, -20), Position = UDim2.new(0, 0, 0, 20),
    BackgroundColor3 = IG.WindowBg, BorderSizePixel = 0, Visible = false, ZIndex = 10
}, MainFrame)
local OHead = mk("Frame", {
    Size = UDim2.new(1, 0, 0, 22), BackgroundColor3 = IG.MenuBar,
    BorderSizePixel = 0, ZIndex = 11
}, Overlay)
local OTitle = label(OHead, "DUMP SUMMARY", UDim2.new(1, -108, 1, 0), UDim2.new(0, 6, 0, 0), IG.Text, nil, 10)
OTitle.ZIndex = 11
local CopyBtn = mk("TextButton", {
    Size = UDim2.fromOffset(46, 17), Position = UDim2.new(1, -98, 0.5, -8),
    BackgroundColor3 = IG.Button, BorderSizePixel = 0, AutoButtonColor = false, Text = "Copy",
    TextColor3 = IG.Text, Font = IG.Font, TextSize = 10, ZIndex = 11
}, OHead)
stroke(CopyBtn)
local BackBtn = mk("TextButton", {
    Size = UDim2.fromOffset(46, 17), Position = UDim2.new(1, -48, 0.5, -8),
    BackgroundColor3 = IG.Button, BorderSizePixel = 0, AutoButtonColor = false, Text = "Back",
    TextColor3 = IG.Text, Font = IG.Font, TextSize = 10, ZIndex = 11
}, OHead)
stroke(BackBtn)
local OScroll = mk("ScrollingFrame", {
    Size = UDim2.new(1, -8, 1, -26), Position = UDim2.new(0, 4, 0, 24),
    BackgroundColor3 = IG.ChildBg, BorderSizePixel = 0, ScrollBarThickness = 4, CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 11
}, Overlay)
stroke(OScroll)
local OBox = mk("TextBox", {
    Size = UDim2.new(1, -8, 0, 0), Position = UDim2.new(0, 4, 0, 3),
    AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, TextEditable = false,
    ClearTextOnFocus = false, MultiLine = true, TextWrapped = true, Text = "", TextColor3 = IG.Text,
    Font = Enum.Font.Code, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 11
}, OScroll)
BackBtn.Activated:Connect(function() Overlay.Visible = false end)
CopyBtn.Activated:Connect(function()
    if copyToClipboard(OBox.Text) then
        CopyBtn.Text = "Copied"
        task.delay(1.2, function() CopyBtn.Text = "Copy" end)
    end
end)

-- ==========================================
-- 7. Dump Engine
-- ==========================================
local function isObfuscated(src)
    if not src or #src == 0 then return false end
    if string.find(src, "IronBrew", 1, true)
        or string.find(src, "MoonSec", 1, true)
        or string.find(src, "Luraph", 1, true)
        or string.find(src, "PSU", 1, true)
        or string.find(src, "AztupBrew", 1, true) then
        return true
    end
    if #src > 12000 and not string.find(src, "\n", 1, true) then
        return true
    end
    local _, hexEsc = string.gsub(src, "\\x%x%x", "")
    if hexEsc > 60 then return true end
    local _, vmLoop = string.gsub(src, "while%s+true%s+do", "")
    local _, envCalls = string.gsub(src, "getfenv%s*%(", "")
    return vmLoop >= 2 and envCalls >= 2
end

local function extractRequires(src)
    local deps, seenReq = {}, {}
    for m in string.gmatch(src or "", "require%s*(%b())") do
        local inner = string.sub(m, 2, -2)
        inner = string.match(inner, "^%s*(.-)%s*$") or inner
        if inner ~= "" and not seenReq[inner] then
            seenReq[inner] = true
            deps[#deps + 1] = inner
        end
    end
    return deps
end

local decompileBusy = false

local function getScriptContent(inst, timeoutSec)
    local ok, src = pcall(function() return inst.Source end)
    if ok and typeof(src) == "string" and #src > 0 then return src end

    if hasBytecode then
        local okB, bc = pcall(getscriptbytecode, inst)
        if okB and (bc == nil or bc == "") then
            return "-- [Empty bytecode (server-only or stripped): " .. formatLuaPath(inst) .. "]"
        end
    end

    if hasDecompile then
        if decompileBusy then
            local waitBusy = 0
            while decompileBusy and waitBusy < 3 do
                waitBusy += task.wait(0.05)
            end
            if decompileBusy then
                return "-- [Decompiler busy from previous timeout, skipped: " .. formatLuaPath(inst) .. "]"
            end
        end

        decompileBusy = true
        local result, finished = nil, false
        task.spawn(function()
            local okD, dec = pcall(decompile, inst)
            if okD and typeof(dec) == "string" and #dec > 0 then result = dec end
            finished = true
            decompileBusy = false
        end)
        local waited = 0
        local maxWait = Config.Advanced.DecompileTimeout and timeoutSec or 8
        while not finished and waited < maxWait do
            waited += task.wait(0.05)
        end
        if result then return result end
        if not finished then
            return "-- [Decompile timed out after " .. tostring(maxWait) .. "s: " .. formatLuaPath(inst) .. "]"
        end
    end
    return "-- [Source unavailable or empty: " .. formatLuaPath(inst) .. "]"
end

local function wrapComment(src)
    local lvl = 0
    while string.find(src, "]" .. string.rep("=", lvl) .. "]", 1, true) do lvl += 1 end
    local eq = string.rep("=", lvl)
    return "--[" .. eq .. "[\n" .. src .. "\n]" .. eq .. "]"
end

local function runDump()
    local t0 = os.clock()
    local E = Config.Extras
    local base = XD.mapName(PlaceNameText)
    local scripts, remotes, tree, seen, count = {}, {}, {}, {}, 0

    local function consider(inst, tag, container, staticRoot)
        if seen[inst] then return end
        seen[inst] = true
        count += 1
        if Config.Performance.ChunkYield and count % 150 == 0 then
            StatusLabel.Text = string.format("Scanning (%d)...", count)
            task.wait()
        end
        if isCoreDescendant(inst) then return end
        if Config.Advanced.SkipDefaultScripts and shouldIgnore(inst) then return end

        if tag ~= "LIVE" then
            local isRemote = (inst:IsA("RemoteEvent") and Config.Remotes.RemoteEvent)
                or (inst:IsA("RemoteFunction") and Config.Remotes.RemoteFunction)
                or ((inst:IsA("BindableEvent") or inst:IsA("BindableFunction")) and Config.Remotes.Bindables)
            if isRemote then
                local lp = formatLuaPath(inst)
                remotes[#remotes + 1] = { Name = inst.Name, ClassName = inst.ClassName, LuaPath = lp, Tag = tag }
                tree[#tree + 1] = "  |- [REMOTE] " .. inst.ClassName .. " : " .. lp .. (tag == "NIL" and " [NIL]" or "")
            end
        end

        local target = false
        if inst:IsA("LocalScript") then
            target = Config.Scripts.LocalScript
        elseif inst:IsA("ModuleScript") then
            target = Config.Scripts.ModuleScript
        elseif inst:IsA("Script") and Config.Scripts.ClientRunScript then
            local ok, rc = pcall(function() return inst.RunContext end)
            target = ok and rc == Enum.RunContext.Client
        end
        if not target then return end
        if tag == "LIVE" and XD.isStaticCopy(inst, container, staticRoot) then return end

        local disabled = false
        pcall(function() disabled = inst.Disabled end)
        if disabled and not Config.Advanced.IncludeDisabledScripts then return end

        StatusLabel.Text = "Reading: " .. inst.Name
        local src = getScriptContent(inst, Config.Advanced.TimeoutDuration)
        if #src > FileSizeBytes[Config.Advanced.MaxFileSizeIndex] then return end
        local obf = Config.Advanced.DetectObfuscation and isObfuscated(src)
        local prop = ""
        if Config.Advanced.DumpProperties then
            prop = string.format(" [Class=%s, Disabled=%s]", inst.ClassName, tostring(disabled))
        end
        local lp = formatLuaPath(inst)
        scripts[#scripts + 1] = {
            Name = inst.Name, LuaPath = lp, ClassName = inst.ClassName, Size = #src,
            Obf = obf, Prop = prop, Deps = extractRequires(src), Source = src, Tag = tag
        }
        local tagBadge = tag and (" [" .. tag .. "]") or ""
        tree[#tree + 1] = "  |- [SCRIPT] " .. inst.ClassName .. " : " .. lp .. tagBadge .. (obf and " [OBF]" or "")
    end

    local function scan(container, tag, staticRoot)
        local ok, list = pcall(container.GetDescendants, container)
        if not ok then return end
        tree[#tree + 1] = "[" .. formatLuaPath(container) .. "]"
        for _, inst in ipairs(list) do
            if not (tag == "LIVE" and inst:IsDescendantOf(ScreenGui)) then
                consider(inst, tag, container, staticRoot)
            end
        end
    end

    for _, sn in ipairs({
        "ReplicatedStorage", "Workspace", "StarterPlayer", "StarterPack", "StarterGui",
        "ReplicatedFirst", "Lighting"
    }) do
        if Config.Services[sn] then
            local ok, srv = pcall(game.GetService, game, sn)
            if ok and srv then scan(srv, nil, nil) end
        end
    end

    if E.LiveScripts then
        local sp = game:GetService("StarterPlayer")
        local lives = {
            { LP:FindFirstChildOfClass("PlayerGui"), game:GetService("StarterGui") },
            { LP:FindFirstChild("PlayerScripts"), sp:FindFirstChild("StarterPlayerScripts") },
            { LP:FindFirstChildOfClass("Backpack"), game:GetService("StarterPack") },
        }
        for _, pair in ipairs(lives) do
            if pair[1] then scan(pair[1], "LIVE", pair[2]) end
        end
    end

    if E.NilInstances and hasNilInstances then
        local okN, nils = pcall(getnilinstances)
        if okN and type(nils) == "table" then
            tree[#tree + 1] = "[NIL INSTANCES]"
            local nilSeen = 0
            for _, inst in ipairs(nils) do
                if typeof(inst) == "Instance" and inst.Parent == nil and not isCoreDescendant(inst) then
                    nilSeen += 1
                    if nilSeen > XD.NIL_CAP then break end
                    consider(inst, "NIL", nil, nil)
                    local okD, desc = pcall(inst.GetDescendants, inst)
                    if okD and type(desc) == "table" then
                        for _, ch in ipairs(desc) do
                            consider(ch, "NIL", nil, nil)
                        end
                    end
                end
            end
        end
    end

    -- ----- Assemble Output -----
    local L = {}
    local function add(s) L[#L + 1] = s end
    local function emit(str)
        for line in string.gmatch(tostring(str) .. "\n", "(.-)\n") do add("-- " .. line) end
    end
    local function addHead(title) XD.head(emit, title) end
    local function runExtra(enabled, status, fn)
        if not enabled then return end
        StatusLabel.Text = status
        local ok, err = pcall(fn, emit)
        if not ok then emit("[extra failed] " .. tostring(err)) end
        add("")
    end

    local timeIdx
    add("--[[")
    add("    SINGLE-FILE GAME DUMP (DUMPER v2.7.0)")
    if Config.Reports.GameInfo then
        add("    Place Name    : " .. XD.oneLine(PlaceNameText, 120))
        add("    Place ID      : " .. tostring(game.PlaceId))
        add("    Job ID        : " .. tostring(game.JobId))
        add("    Total Remotes : " .. #remotes)
        add("    Total Scripts : " .. #scripts)
        add("    Dump Time     : ...")
        timeIdx = #L
    end
    add("]]")
    add("")

    addHead("[1] REMOTES DUMP (" .. #remotes .. " FOUND)")
    if #remotes == 0 then add("-- No remotes found in selected services.") end
    for i, rm in ipairs(remotes) do
        local tb = rm.Tag and (" [" .. rm.Tag .. "]") or ""
        add(string.format("-- [%03d] [%s] %s%s", i, rm.ClassName, rm.LuaPath, tb))
        if rm.ClassName == "RemoteEvent" then
            add("--   Usage: " .. rm.LuaPath .. ":FireServer(...)")
        elseif rm.ClassName == "RemoteFunction" then
            add("--   Usage: " .. rm.LuaPath .. ":InvokeServer(...)")
        end
    end
    add("")

    if Config.Reports.ScriptIndex then
        addHead("[2] SCRIPT INDEX (" .. #scripts .. " FOUND)")
        for i, sc in ipairs(scripts) do
            local tb = sc.Tag and (" [" .. sc.Tag .. "]") or ""
            add(string.format("-- [%03d] [%s] %s (%d bytes)%s%s%s", i, sc.ClassName, sc.LuaPath, sc.Size, sc.Prop,
                tb, sc.Obf and " [OBFUSCATED]" or ""))
        end
        add("")
    end

    if Config.ReportsAdvanced.SizeBreakdown and #scripts > 0 then
        addHead("[3] SIZE BREAKDOWN (LARGEST FIRST)")
        local sorted = table.clone(scripts)
        table.sort(sorted, function(a, b) return a.Size > b.Size end)
        for _, sc in ipairs(sorted) do add(string.format("-- %7d bytes | %s", sc.Size, sc.LuaPath)) end
        add("")
    end

    if Config.ReportsAdvanced.DependencyGraph and #scripts > 0 then
        addHead("[4] MODULE DEPENDENCY GRAPH")
        for _, sc in ipairs(scripts) do
            if #sc.Deps > 0 then
                add("-- " .. sc.LuaPath .. " requires:")
                for _, d in ipairs(sc.Deps) do add("--    -> " .. XD.oneLine(d, 160)) end
            end
        end
        add("")
    end

    if Config.Reports.HierarchyTree then
        addHead("[5] HIERARCHY TREE")
        for _, line in ipairs(tree) do add("-- " .. line) end
        add("")
    end

    runExtra(E.ServiceAttributes, "Reading services...", XD.services)
    runExtra(E.UIHierarchy, "Reading UI...", XD.ui)
    runExtra(E.RSValues, "Reading ReplicatedStorage...", XD.rs)
    runExtra(E.RemoteLog or #XD.RL.list > 0, "Writing outgoing log...", XD.remotes)
    runExtra(E.IncomingLog or #XD.IN.list > 0, "Writing incoming log...", XD.incoming)
    runExtra(E.GameInfo, "Reading game info...", XD.gameInfo)
    runExtra(E.PlayerData, "Reading player data...", XD.player)
    runExtra(E.WorldOverview or E.Interactables or E.NPCCensus, "Scanning Workspace...", XD.world)
    runExtra(E.LoadedModules, "Reading loaded modules...", XD.loaded)

    addHead("[6] DUMPED SCRIPT SOURCES (each source is inside a long comment)")
    add("")
    local dash = "-- " .. string.rep("-", 60)
    for i, sc in ipairs(scripts) do
        local tb = sc.Tag and (" | [" .. sc.Tag .. "]") or ""
        add(dash)
        add(string.format("-- SCRIPT [%03d]: %s", i, XD.oneLine(sc.Name, 80)))
        add(string.format("-- CLASS : %s | SIZE: %d bytes%s%s", sc.ClassName, sc.Size,
            tb, sc.Obf and " | [OBFUSCATED]" or ""))
        add("-- PATH  : " .. sc.LuaPath)
        add(dash)
        add(wrapComment(sc.Source))
        add("")
        sc.Source = nil
    end

    if timeIdx then L[timeIdx] = string.format("    Dump Time     : %.2fs", os.clock() - t0) end

    StatusLabel.Text = "Writing files..."
    local ok, files, flat = XD.writeSplit(L, base, Config.Advanced.OutputFormat, Config.Advanced.SplitParts)

    if Config.Advanced.AutoCopySummary then
        if #files <= 1 then
            copyToClipboard(table.concat(L, "\n"))
        else
            copyToClipboard(table.concat(files, "\n"))
        end
    end

    local S = {
        "========================================",
        "DUMP COMPLETED",
        "========================================",
        "Files Saved   : " .. #files .. " / " .. math.clamp(Config.Advanced.SplitParts, 1, 10) .. " requested",
        "Location      : " .. (flat and "workspace/ (flat)" or ("workspace/NEXUS/" .. base .. "/")),
        "Write Status  : " .. (ok and "SUCCESS" or (hasWrite and "FAILED (some files not written)" or "FAILED (no writefile)")),
        "Total Remotes : " .. #remotes,
        "Total Scripts : " .. #scripts,
        "Out Log       : " .. #XD.RL.list .. " unique | In Log: " .. #XD.IN.list .. " unique",
        string.format("Elapsed Time  : %.2fs", os.clock() - t0),
        "",
        "--- FILES ---",
    }
    for _, f in ipairs(files) do S[#S + 1] = f end
    if #remotes > 0 then
        S[#S + 1] = ""
        S[#S + 1] = "--- REMOTES PREVIEW ---"
        for i = 1, math.min(20, #remotes) do
            S[#S + 1] = string.format("[%d] [%s] %s", i, remotes[i].ClassName, remotes[i].LuaPath)
        end
        if #remotes > 20 then S[#S + 1] = string.format("... and %d more in the file", #remotes - 20) end
    end
    local summaryText = table.concat(S, "\n")
    if #summaryText > 14000 then
        summaryText = string.sub(summaryText, 1, 14000) .. "\n... (truncated for UI display)"
    end
    OBox.Text = summaryText
    Overlay.Visible = true
    StatusLabel.Text = "Saved " .. #files .. " file(s)"

    table.clear(L)
    table.clear(scripts)
    table.clear(tree)
    table.clear(remotes)
end

local dumping = false
StartBtn.Activated:Connect(function()
    if dumping then return end
    dumping, XD.busy = true, true
    StartBtn.BackgroundColor3 = Color3.fromRGB(25, 45, 75)
    StartBtn.Text = "Dumping..."
    StatusLabel.Text = "Starting..."
    task.spawn(function()
        local ok, err = xpcall(runDump, debug.traceback)
        if not ok then
            warn("[DUMPER] " .. tostring(err))
            OBox.Text = "DUMP FAILED:\n" .. string.sub(tostring(err), 1, 12000)
            Overlay.Visible = true
            StatusLabel.Text = "Dump failed (see error)"
        end
        StartBtn.BackgroundColor3 = IG.Button
        StartBtn.Text = "Start Dump"
        XD.busy = false
        XD.hold = os.clock() + 6
        dumping = false
    end)
end)

StatusLabel.Text = "Ready"

end, function(e) return debug.traceback(tostring(e), 2) end)

if not mainOk then showFatal(mainErr) end
