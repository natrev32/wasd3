-- Nebula Hub v18.9 – Midnight Nebula Edition
-- Feature: Auto Restock Booth + Auto Claim Booth + Anti AFK
-- Authority: iPowfu | Channel: Nebula Hub

local RunService = game:GetService("RunService")
local cloneref   = (cloneref or table.clone or function(i) return i end)
local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
local HttpService = game:GetService("HttpService")
local Players     = game:GetService("Players")
local VIM         = game:GetService("VirtualInputManager")

local WindUI
do
    local ok, result = pcall(function()
        return require(game:GetService("ProjectResources"):WaitForChild("Init"))
    end)
    if ok then
        WindUI = result
    else
        local success, res = pcall(function()
            if cloneref(RunService):IsStudio() then
                return require(cloneref(ReplicatedStorage:WaitForChild("WindUI"):WaitForChild("Init")))
            else
                return loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()
            end
        end)
        if success then WindUI = res end
    end
end

if not WindUI then warn("Nebula Hub: Gagal memuat WindUI!") return end

local lp         = Players.LocalPlayer
local InviteCode = "dyt7dd55Ct"

-- =============================================
-- RARITY LIST
-- =============================================
local BLOCK_RARITIES = {
    -- Regular
    "Common","Uncommon","Rare","Epic","Legendary",
    "Mythical","Cosmic","Secret","Celestial","Divine","Infinity",
    -- Event-Exclusive
    "Radioactive","UFO","Money","Arcade","Valentines","Volcanic","Sugar Rush","Admin",
}

-- =============================================
-- SETTINGS
-- =============================================
local SETTINGS_FILE = "NebulaHub_Settings.json"
local SCAN_FILE     = "NebulaHub_ScanCache.json"

local function LoadSettings()
    local d = {
        SellType      = "Block",
        FilterRarity  = "Common",
        FilterAnomali = "All",
        StockAmount   = 100,
        StockPrice    = 100,
        RestockDelay  = 0.2,
        ClaimDelay    = 0.5,
        ClaimInterval = 3,
    }
    if isfile and isfile(SETTINGS_FILE) then
        pcall(function()
            for k,v in pairs(HttpService:JSONDecode(readfile(SETTINGS_FILE))) do d[k]=v end
        end)
    end
    return d
end

local function SaveSettings(cfg)
    pcall(function() writefile(SETTINGS_FILE, HttpService:JSONEncode(cfg)) end)
end

local function SaveScanCache(names)
    pcall(function() writefile(SCAN_FILE, HttpService:JSONEncode({ anomalis = names })) end)
end

local function LoadScanCache()
    if isfile and isfile(SCAN_FILE) then
        local ok, r = pcall(function() return HttpService:JSONDecode(readfile(SCAN_FILE)) end)
        if ok and r and r.anomalis then return r.anomalis end
    end
    return {}
end

-- =============================================
-- REMOTES
-- =============================================
local ListRemote, ClaimRemote

local function GetListRemote()
    if ListRemote then return ListRemote end
    pcall(function()
        ListRemote = ReplicatedStorage
            :WaitForChild("Shared"):WaitForChild("Remotes")
            :WaitForChild("Networking"):WaitForChild("RF/ListBoothOffering")
    end)
    return ListRemote
end

local function GetClaimRemote()
    if ClaimRemote then return ClaimRemote end
    pcall(function()
        ClaimRemote = ReplicatedStorage
            :WaitForChild("Shared"):WaitForChild("Remotes")
            :WaitForChild("Networking"):WaitForChild("RF/ClaimBooth")
    end)
    return ClaimRemote
end

-- =============================================
-- ANTI AFK
-- =============================================
local AntiAfkThread = nil

local function StartAntiAfk()
    if AntiAfkThread then return end
    AntiAfkThread = task.spawn(function()
        while AntiAfkThread do
            task.wait(60)
            pcall(function()
                -- Simulasi jump + idle untuk reset AFK timer
                local char = lp.Character
                if char then
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    if hum then hum.Jump = true end
                end
                -- Simulasi keypress W singkat via VirtualInputManager
                VIM:SendKeyEvent(true,  Enum.KeyCode.W, false, game)
                task.wait(0.1)
                VIM:SendKeyEvent(false, Enum.KeyCode.W, false, game)
            end)
        end
    end)
