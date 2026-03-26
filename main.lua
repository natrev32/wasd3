-- Nebula Hub v18.9 – Midnight Nebula Edition
-- Feature: Auto Restock Booth + Auto Claim Booth + Anti AFK + Auto Trade
-- Authority: iPowfu | Channel: Nebula Hub

local RunService = game:GetService("RunService")
local cloneref   = (cloneref or table.clone or function(i) return i end)
local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
local HttpService = game:GetService("HttpService")
local Players     = game:GetService("Players")
local VIM         = game:GetService("VirtualInputManager")
local VirtualUser = game:GetService("VirtualUser")

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
    "Common","Uncommon","Rare","Epic","Legendary",
    "Mythical","Cosmic","Secret","Celestial","Divine","Infinity",
    "Radioactive","UFO","Money","Arcade","Valentines","Volcanic","Sugar Rush","Admin",
}

-- =============================================
-- SETTINGS
-- =============================================
local SETTINGS_FILE = "NebulaHub_Settings.json"
local SCAN_FILE     = "NebulaHub_ScanCache.json"

local function LoadSettings()
    local d = {
        -- Restock
        SellType        = "Block",
        FilterRarity    = "Common",
        FilterAnomali   = "All",
        FilterMutation  = "All",
        FilterLevelMin  = 0,
        FilterLevelMax  = 9999,
        StockAmount     = 100,
        StockPrice      = 100,
        RestockDelay    = 0.2,
        -- Claim
        ClaimDelay    = 0.5,
        ClaimInterval = 3,
        -- Trade
        TradeSellType     = "Block",
        TradeRarity       = "Common",
        TradeAnomali      = "All",
        TradeMutation     = "All",
        TradeLevelMin     = 0,
        TradeLevelMax     = 9999,
        TradeSlotCount    = 1,
        TradeWaitAccept   = 5,
        TradeWaitAfterAcc = 2,
        TradeSendDelay    = 0.5,
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
-- REMOTES (RESTOCK & CLAIM)
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
-- ANTI AFK (FIXED - 100% RELIABLE)
-- =============================================
local antiAfkRunning = false
local antiAfkThread  = nil
local idledConn      = nil

local function StartAntiAfk()
    if antiAfkRunning then return end
    antiAfkRunning = true

    if idledConn then
        pcall(function() idledConn:Disconnect() end)
        idledConn = nil
    end

    idledConn = lp.Idled:Connect(function()
        if not antiAfkRunning then return end
        pcall(function()
            VirtualUser:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
            task.wait(0.1)
            VirtualUser:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
        end)
    end)

    antiAfkThread = task.spawn(function()
        while antiAfkRunning do
            task.wait(55)
            if not antiAfkRunning then break end

            pcall(function()
                local char = lp.Character
                if char then
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    if hum and hum:GetState() ~= Enum.HumanoidStateType.Dead then
                        hum:ChangeState(Enum.HumanoidStateType.Jumping)
                    end
                end

                VirtualUser:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
                task.wait(0.05)
                VirtualUser:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)

                pcall(function()
                    VIM:SendKeyEvent(true,  Enum.KeyCode.W, false, game)
                    task.wait(0.05)
                    VIM:SendKeyEvent(false, Enum.KeyCode.W, false, game)
                end)
            end)
        end
    end)
end