end

local function StopAntiAfk()
    if AntiAfkThread then
        task.cancel(AntiAfkThread)
        AntiAfkThread = nil
    end
end

-- =============================================
-- INVENTORY
-- =============================================
local function ScanInventory()
    local blocks, anomals = {}, {}
    pcall(function()
        for _, item in ipairs(lp.Backpack:GetChildren()) do
            local luckyType    = item:GetAttribute("LuckyBlockType")
            local brainrotName = item:GetAttribute("BrainrotName")
            local displayName  = item:GetAttribute("DisplayName") or item.Name
            if luckyType and luckyType ~= "" then
                table.insert(blocks, { id = item.Name, displayName = displayName, rarity = luckyType })
            elseif brainrotName and brainrotName ~= "" then
                table.insert(anomals, { id = item.Name, brainrotName = brainrotName, displayName = displayName })
            end
        end
    end)
    return blocks, anomals
end

local function GetUniqueAnomaliNames(anomals)
    local seen, list = {}, {}
    for _, item in ipairs(anomals) do
        if not seen[item.brainrotName] then
            seen[item.brainrotName] = true
            table.insert(list, item.brainrotName)
        end
    end
    table.sort(list)
    table.insert(list, 1, "All")
    return list
end

-- =============================================
-- RESTOCK HELPER
-- =============================================
local function RestockItem(item, cfg, counters)
    local remote = GetListRemote()
    if not remote then return false end
    local ok, result = pcall(function()
        return remote:InvokeServer(item.id, cfg.StockPrice, cfg.StockAmount)
    end)
    if not ok then
        counters.rejected = (counters.rejected or 0) + 1
        return false
    end
    if result == true then
        counters.restock = counters.restock + 1
        return true
    else
        counters.rejected = (counters.rejected or 0) + 1
        return false
    end
end

-- =============================================
-- CLAIM HELPERS
-- =============================================
local function GetAllBooths()
    local booths = {}
    pcall(function()
        local f = workspace:FindFirstChild("GameObjects") and workspace.GameObjects:FindFirstChild("Booths")
        if not f then return end
        for _, b in ipairs(f:GetChildren()) do table.insert(booths, b) end
    end)
    return booths
end

local function TeleportToBooth(booth)
    pcall(function()
        local hrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        local cf = booth.PrimaryPart and booth.PrimaryPart.CFrame or booth:GetPivot()
        hrp.CFrame = cf * CFrame.new(0, 5, 0)
    end)
end

local function TryClaimBooth(booth)
    local remote = GetClaimRemote()
    if not remote then return false end
    local ok, result = pcall(function() return remote:InvokeServer(booth.Name, false) end)
    if not ok then return false end
    if result == true then return true end
    if type(result) == "table" and result[1] == true then return true end
    return false
end

-- =============================================
-- BUILD UI
-- =============================================
local function BuildUI()
    local cfg       = LoadSettings()
    local scanCache = LoadScanCache()

    local anomaliValues = #scanCache > 0 and scanCache or { "All" }
    if anomaliValues[1] ~= "All" then table.insert(anomaliValues, 1, "All") end
    local valid = false
    for _, v in ipairs(anomaliValues) do if v == cfg.FilterAnomali then valid = true break end end
    if not valid then cfg.FilterAnomali = "All" end

    local counters = { restock = 0, rejected = 0, claimCount = 0, claimedId = "-" }

    -- ==================
    -- WINDOW
    -- ==================
    local Window = WindUI:CreateWindow({
        Title         = "Nebula Hub           ",
        Folder        = "nebula_configs",
        Icon          = "solar:planet-2-bold-duotone",
        IconColor     = Color3.fromHex("#BB86FC"),
        NewElements   = true,
        AccentColor   = Color3.fromHex("#6200EE"),
        HideSearchBar = false,
        OpenButton    = {
            Title           = "NEBULA",
            CornerRadius    = UDim.new(0, 8),
            StrokeThickness = 2,
            Enabled         = true,
            Draggable       = true,
            OnlyMobile      = false,
            Scale           = 0.6,
            Color           = ColorSequence.new({
                ColorSequenceKeypoint.new(0,   Color3.new(1,1,1)),
                ColorSequenceKeypoint.new(0.5, Color3.new(1,1,1)),
                ColorSequenceKeypoint.new(1,   Color3.new(1,1,1)),
            }),
        },
        Topbar = { Height = 52, ButtonsType = "Mac" },
    })

    Window:Tag({ Title = " iPowfu ", Icon = "solar:shield-user-bold", Color = Color3.fromHex("#03DAC6"), Border = true })
    Window:Tag({ Title = " V18.9 ",  Icon = "solar:star-fall-bold",   Color = Color3.fromHex("#CF6679"), Border = true })

    -- ==================
    -- TAB RESTOCK
    -- ==================
    local Tab = Window:Tab({ Title = "Restock Booth", Icon = "solar:shop-bold", Border = true })
    Window:Divider()

    -- Scan
    Tab:Section({ Title = "Step 1 — Scan Inventory" })
    if #scanCache > 1 then
        Tab:Paragraph({
            Title = "Cache scan tersedia",
            Desc  = tostring(#scanCache - 1) .. " jenis anomali. Scan ulang untuk update.",
        })
    else
        Tab:Paragraph({
            Title = "Belum ada data scan",
            Desc  = "Klik Scan untuk mendeteksi item di backpack.",
        })
    end

    Tab:Button({
        Title = "Scan Inventory",
        Desc  = "Scan backpack lalu rebuild UI otomatis",
        Icon  = "solar:magnifer-bold",
        Color = Color3.fromHex("#03DAC6"),
        Callback = function()
            task.spawn(function()
                local blocks, anomals = ScanInventory()
                local uniqueNames = GetUniqueAnomaliNames(anomals)
                SaveScanCache(uniqueNames)
                WindUI:Notify({
                    Title   = "Scan Selesai",
                    Content = "Block: " .. #blocks .. " | Anomali: " .. #anomals
                        .. " (" .. (#uniqueNames - 1) .. " jenis). Rebuild dalam 2s...",
                    Duration = 4,
                })
                task.wait(2)
                pcall(function() Window:Destroy() end)
                task.wait(0.3)
                BuildUI()
            end)
        end,
    })

    -- Filter
    Tab:Section({ Title = "Step 2 — Filter" })
    Tab:Dropdown({
        Title = "Tipe Item", Desc = "Pilih Block atau Anomali",
        Icon = "solar:sort-by-time-bold", Value = cfg.SellType,
        Values = { "Block", "Anomali" }, Multi = false, AllowNone = false,
        Callback = function(v) cfg.SellType = v SaveSettings(cfg) end,
    })
    Tab:Dropdown({
        Title = "Rarity Block", Desc = "Rarity block yang akan di-list",
        Icon = "solar:diploma-bold", Value = cfg.FilterRarity,
        Values = BLOCK_RARITIES, Multi = false, AllowNone = false,
        Callback = function(v) cfg.FilterRarity = v SaveSettings(cfg) end,
    })
    Tab:Dropdown({
        Title = "Jenis Anomali", Desc = "Pilih anomali (All = semua jenis)",
        Icon = "solar:ufo-bold", Value = cfg.FilterAnomali,
        Values = anomaliValues, Multi = false, AllowNone = false,
        Callback = function(v) cfg.FilterAnomali = v SaveSettings(cfg) end,
    })

    -- Pengaturan
    Tab:Section({ Title = "Step 3 — Pengaturan" })
    Tab:Input({
        Title = "Jumlah (QTY)", Desc = "Jumlah item per listing",
        Icon = "solar:hashtag-bold", Placeholder = tostring(cfg.StockAmount),
        Callback = function(v)
            local n = tonumber(v) if n and n > 0 then cfg.StockAmount = n SaveSettings(cfg) end
        end,
    })
    Tab:Input({
        Title = "Harga Per Item", Desc = "Harga jual per item",
        Icon = "solar:tag-price-bold", Placeholder = tostring(cfg.StockPrice),
        Callback = function(v)
            local n = tonumber(v) if n and n >= 0 then cfg.StockPrice = n SaveSettings(cfg) end
        end,
    })
    Tab:Input({
        Title = "Delay Restock (detik)", Desc = "Jeda antar item — makin kecil makin cepat (min: 0.05s)",
        Icon = "solar:clock-circle-bold", Placeholder = tostring(cfg.RestockDelay),
        Callback = function(v)
            local n = tonumber(v) if n and n >= 0.05 then cfg.RestockDelay = n SaveSettings(cfg) end
        end,
    })

    -- Jalankan
    Tab:Section({ Title = "Step 4 — Jalankan" })
    local RestockThread = nil
    Tab:Toggle({
        Title = "Auto Restock Loop",
        Desc  = "Restock terus-menerus sesuai filter — berhenti saat di-toggle off",
        Icon  = "solar:refresh-bold",
        Value = false,
        Callback = function(v)
            if v then
                if RestockThread then task.cancel(RestockThread) end
                counters.restock  = 0
                counters.rejected = 0
                local info = cfg.SellType == "Block"
                    and ("Block " .. cfg.FilterRarity)
                    or  ("Anomali: " .. cfg.FilterAnomali)
                WindUI:Notify({
                    Title   = "Auto Restock Aktif",
                    Content = info .. " | qty: " .. cfg.StockAmount .. " | harga: " .. cfg.StockPrice,
                    Duration = 3,
                })
                RestockThread = task.spawn(function()
                    local round = 0
                    while true do
                        round = round + 1
                        local blocks, anomals = ScanInventory()
                        local items = {}
                        if cfg.SellType == "Block" then
                            for _, item in ipairs(blocks) do
                                if string.lower(item.rarity) == string.lower(cfg.FilterRarity) then
                                    table.insert(items, item)
                                end
                            end
                        else
                            for _, item in ipairs(anomals) do
                                local match = cfg.FilterAnomali == "All"
                                    or string.lower(item.brainrotName) == string.lower(cfg.FilterAnomali)
                                if match then table.insert(items, item) end
                            end
                        end

                        if #items == 0 then
                            task.wait(2)
                            continue
                        end

                        local consReject = 0
                        for _, item in ipairs(items) do
                            local ok = RestockItem(item, cfg, counters)
                            if ok then
                                consReject = 0
                            else
                                consReject = consReject + 1
                                if consReject >= 5 then break end
                            end
                            task.wait(cfg.RestockDelay)
                        end

                        task.wait(1)
                    end
                end)
            else
                if RestockThread then task.cancel(RestockThread) RestockThread = nil end
                WindUI:Notify({ Title = "Auto Restock", Content = "Dihentikan.", Duration = 3 })
            end
        end,
    })

    -- ==================
    -- TAB CLAIM BOOTH
    -- ==================
    local ClaimTab = Window:Tab({ Title = "Claim Booth", Icon = "solar:home-add-bold", Border = true })

    ClaimTab:Section({ Title = "Pengaturan" })
    ClaimTab:Paragraph({
        Title = "Cara Kerja",
        Desc  = "Loop semua booth satu-per-satu → kalau server return true (kosong) → claim → teleport → selesai.",
    })
    ClaimTab:Input({
        Title = "Delay Antar Booth (detik)", Desc = "Jeda tiap booth dicoba (min: 0.1s)",
        Icon = "solar:clock-circle-bold", Placeholder = tostring(cfg.ClaimDelay),
        Callback = function(v)
            local n = tonumber(v) if n and n >= 0.1 then cfg.ClaimDelay = n SaveSettings(cfg) end
        end,
    })
    ClaimTab:Input({
        Title = "Interval Loop (detik)", Desc = "Jeda setelah 1 putaran semua booth (min: 1s)",
        Icon = "solar:refresh-circle-bold", Placeholder = tostring(cfg.ClaimInterval),
        Callback = function(v)
            local n = tonumber(v) if n and n >= 1 then cfg.ClaimInterval = n SaveSettings(cfg) end
        end,
    })

    ClaimTab:Section({ Title = "Claim Sekali" })
    ClaimTab:Button({
        Title = "Scan & Claim Booth Kosong",
        Desc  = "Loop semua booth → claim pertama yang kosong → teleport",
        Icon  = "solar:home-bold",
        Color = Color3.fromHex("#03DAC6"),
        Callback = function()
            task.spawn(function()
                local booths = GetAllBooths()
                if #booths == 0 then
                    WindUI:Notify({ Title = "Claim", Content = "Booth folder tidak ditemukan!", Duration = 3 })
                    return
                end
                WindUI:Notify({ Title = "Claim Dimulai", Content = "Mencoba " .. #booths .. " booth...", Duration = 3 })
                for i, booth in ipairs(booths) do
                    if TryClaimBooth(booth) then
                        task.wait(0.3)
                        TeleportToBooth(booth)
                        counters.claimCount = counters.claimCount + 1
                        counters.claimedId  = booth.Name
                        WindUI:Notify({
                            Title   = "Booth Berhasil Di-claim!",
                            Content = "Booth ke-" .. i .. "/" .. #booths .. "\nSudah teleport ke lokasi.",
                            Duration = 8,
                        })
                        return
                    end
                    task.wait(cfg.ClaimDelay)
                end
                WindUI:Notify({
                    Title   = "Semua Booth Penuh",
                    Content = "Tidak ada booth kosong. Aktifkan Auto Claim Loop!",
                    Duration = 5,
                })
            end)
        end,
    })

    ClaimTab:Section({ Title = "Auto Claim Loop" })
    ClaimTab:Paragraph({
        Title = "Auto Loop",
        Desc  = "Scan terus sampai dapat booth kosong → claim → teleport → berhenti otomatis.",
    })

    local ClaimLoopThread = nil
    ClaimTab:Toggle({
        Title = "Auto Claim Loop",
        Desc  = "Terus scan & claim sampai dapat booth, lalu stop",
        Icon  = "solar:refresh-bold",
        Value = false,
        Callback = function(v)
            if v then
                if ClaimLoopThread then task.cancel(ClaimLoopThread) end
                WindUI:Notify({
                    Title   = "Auto Claim Loop Aktif",
                    Content = "Scan tiap " .. cfg.ClaimInterval .. "s. Stop otomatis saat dapat booth!",
                    Duration = 4,
                })
                ClaimLoopThread = task.spawn(function()
                    local round = 0
                    while true do
                        round = round + 1
                        local booths = GetAllBooths()
                        if #booths == 0 then task.wait(cfg.ClaimInterval) continue end
                        local found = false
                        for _, booth in ipairs(booths) do
                            if TryClaimBooth(booth) then
                                task.wait(0.3)
                                TeleportToBooth(booth)
                                counters.claimCount = counters.claimCount + 1
                                counters.claimedId  = booth.Name
                                WindUI:Notify({
                                    Title   = "Auto Claim Berhasil! Round " .. round,
                                    Content = "Booth: " .. booth.Name:sub(1,16) .. "...\nSudah teleport ke lokasi!",
                                    Duration = 8,
                                })
                                found = true
                                break
                            end
                            task.wait(cfg.ClaimDelay)
                        end
                        if found then ClaimLoopThread = nil break end
                        task.wait(cfg.ClaimInterval)
                    end
                end)
            else
                if ClaimLoopThread then task.cancel(ClaimLoopThread) ClaimLoopThread = nil end
                WindUI:Notify({ Title = "Auto Claim", Content = "Dihentikan.", Duration = 3 })
            end
        end,
    })

    ClaimTab:Section({ Title = "Utilitas" })
    ClaimTab:Button({
        Title = "Teleport Ulang ke Booth",
        Desc  = "Teleport lagi ke booth yang terakhir di-claim",
        Icon  = "solar:map-point-bold",
        Color = Color3.fromHex("#BB86FC"),
        Callback = function()
            if counters.claimedId == "-" then
                WindUI:Notify({ Title = "Teleport", Content = "Belum ada booth yang di-claim!", Duration = 3 })
                return
            end
            pcall(function()
                local booth = workspace.GameObjects.Booths[counters.claimedId]
                if booth then
                    TeleportToBooth(booth)
                    WindUI:Notify({ Title = "Teleport", Content = "Berhasil teleport ke booth!", Duration = 3 })
                else
                    WindUI:Notify({ Title = "Teleport", Content = "Booth tidak ditemukan lagi!", Duration = 3 })
                end
            end)
        end,
    })

    -- ==================
    -- TAB ANTI AFK
    -- ==================
    local AfkTab = Window:Tab({ Title = "Anti AFK", Icon = "solar:user-check-bold", Border = true })

    AfkTab:Section({ Title = "Anti AFK" })
    AfkTab:Paragraph({
        Title = "Cara Kerja",
        Desc  = "Tiap 60 detik karakter akan jump + simulasi tekan W singkat untuk reset timer AFK Roblox.",
    })
    AfkTab:Toggle({
        Title = "Anti AFK",
        Desc  = "Aktifkan agar tidak di-kick saat AFK",
        Icon  = "solar:shield-check-bold",
        Value = false,
        Callback = function(v)
            if v then
                StartAntiAfk()
                WindUI:Notify({ Title = "Anti AFK", Content = "Aktif! Reset timer tiap 60 detik.", Duration = 3 })
            else
                StopAntiAfk()
                WindUI:Notify({ Title = "Anti AFK", Content = "Dimatikan.", Duration = 3 })
            end
        end,
    })

    -- ==================
    -- TAB INFO
    -- ==================
    local InfoTab = Window:Tab({ Title = "Info", Icon = "solar:info-square-bold" })

    local Response = nil
    pcall(function()
        Response = HttpService:JSONDecode(
            game:HttpGet("https://discord.com/api/v9/invites/" .. InviteCode .. "?with_counts=true")
        )
    end)

    if Response and Response.guild then
        InfoTab:Section({ Title = "Join Discord Server!" })
        InfoTab:Paragraph({
            Title     = tostring(Response.guild.name),
            Desc      = tostring(Response.guild.description or "Welcome to Nebula Hub Community"),
            Image     = "https://cdn.discordapp.com/icons/" .. Response.guild.id .. "/" .. Response.guild.icon .. ".png?size=1024",
            ImageSize = 48,
            Buttons   = {{ Title = "Copy Link", Icon = "solar:copy-bold",
                Callback = function()
                    setclipboard("https://discord.gg/" .. InviteCode)
                    WindUI:Notify({ Title = "Discord", Content = "Link disalin!" })
                end }},
        })
    else
        InfoTab:Section({ Title = "Community" })
        InfoTab:Button({
            Title = "Copy Discord Link", Icon = "solar:share-circle-bold",
            Callback = function()
                setclipboard("https://discord.gg/" .. InviteCode)
                WindUI:Notify({ Title = "Nebula Hub", Content = "Link disalin!" })
            end,
        })
    end

    InfoTab:Section({ Title = "System" })
    InfoTab:Button({ Title = "Master: iPowfu",      Icon = "solar:verified-check-bold", Color = Color3.fromHex("#ffffff") })
    InfoTab:Button({ Title = "Channel: Nebula Hub", Icon = "solar:play-circle-bold",    Color = Color3.fromHex("#ffffff") })

    Window:SelectTab(Tab)
end

-- =============================================
-- INIT
-- =============================================
BuildUI()

WindUI:Notify({
    Title   = "Nebula Hub Loaded",
    Content = "Restock + Claim + Anti AFK siap digunakan!",
    Duration = 5,
})