local function StopAntiAfk()
    antiAfkRunning = false

    if idledConn then
        pcall(function() idledConn:Disconnect() end)
        idledConn = nil
    end

    if antiAfkThread then
        pcall(function() task.cancel(antiAfkThread) end)
        antiAfkThread = nil
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
            local mutation     = item:GetAttribute("Mutation") or "None"
            local level        = tonumber(item:GetAttribute("Level")) or 0
            if luckyType and luckyType ~= "" then
                table.insert(blocks, { id = item.Name, displayName = displayName, rarity = luckyType, mutation = mutation, level = level })
            elseif brainrotName and brainrotName ~= "" then
                table.insert(anomals, { id = item.Name, brainrotName = brainrotName, displayName = displayName, mutation = mutation, level = level })
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

    Tab:Section({ Title = "Step 1 — Scan Inventory" })
    if #scanCache > 1 then
        Tab:Paragraph({
            Title = "Cache tersedia",
            Desc  = tostring(#scanCache - 1) .. " jenis anomali.",
        })
    else
        Tab:Paragraph({
            Title = "Belum di-scan",
            Desc  = "Klik Scan untuk deteksi item.",
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

    -- Ambil list mutation dari ReplicatedStorage untuk restock
    local restockMutList = { "All", "None" }
    pcall(function()
        local folder = ReplicatedStorage:WaitForChild("Assets", 3):WaitForChild("Mutations", 3)
        local names = {}
        for _, m in ipairs(folder:GetChildren()) do
            if m:IsA("Folder") then
                for _, sub in ipairs(m:GetChildren()) do table.insert(names, sub.Name) end
            else
                table.insert(names, m.Name)
            end
        end
        table.sort(names)
        for _, n in ipairs(names) do table.insert(restockMutList, n) end
    end)
    -- Validasi saved value
    local rMutValid = false
    for _, v in ipairs(restockMutList) do if v == cfg.FilterMutation then rMutValid = true break end end
    if not rMutValid then cfg.FilterMutation = "All" end

    Tab:Dropdown({
        Title = "Mutation", Desc = "Filter mutation item (All = semua, None = tanpa mutation)",
        Icon = "solar:atom-bold", Value = cfg.FilterMutation,
        Values = restockMutList, Multi = false, AllowNone = false,
        Callback = function(v) cfg.FilterMutation = v SaveSettings(cfg) end,
    })
    Tab:Input({
        Title = "Level Minimum", Desc = "Hanya restock item level >= nilai ini (0 = semua)",
        Icon = "solar:arrow-up-bold", Placeholder = tostring(cfg.FilterLevelMin),
        Callback = function(v)
            local n = tonumber(v) if n and n >= 0 then cfg.FilterLevelMin = math.floor(n) SaveSettings(cfg) end
        end,
    })
    Tab:Input({
        Title = "Level Maksimum", Desc = "Hanya restock item level <= nilai ini (9999 = semua)",
        Icon = "solar:arrow-down-bold", Placeholder = tostring(cfg.FilterLevelMax),
        Callback = function(v)
            local n = tonumber(v) if n and n >= 0 then cfg.FilterLevelMax = math.floor(n) SaveSettings(cfg) end
        end,
    })

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
        Title = "Delay Restock (detik)", Desc = "Jeda antar item — min: 0.05s",
        Icon = "solar:clock-circle-bold", Placeholder = tostring(cfg.RestockDelay),
        Callback = function(v)
            local n = tonumber(v) if n and n >= 0.05 then cfg.RestockDelay = n SaveSettings(cfg) end
        end,
    })

    Tab:Section({ Title = "Step 4 — Jalankan" })
    local RestockThread = nil
    Tab:Toggle({
        Title = "Auto Restock Loop",
        Desc  = "Restock terus-menerus sesuai filter",
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
                                local rarityMatch = string.lower(item.rarity) == string.lower(cfg.FilterRarity)
                                local mutMatch    = cfg.FilterMutation == "All"
                                    or string.lower(item.mutation or "none") == string.lower(cfg.FilterMutation)
                                local lvlMatch    = item.level >= cfg.FilterLevelMin and item.level <= cfg.FilterLevelMax
                                if rarityMatch and mutMatch and lvlMatch then
                                    table.insert(items, item)
                                end
                            end
                        else
                            for _, item in ipairs(anomals) do
                                local nameMatch = cfg.FilterAnomali == "All"
                                    or string.lower(item.brainrotName) == string.lower(cfg.FilterAnomali)
                                local mutMatch  = cfg.FilterMutation == "All"
                                    or string.lower(item.mutation or "none") == string.lower(cfg.FilterMutation)
                                local lvlMatch  = item.level >= cfg.FilterLevelMin and item.level <= cfg.FilterLevelMax
                                if nameMatch and mutMatch and lvlMatch then
                                    table.insert(items, item)
                                end
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
        Title = "Claim Booth",
        Desc  = "Scan semua booth, claim yang kosong, lalu teleport.",
    })
    ClaimTab:Input({
        Title = "Delay Antar Booth (detik)", Desc = "Min: 0.1s",
        Icon = "solar:clock-circle-bold", Placeholder = tostring(cfg.ClaimDelay),
        Callback = function(v)
            local n = tonumber(v) if n and n >= 0.1 then cfg.ClaimDelay = n SaveSettings(cfg) end
        end,
    })
    ClaimTab:Input({
        Title = "Interval Loop (detik)", Desc = "Min: 1s",
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
        Desc  = "Loop terus sampai dapat booth kosong, lalu berhenti.",
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
        Title = "Triple Method",
        Desc  = "Idled event + loop 55 detik + VIM backup. Aktifkan agar tidak di-kick.",
    })

    AfkTab:Toggle({
        Title = "Anti AFK",
        Desc  = "Aktifkan agar tidak di-kick. Triple method = 100% reliable.",
        Icon  = "solar:shield-check-bold",
        Value = false,
        Callback = function(v)
            if v then
                StartAntiAfk()
                WindUI:Notify({
                    Title   = "Anti AFK Aktif",
                    Content = "Triple method aktif:\n• Idled event interceptor\n• Loop 55 detik\n• VIM backup",
                    Duration = 4,
                })
            else
                StopAntiAfk()
                WindUI:Notify({ Title = "Anti AFK", Content = "Dimatikan.", Duration = 3 })
            end
        end,
    })

    -- ==================
    -- TAB TRADE
    -- ==================
    local TradeTab = Window:Tab({ Title = "Auto Trade", Icon = "solar:transfer-horizontal-bold", Border = true })

    -- REMOTES TRADE
    local TradeRemote, TradeSlotRemote, TradeReadyRemote

    local function GetTradeRemote()
        if TradeRemote then return TradeRemote end
        pcall(function()
            TradeRemote = ReplicatedStorage
                :WaitForChild("Shared"):WaitForChild("Remotes")
                :WaitForChild("Networking"):WaitForChild("RF/TradeSendTrade")
        end)
        return TradeRemote
    end

    local function GetTradeSlotRemote()
        if TradeSlotRemote then return TradeSlotRemote end
        pcall(function()
            TradeSlotRemote = ReplicatedStorage
                :WaitForChild("Shared"):WaitForChild("Remotes")
                :WaitForChild("Networking"):WaitForChild("RF/TradeSetSlotOffer")
        end)
        return TradeSlotRemote
    end

    local function GetTradeReadyRemote()
        if TradeReadyRemote then return TradeReadyRemote end
        pcall(function()
            TradeReadyRemote = ReplicatedStorage
                :WaitForChild("Shared"):WaitForChild("Remotes")
                :WaitForChild("Networking"):WaitForChild("RE/Trading/TradeReadyTrade")
        end)
        return TradeReadyRemote
    end

    -- STATE TRADE — nilai awal dari file settings
    local tradeState = {
        TargetName   = "",
        SellType     = cfg.TradeSellType,
        FilterRarity = cfg.TradeRarity,
        FilterAnomali= cfg.TradeAnomali,
        FilterMutation = cfg.TradeMutation,
        LevelMin     = cfg.TradeLevelMin,
        LevelMax     = cfg.TradeLevelMax,
        SlotCount    = cfg.TradeSlotCount,
        WaitAccept   = cfg.TradeWaitAccept,
        WaitAfterAcc = cfg.TradeWaitAfterAcc,
        SendDelay    = cfg.TradeSendDelay,
    }

    -- Helper: simpan tradeState ke cfg lalu save ke file
    local function SaveTrade()
        cfg.TradeSellType     = tradeState.SellType
        cfg.TradeRarity       = tradeState.FilterRarity
        cfg.TradeAnomali      = tradeState.FilterAnomali
        cfg.TradeMutation     = tradeState.FilterMutation
        cfg.TradeLevelMin     = tradeState.LevelMin
        cfg.TradeLevelMax     = tradeState.LevelMax
        cfg.TradeSlotCount    = tradeState.SlotCount
        cfg.TradeWaitAccept   = tradeState.WaitAccept
        cfg.TradeWaitAfterAcc = tradeState.WaitAfterAcc
        cfg.TradeSendDelay    = tradeState.SendDelay
        SaveSettings(cfg)
    end

    -- Helper: get player list di server (exclude diri sendiri)
    local function GetServerPlayers()
        local list = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= lp then
                table.insert(list, p.Name)
            end
        end
        if #list == 0 then table.insert(list, "(Tidak ada player lain)") end
        return list
    end

    -- ---- SECTION: Target Player ----
    TradeTab:Section({ Title = "Step 1 — Target Player" })

    TradeTab:Paragraph({
        Title = "Pilih Target",
        Desc  = "Pilih dari dropdown atau ketik manual di bawah.",
    })

    local playerList = GetServerPlayers()
    TradeTab:Dropdown({
        Title  = "Player di Server",
        Desc   = "Pilih dari player yang ada",
        Icon   = "solar:users-group-rounded-bold",
        Value  = playerList[1],
        Values = playerList,
        Multi  = false,
        AllowNone = false,
        Callback = function(v)
            if v ~= "(Tidak ada player lain)" then
                tradeState.TargetName = v
            end
        end,
    })

    TradeTab:Button({
        Title = "Refresh List Player",
        Desc  = "Update daftar player di server",
        Icon  = "solar:refresh-bold",
        Color = Color3.fromHex("#03DAC6"),
        Callback = function()
            task.spawn(function()
                pcall(function() Window:Destroy() end)
                task.wait(0.3)
                BuildUI()
            end)
        end,
    })

    TradeTab:Input({
        Title       = "Manual — Nama Player",
        Desc        = "Ketik nama player target (override dropdown)",
        Icon        = "solar:user-bold",
        Placeholder = "Contoh: PlayerName123",
        Callback    = function(v)
            if v and v ~= "" then
                tradeState.TargetName = v
            end
        end,
    })

    -- Helper: ambil list mutation dari ReplicatedStorage.Assets.Mutations
    local function GetMutationList()
        local list = {}
        pcall(function()
            local folder = ReplicatedStorage:WaitForChild("Assets", 3):WaitForChild("Mutations", 3)
            for _, m in ipairs(folder:GetChildren()) do
                if m:IsA("Folder") then
                    -- subfolder (Electric, GearMutations) — ambil anak-anaknya
                    for _, sub in ipairs(m:GetChildren()) do
                        table.insert(list, sub.Name)
                    end
                else
                    table.insert(list, m.Name)
                end
            end
        end)
        table.sort(list)
        table.insert(list, 1, "None")
        table.insert(list, 1, "All")
        return list
    end

    -- ---- SECTION: Item Filter ----
    TradeTab:Section({ Title = "Step 2 — Pilih Item yang Di-Trade" })

    local tradeAnomalyValues = #scanCache > 1 and scanCache or { "All" }
    if tradeAnomalyValues[1] ~= "All" then table.insert(tradeAnomalyValues, 1, "All") end

    TradeTab:Dropdown({
        Title  = "Tipe Item",
        Desc   = "Block atau Anomali",
        Icon   = "solar:sort-by-time-bold",
        Value  = tradeState.SellType,
        Values = { "Block", "Anomali" },
        Multi  = false,
        AllowNone = false,
        Callback = function(v) tradeState.SellType = v SaveTrade() end,
    })

    TradeTab:Dropdown({
        Title  = "Rarity Block",
        Desc   = "Rarity block yang akan di-trade",
        Icon   = "solar:diploma-bold",
        Value  = tradeState.FilterRarity,
        Values = BLOCK_RARITIES,
        Multi  = false,
        AllowNone = false,
        Callback = function(v) tradeState.FilterRarity = v SaveTrade() end,
    })

    TradeTab:Dropdown({
        Title  = "Jenis Anomali",
        Desc   = "Pilih anomali (All = semua jenis)",
        Icon   = "solar:ufo-bold",
        Value  = tradeState.FilterAnomali,
        Values = tradeAnomalyValues,
        Multi  = false,
        AllowNone = false,
        Callback = function(v) tradeState.FilterAnomali = v SaveTrade() end,
    })

    local mutationList = GetMutationList()
    -- Pastikan saved value valid, fallback ke "All"
    local mutValid = false
    for _, v in ipairs(mutationList) do if v == tradeState.FilterMutation then mutValid = true break end end
    if not mutValid then tradeState.FilterMutation = "All" end

    TradeTab:Dropdown({
        Title  = "Mutation",
        Desc   = "Filter mutation item (All = semua, None = tanpa mutation)",
        Icon   = "solar:atom-bold",
        Value  = tradeState.FilterMutation,
        Values = mutationList,
        Multi  = false,
        AllowNone = false,
        Callback = function(v) tradeState.FilterMutation = v SaveTrade() end,
    })

    TradeTab:Input({
        Title       = "Level Minimum",
        Desc        = "Item dengan level >= nilai ini yang di-trade (0 = semua)",
        Icon        = "solar:arrow-up-bold",
        Placeholder = tostring(tradeState.LevelMin),
        Callback    = function(v)
            local n = tonumber(v)
            if n and n >= 0 then tradeState.LevelMin = math.floor(n) SaveTrade() end
        end,
    })

    TradeTab:Input({
        Title       = "Level Maksimum",
        Desc        = "Item dengan level <= nilai ini yang di-trade (9999 = semua)",
        Icon        = "solar:arrow-down-bold",
        Placeholder = tostring(tradeState.LevelMax),
        Callback    = function(v)
            local n = tonumber(v)
            if n and n >= 0 then tradeState.LevelMax = math.floor(n) SaveTrade() end
        end,
    })

    -- ---- SECTION: Pengaturan ----
    TradeTab:Section({ Title = "Step 3 — Pengaturan Trade" })

    TradeTab:Input({
        Title       = "Jumlah Slot Item",
        Desc        = "Berapa item yang ditaruh di trade slot (maks sesuai game)",
        Icon        = "solar:hashtag-bold",
        Placeholder = tostring(tradeState.SlotCount),
        Callback    = function(v)
            local n = tonumber(v)
            if n and n >= 1 then tradeState.SlotCount = math.floor(n) SaveTrade() end
        end,
    })

    TradeTab:Input({
        Title       = "Delay Tunggu Lawan Accept (detik)",
        Desc        = "Jeda setelah send request — waktu buat lawan klik Accept. Min: 1s",
        Icon        = "solar:hourglass-bold",
        Placeholder = tostring(tradeState.WaitAccept),
        Callback    = function(v)
            local n = tonumber(v)
            if n and n >= 1 then tradeState.WaitAccept = n SaveTrade() end
        end,
    })

    TradeTab:Input({
        Title       = "Delay Setelah Accept (detik)",
        Desc        = "Jeda ekstra setelah acc sebelum set item — biar server siap. Min: 1s",
        Icon        = "solar:clock-circle-bold",
        Placeholder = tostring(tradeState.WaitAfterAcc),
        Callback    = function(v)
            local n = tonumber(v)
            if n and n >= 1 then tradeState.WaitAfterAcc = n SaveTrade() end
        end,
    })

    TradeTab:Input({
        Title       = "Delay Antar Slot (detik)",
        Desc        = "Jeda antar invoke set slot — min: 0.3s",
        Icon        = "solar:transfer-horizontal-bold",
        Placeholder = tostring(tradeState.SendDelay),
        Callback    = function(v)
            local n = tonumber(v)
            if n and n >= 0.3 then tradeState.SendDelay = n SaveTrade() end
        end,
    })

    -- ---- SECTION: Eksekusi ----
    TradeTab:Section({ Title = "Step 4 — Jalankan Trade" })

    TradeTab:Paragraph({
        Title = "Urutan Otomatis",
        Desc  = "Send → tunggu acc → stabilisasi → set item → accept.",
    })

    TradeTab:Button({
        Title = "Mulai Auto Trade",
        Desc  = "Kirim trade → tunggu acc → set item → accept",
        Icon  = "solar:transfer-horizontal-bold",
        Color = Color3.fromHex("#BB86FC"),
        Callback = function()
            task.spawn(function()

                -- Validasi target
                if tradeState.TargetName == "" then
                    WindUI:Notify({
                        Title   = "Auto Trade",
                        Content = "Pilih atau ketik nama player target dulu!",
                        Duration = 4,
                    })
                    return
                end

                -- Cari player object
                local targetPlayer = Players:FindFirstChild(tradeState.TargetName)
                if not targetPlayer then
                    WindUI:Notify({
                        Title   = "Auto Trade",
                        Content = "Player '" .. tradeState.TargetName .. "' tidak ditemukan di server!",
                        Duration = 4,
                    })
                    return
                end

                -- Scan inventory untuk ambil item
                local blocks, anomals = ScanInventory()
                local items = {}

                if tradeState.SellType == "Block" then
                    for _, item in ipairs(blocks) do
                        local rarityMatch   = string.lower(item.rarity) == string.lower(tradeState.FilterRarity)
                        local mutMatch      = tradeState.FilterMutation == "All"
                            or string.lower(item.mutation or "none") == string.lower(tradeState.FilterMutation)
                        local levelMatch    = item.level >= tradeState.LevelMin and item.level <= tradeState.LevelMax
                        if rarityMatch and mutMatch and levelMatch then
                            table.insert(items, item)
                        end
                    end
                else
                    for _, item in ipairs(anomals) do
                        local nameMatch  = tradeState.FilterAnomali == "All"
                            or string.lower(item.brainrotName) == string.lower(tradeState.FilterAnomali)
                        local mutMatch   = tradeState.FilterMutation == "All"
                            or string.lower(item.mutation or "none") == string.lower(tradeState.FilterMutation)
                        local levelMatch = item.level >= tradeState.LevelMin and item.level <= tradeState.LevelMax
                        if nameMatch and mutMatch and levelMatch then
                            table.insert(items, item)
                        end
                    end
                end

                if #items == 0 then
                    WindUI:Notify({
                        Title   = "Auto Trade",
                        Content = "Tidak ada item yang cocok di inventory!",
                        Duration = 4,
                    })
                    return
                end

                WindUI:Notify({
                    Title   = "Auto Trade Dimulai",
                    Content = "Target: " .. tradeState.TargetName
                        .. "\nItem tersedia: " .. #items
                        .. " | Slot: " .. tradeState.SlotCount,
                    Duration = 4,
                })

                -- STEP 1: Send trade request
                local tradeRemote = GetTradeRemote()
                if not tradeRemote then
                    WindUI:Notify({ Title = "Trade Error", Content = "RF/TradeSendTrade tidak ditemukan!", Duration = 4 })
                    return
                end

                local ok1, res1 = pcall(function()
                    return tradeRemote:InvokeServer(targetPlayer)
                end)

                if not ok1 then
                    WindUI:Notify({ Title = "Trade Error", Content = "Gagal send trade request!\n" .. tostring(res1), Duration = 5 })
                    return
                end

                -- STEP 2: Tunggu lawan acc — beri waktu cukup sebelum lanjut
                WindUI:Notify({
                    Title   = "Trade Request Terkirim",
                    Content = "Menunggu " .. tradeState.WaitAccept .. "s untuk " .. tradeState.TargetName .. " accept...",
                    Duration = tradeState.WaitAccept,
                })
                task.wait(tradeState.WaitAccept)

                -- STEP 3: Delay ekstra biar server/game selesai setup trade session
                WindUI:Notify({
                    Title   = "Stabilisasi Trade",
                    Content = "Menunggu " .. tradeState.WaitAfterAcc .. "s biar server siap...",
                    Duration = tradeState.WaitAfterAcc,
                })
                task.wait(tradeState.WaitAfterAcc)

                -- STEP 4: Set item ke slot
                local slotRemote = GetTradeSlotRemote()
                if not slotRemote then
                    WindUI:Notify({ Title = "Trade Error", Content = "RF/TradeSetSlotOffer tidak ditemukan!", Duration = 4 })
                    return
                end

                local slotCount = math.min(tradeState.SlotCount, #items)
                local successSlot = 0

                WindUI:Notify({
                    Title   = "Set Item",
                    Content = "Memasukkan " .. slotCount .. " item ke slot trade...",
                    Duration = 3,
                })

                for i = 1, slotCount do
                    local item = items[i]
                    local slotIndex = tostring(i)
                    local itemId    = item.id

                    local ok2, res2 = pcall(function()
                        return slotRemote:InvokeServer(slotIndex, itemId)
                    end)

                    if ok2 then
                        successSlot = successSlot + 1
                    else
                        warn("TradeSetSlot gagal slot " .. slotIndex .. ": " .. tostring(res2))
                    end

                    task.wait(tradeState.SendDelay)
                end

                WindUI:Notify({
                    Title   = "Item Di-set",
                    Content = successSlot .. "/" .. slotCount .. " slot berhasil.\nMenunggu cooldown 3s...",
                    Duration = 3,
                })

                -- Tunggu 3 detik — cooldown tombol Accept dari game setelah place item
                task.wait(3)

                -- STEP 5a: Fire ready (pertama) — tandai kita siap
                local readyRemote = GetTradeReadyRemote()
                if not readyRemote then
                    WindUI:Notify({ Title = "Trade Error", Content = "RE/Trading/TradeReadyTrade tidak ditemukan!", Duration = 4 })
                    return
                end

                pcall(function()
                    readyRemote:FireServer(true, 5)
                end)

                WindUI:Notify({
                    Title   = "Ready!",
                    Content = "Menunggu " .. tradeState.SendDelay .. "s lalu confirm accept...",
                    Duration = tradeState.SendDelay,
                })

                task.wait(tradeState.SendDelay)

                -- STEP 5b: Fire accept final — konfirmasi trade
                pcall(function()
                    readyRemote:FireServer(true, 5)
                end)

                WindUI:Notify({
                    Title   = "Auto Trade Selesai!",
                    Content = "Trade ke " .. tradeState.TargetName
                        .. " sudah di-accept!\nSlot berhasil: " .. successSlot .. "/" .. slotCount,
                    Duration = 6,
                })

            end)
        end,
    })

    -- Tombol cancel / reset state
    TradeTab:Button({
        Title = "Reset State Trade",
        Desc  = "Bersihkan target dan reset pengaturan",
        Icon  = "solar:restart-bold",
        Color = Color3.fromHex("#CF6679"),
        Callback = function()
            tradeState.TargetName = ""
            WindUI:Notify({ Title = "Trade", Content = "State direset.", Duration = 3 })
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
    Content = "Restock + Claim + Anti AFK + Auto Trade siap digunakan!",
    Duration = 5,
})
