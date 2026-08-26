--[[
    ██╗   ██╗ ██████╗██████╗ ██╗   ██╗
    ██║   ██║██╔════╝██╔══██╗╚██╗ ██╔╝
    ██║   ██║██║     ██████╔╝ ╚████╔╝
    ╚██╗ ██╔╝██║     ██╔═══╝ ██╔══██╗
     ╚████╔╝ ╚██████╗██║     ██║   ██║   + +
      ╚═══╝   ╚═════╝╚═╝     ╚═╝   ╚═╝
    VC++ hub  |  Murder Mystery 2  |  Auto Coin Farm
    ------------------------------------------------------------
    * GUI ลากได้ ปุ่ม toggle ครบ (Auto Farm / Auto Rejoin / Auto Claim / Noclip)
    * ฟาร์มเฉพาะ "ตอนถึงตาเราเล่นจริง" เท่านั้น
      -> ล็อบบี้ / พักรอบ / จอ "WAITING FOR YOUR TURN" (ผู้ชม) = ยืนเฉย ไม่บิน
    * ไหลลื่นด้วย tween ความเร็วคงที่ (กันโดนเตะ 267) + ล้างความเร็วกันจอสั่น
    * เก็บครบตามเป้า -> rejoin เข้าเซิร์ฟใหม่ (เร็วกว่า hop)
    * log แสดง เหรียญ/Shells/เวลา + ส่งเข้าระบบ Horst และ Masterp (auto-detect ทั้งคู่)
--]]

--==================== CONFIG ====================--
-- ★ ตั้งค่าได้ 2 ทาง:
--   1) วาง getgenv().VCPP_Config = {...} "เหนือ" loadstring (ถ้ามี จะใช้ตัวนี้ก่อน)
--   2) ถ้าไม่ได้ตั้งภายนอก -> ใช้ค่า DEFAULT_CONFIG ด้านล่างนี้ (แก้ตรงนี้แล้วอัพ luarmor ได้เลย)
-- --------------------------------------------------------------------------
local DEFAULT_CONFIG = {
    -- พื้นฐาน
    Farm = true, Claim = true, AutoPlay = true, AutoRejoin = true,
    FullAction = "kill", HorstLog = true, ShowInfo = true, ShowUI = false,
    -- ประสิทธิภาพ + กันค้าง
    UltraLite = true, LockFPS = 5, Noclip = true, HideChat = true, AntiAFK = true,
    -- การฟาร์ม
    Speed = 70, Target = 40, Dwell = 1.3, Spread = 4,
    -- โหมด 1: ฟาร์มเหรียญล้วน (เหรียญถึงเป้า -> เปลี่ยนไอดี)
    ChangeAtCoin = false, CoinGoal = 20000,
    -- โหมด 2: เปิดกล่องโกลด์ (เหรียญ)
    OpenCrates = false, Crates = { "KnifeBox1", "GunBox1" },
    CratesNeed = 0, OpenAmount = 1, OpenMax = 0, ChangeAtCoinOut = true,
    -- ★ โหมด 3: เปิดกล่อง Summer (เปลือกหอย) — เปิดเลยพอมีหอยพอ 1 กล่อง (120)
    OpenSummer = true, SummerNeed = 120, SummerAmount = 1, SummerMax = 0,
    TargetSkins = {}, ChangeAtShellOut = true,
    LogRarities = { "Legendary", "Godly", "Unique", "Ancient" },
}
-- ใช้ config ภายนอกถ้ามี ไม่งั้นใช้ค่า default ที่ฝังไว้ (กันเคส getgenv ไม่ถูกส่งมา)
local CFG = getgenv().VCPP_Config or _G.VCPP_Config or DEFAULT_CONFIG
local function cfg(key, default)
    local v = CFG[key]
    if v == nil then return default end
    return v
end

local STATE = getgenv().__VENOZ_HUB
if STATE then STATE.stop = true task.wait(0.3) end
STATE = {
    stop     = false,
    farming  = false,
    farm     = cfg("AutoFarm",   true),   -- เปิด auto farm
    hop      = cfg("AutoRejoin", true),   -- เก็บครบแล้ว rejoin เข้าเซิร์ฟใหม่
    noclip   = cfg("Noclip",     true),   -- ไหลทะลุ ไม่ติดมุม
    claim    = cfg("AutoClaim",  true),   -- auto กด Claim รางวัล (Shells ฯลฯ)
    speed    = cfg("Speed",      50),     -- ความเร็วไหล (studs/วิ) | 16-20 ปลอดภัยสุด, 45-60 ไวขึ้น
    target   = cfg("Target",     40),     -- เก็บครบเท่านี้แล้ว rejoin
    dwell    = cfg("Dwell",      1.3),    -- หน่วงบนเหรียญ ให้เก็บครบ (วิ)
    status   = "เริ่มต้น...",
}
getgenv().__VENOZ_HUB = STATE

--==================== SERVICES ====================--
if not game:IsLoaded() then game.Loaded:Wait() end
local Players         = game:GetService("Players")
local RunService      = game:GetService("RunService")
local TweenService    = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")
local HttpService     = game:GetService("HttpService")
local UserInput       = game:GetService("UserInputService")

local player = Players.LocalPlayer
while not player do task.wait(0.2) player = Players.LocalPlayer end

-- แปลงชื่อปุ่ม -> Enum.KeyCode (รองรับตัวเล็ก/ใหญ่ เช่น "b" -> Enum.KeyCode.B)
local function toKeyCode(name)
    name = tostring(name)
    for _, v in ipairs({ name, name:upper(), name:sub(1, 1):upper() .. name:sub(2):lower() }) do
        local ok, kc = pcall(function() return Enum.KeyCode[v] end)
        if ok and kc then return kc end
    end
    return nil
end

--==================== SESSION STATS + HORST ====================--
local session = { coins = 0, shells = 0, start = os.clock() }
local lastShellSig = ""
local reportHorst            -- forward declare (ใช้ใน serverHop ก่อนนิยาม)
local obtainedSkins = {}     -- log สกินของดี (Legendary/Godly) ที่ได้จากกล่อง

-- อ่านยอด "จริง" จาก GetProfileData:InvokeServer() (passive ไม่ต้องเปิด UI)
--   Coins  = Materials.Owned.Coins
--   Shells = Materials.Owned.SummerKey2026  (อีเวนต์เปลือกหอย)
-- จำค่าล่าสุดไว้ใน getgenv (อยู่รอดข้ามการรันสคริปต์ซ้ำในเซสชันเดียว)
local MEM = getgenv().__VCPP_MEM or { coins = 0, shells = 0 }
getgenv().__VCPP_MEM = MEM
local cacheCoins, cacheShells = MEM.coins or 0, MEM.shells or 0
local dataReady = (cacheCoins > 0 or cacheShells > 0)  -- ถ้ามีค่าจำไว้แล้ว ถือว่าพร้อม
local profileRF

-- หา remote แบบ lazy (เผื่อ autoexec โหลดก่อน Remotes มา)
local function resolveRF()
    if profileRF and profileRF.Parent then return profileRF end
    pcall(function()
        local rem = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
        local inv = rem and rem:FindFirstChild("Inventory")
        profileRF = inv and inv:FindFirstChild("GetProfileData")
    end)
    return profileRF
end

local function fetchProfile()
    local rf = resolveRF()
    if not rf then return false end
    local ok, data = pcall(function() return rf:InvokeServer() end)
    if ok and type(data) == "table" then
        local owned = data.Materials and data.Materials.Owned
        if type(owned) == "table" then
            -- ★ สำคัญ: พอเงิน/หอยหมด เซิร์ฟจะ "ลบ key ทิ้ง" (เป็น nil ไม่ใช่ 0)
            --   ถ้าเช็ค type=="number" มันจะข้าม -> ค่าค้างที่เลขเก่า (log ไม่ลด!)
            --   จึงใช้ tonumber(...) or 0 : ไม่มี key = 0 (ใช้หมดแล้ว)
            cacheCoins  = tonumber(owned.Coins) or 0
            cacheShells = tonumber(owned.SummerKey2026) or 0
            MEM.coins, MEM.shells = cacheCoins, cacheShells   -- จำค่าล่าสุด
            dataReady = true
            return true
        end
    end
    return false
end

-- background refresher: ตอนเริ่มลองรัวจนเจอ แล้วดึงซ้ำทุก ~12 วิ (ไม่ต้องเปิดร้าน)
task.spawn(function()
    for _ = 1, 15 do
        if STATE.stop then return end
        if fetchProfile() then break end
        task.wait(1)
    end
    while not STATE.stop do
        pcall(fetchProfile)
        task.wait(6)   -- อัพเลขบ่อยขึ้น (เหรียญ/หอยลดเห็นไว)
    end
end)

local function getTotalCoins() return cacheCoins end
local function getTotalShells() return cacheShells end
local function getLevel()
    local v = player:GetAttribute("Level")
    return tonumber(v) or 0
end

-- Horst config
local HORST_ENABLE   = cfg("HorstLog", cfg("Horst", true))  -- ส่งรายงานเข้า Horst
local HORST_INTERVAL = cfg("HorstEvery", 5)                 -- ส่งทุกกี่วินาที
-- ★ โหมด 1: ฟาร์มเหรียญ พอเหรียญรวมถึงเป้า -> เปลี่ยนไอดี (Horst AccountChangeDone)
local CHANGE_AT_COIN = cfg("ChangeAtCoin", false)
local COIN_GOAL      = cfg("CoinGoal", 0)
local HORST_DONE_COINS = (CHANGE_AT_COIN and COIN_GOAL > 0) and COIN_GOAL or cfg("HorstDoneAt", 0)
local horstDoneSent  = false

local function fmtTime(sec)
    sec = math.floor(sec)
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    local s = sec % 60
    if h > 0 then return string.format("%dh %dm %ds", h, m, s) end
    return string.format("%dm %ds", m, s)
end

--==================== ROUND STATE ====================--
local roundActive  = false
local roundStartAt = 0
local SETTLE_TIME  = 2.0

local function realCoinsExist()
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("BasePart") and d.Name == "Coin_Server" and not d:FindFirstAncestor("Lobby") then
            return true
        end
    end
    return false
end

do
    local rem = game.ReplicatedStorage:FindFirstChild("Remotes")
    local gp  = rem and rem:FindFirstChild("Gameplay")
    if gp then
        local function bind(name, fn)
            local r = gp:FindFirstChild(name)
            if r and r:IsA("RemoteEvent") then r.OnClientEvent:Connect(fn) end
        end
        bind("CoinsStarted", function()
            if not roundActive then roundStartAt = os.clock() end
            roundActive = true
        end)
        bind("GameOver",     function() roundActive = false end)
        bind("RoundEndFade", function() roundActive = false end)
        bind("CoinCollected", function() session.coins = session.coins + 1 end) -- นับเหรียญเซสชัน
    end
    if realCoinsExist() then
        roundActive  = true
        roundStartAt = os.clock() - SETTLE_TIME
    end
end

--==================== HELPERS ====================--
-- อ่านจำนวนเหรียญในกระเป๋า
local function getCoinCount()
    local n = 0
    pcall(function()
        local lbl = player.PlayerGui.MainGUI.Game.CoinBags.Container.Coin.CurrencyFrame.Icon.Coins
        if lbl and lbl:IsA("TextLabel") then n = tonumber(lbl.Text) or 0 end
    end)
    return n
end

local function isBagFull()
    if getCoinCount() >= STATE.target then return true end
    local full = false
    pcall(function()
        local coin = player.PlayerGui.MainGUI.Game.CoinBags.Container:FindFirstChild("Coin")
        local f = coin and coin:FindFirstChild("Full")
        if f and f.Visible then full = true end
    end)
    return full
end

-- เราเป็น "ผู้ชม/รอตาเล่น" อยู่ไหม (จอ WAITING FOR YOUR TURN)
local function isWaiting()
    local waiting = false
    pcall(function()
        local w = player.PlayerGui.MainGUI.Game:FindFirstChild("Waiting")
        if w and w:IsA("GuiObject") and w.Visible then waiting = true end
    end)
    return waiting
end

-- ถึงตาเราเล่นจริงไหม (ไม่ใช่ล็อบบี้ ไม่ใช่ผู้ชม ยังไม่ตาย)
local function amIPlaying()
    local char = player.Character
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if not (hum and hum.Health > 0) then return false end
    if isWaiting() then return false end
    if not roundActive then return false end
    if (os.clock() - roundStartAt) < SETTLE_TIME then return false end
    return true
end

-- หาเหรียญในแมพ (กันล็อบบี้)
local coinContainer
local function getContainer()
    if coinContainer and coinContainer.Parent then return coinContainer end
    for _, d in ipairs(workspace:GetDescendants()) do
        if d.Name == "CoinContainer" and not d:FindFirstAncestor("Lobby") then
            coinContainer = d ; return d
        end
    end
    coinContainer = nil ; return nil
end

-- เหรียญนี้ยังเก็บได้จริงไหม (คนอื่นเก็บไปแล้วจะมี Collected=true + TouchInterest หาย)
local function isCoinAvailable(c)
    if c:GetAttribute("Collected") then return false end
    if not c:FindFirstChild("TouchInterest") then return false end
    return true
end

local function findCoins()
    local list = {}
    local cont = getContainer()
    if cont then
        for _, c in ipairs(cont:GetChildren()) do
            if c:IsA("BasePart") and c.Name == "Coin_Server" and isCoinAvailable(c) then
                list[#list + 1] = c
            end
        end
    end
    if #list == 0 then
        for _, d in ipairs(workspace:GetDescendants()) do
            if d:IsA("BasePart") and d.Name == "Coin_Server" and not d:FindFirstAncestor("Lobby")
            and isCoinAvailable(d) then
                list[#list + 1] = d
            end
        end
    end
    return list
end

--==================== NOCLIP ====================--
RunService.Stepped:Connect(function()
    if not (STATE.noclip and STATE.farming) then return end
    local char = player.Character
    if not char then return end
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
    end
end)

--==================== MOVEMENT (ลื่น + กันเตะ) ====================--
local function pin(root)
    root.AssemblyLinearVelocity  = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
end

local function glideTo(root, pos)
    local dist = (root.Position - pos).Magnitude
    local dur  = math.max(dist / STATE.speed, 0.2)
    if dur > 15 then dur = 15 end
    local tween = TweenService:Create(root, TweenInfo.new(dur, Enum.EasingStyle.Linear), { CFrame = CFrame.new(pos) })
    tween:Play()
    local done = false
    tween.Completed:Once(function() done = true end)
    local t0 = os.clock()
    while not done and (os.clock() - t0) < (dur + 0.6) do
        if STATE.stop or not root.Parent or not roundActive or not STATE.farm then break end
        pin(root)                 -- ล้างความเร็ว = จอไม่สั่น
        RunService.Heartbeat:Wait()
    end
    pcall(function() tween:Cancel() end)
    -- หน่วงบนเหรียญ (ตรึงตำแหน่งให้เก็บครบ)
    local d0 = os.clock()
    while (os.clock() - d0) < STATE.dwell do
        if STATE.stop or not root.Parent then break end
        root.CFrame = CFrame.new(pos)
        pin(root)
        RunService.Heartbeat:Wait()
    end
end

--==================== HORST REPORT (เงิน/เวลา/หอย) ====================--
-- ส่งรายงานเข้าระบบ Horst | ห้ามใช้ตัวอักษร  |  และ  ;  ใน description
-- ★ แจ้ง "เปลี่ยนไอดี/เสร็จ" ให้ทุกระบบที่มี (Horst + Masterp)
local function managerDone()
    pcall(function() if type(_G.Horst_AccountChangeDone) == "function" then _G.Horst_AccountChangeDone() end end)
    pcall(function() if type(_G.Masterp_Done) == "function" then _G.Masterp_Done() end end)
end

reportHorst = function(final)
    if not HORST_ENABLE then return end
    -- ต้องมีระบบใดระบบหนึ่งอย่างน้อย (Horst หรือ Masterp)
    local hasHorst   = type(_G.Horst_SetDescription) == "function"
    local hasMasterp = type(_G.Masterp_Description)   == "function"
    if not (hasHorst or hasMasterp) then return end
    if not dataReady then return end   -- ยังไม่ได้ค่าจริง อย่าส่ง 0 เข้าระบบ
    local coins  = getTotalCoins()
    local shells = getTotalShells()
    local level  = getLevel()
    -- ห้ามใช้  |  และ  ;  ในข้อความ (ใช้ , แทน) — ใช้ได้ทั้ง Horst และ Masterp
    local desc = string.format("💰 Coins %d , 🐚 Shells %d , ⭐ Level %d", coins, shells, level)
    if #obtainedSkins > 0 then
        desc = desc .. " , 🎁 " .. table.concat(obtainedSkins, " ")
    end
    -- Horst: รับ (desc, json)
    if hasHorst then
        local encoded
        pcall(function()
            encoded = HttpService:JSONEncode({
                Coins = coins, Shells = shells, Level = level,
                Skins = table.concat(obtainedSkins, ", "),
            })
        end)
        pcall(function() _G.Horst_SetDescription(desc, encoded) end)
    end
    -- Masterp: รับ desc อย่างเดียว (ข้อความซ้ำจะไม่อัพเดต เป็นเรื่องปกติ)
    if hasMasterp then
        pcall(function() _G.Masterp_Description(desc) end)
    end
    -- โหมด 1: เหรียญถึงเป้า -> แจ้งเสร็จทุกระบบ
    if HORST_DONE_COINS > 0 and not horstDoneSent and coins >= HORST_DONE_COINS then
        horstDoneSent = true
        managerDone()
    end
end

task.spawn(function()
    while not STATE.stop do
        pcall(function() reportHorst(false) end)
        task.wait(HORST_INTERVAL)
    end
end)

--==================== REJOIN (เร็วกว่า hop) ====================--
-- rejoin เข้าเซิร์ฟใหม่แบบสุ่ม -> ไวกว่า ไม่เจอ "server full" จากการเจาะเซิร์ฟ
local hopping = false
local function serverHop()
    if hopping then return end
    hopping = true
    STATE.farming = false
    STATE.status = "กระเป๋าเต็ม! กำลัง rejoin..."

    -- รายงาน Horst ก่อนออก (ถ้ามี)
    pcall(function() if reportHorst then reportHorst(true) end end)

    for i = 1, 5 do
        local ok = pcall(function()
            TeleportService:Teleport(game.PlaceId, player)
        end)
        if ok then return end
        task.wait(1.5)
    end
    hopping = false
end

--==================== FARM LOOP ====================--
-- สุ่มเลือกจากเหรียญใกล้สุดกี่อัน (กันหลาย client บินไปแย่งเหรียญอันเดียวกัน)
local SPREAD_PICK = cfg("Spread", 4)
-- กระเป๋าเต็ม 40 จะทำอะไร: "kill" = ฆ่าตัวเองเกิดใหม่เซิร์ฟเดิม (เร็วกว่า) | "rejoin" = ย้ายเซิร์ฟ
local FULL_ACTION = tostring(cfg("FullAction", "kill")):lower()
pcall(function() math.randomseed(math.floor(os.clock() * 1e6) + player.UserId) end)

task.spawn(function()
    local collected = {}
    while not STATE.stop do
        if not STATE.farm then
            STATE.farming = false ; STATE.status = "หยุด (ปิด Auto Farm)"
            task.wait(0.3) ; continue
        end
        if not amIPlaying() then
            STATE.farming = false ; collected = {} ; coinContainer = nil
            STATE.status = isWaiting() and "รอตาเล่น (ผู้ชม) - ยืนเฉย"
                or (roundActive and "รอลงแมพ..." or "ล็อบบี้ / พักรอบ - ยืนเฉย")
            task.wait(0.35) ; continue
        end

        if STATE.hop and isBagFull() then
            if FULL_ACTION == "rejoin" then
                serverHop() ; break
            else
                -- ฆ่าตัวเอง -> เกิดใหม่เซิร์ฟเดิม (กระเป๋ารีเซ็ตรอบใหม่) เร็วกว่ารีจอยน์
                STATE.farming = false
                STATE.status = "กระเป๋าเต็ม -> ฆ่าตัวเอง (เกิดใหม่)"
                pcall(function()
                    local c = player.Character
                    local h = c and c:FindFirstChildOfClass("Humanoid")
                    if h then h.Health = 0 ; h:ChangeState(Enum.HumanoidStateType.Dead) end
                    if c then c:BreakJoints() end
                end)
                task.wait(3)          -- รอตาย + เกิดใหม่
                collected = {}
                continue
            end
        end

        local char = player.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then task.wait(0.3) ; continue end

        STATE.farming = true

        -- รวมเหรียญที่เก็บได้ + ระยะ แล้วสุ่มจาก K อันใกล้สุด (กระจาย ไม่แย่งกัน)
        local avail = {}
        for _, c in ipairs(findCoins()) do
            if c.Parent and not collected[c] then
                avail[#avail + 1] = { c = c, d = (root.Position - c.Position).Magnitude }
            end
        end
        table.sort(avail, function(a, b) return a.d < b.d end)
        local best, bd = nil, math.huge
        if #avail > 0 then
            local k = math.clamp(SPREAD_PICK, 1, #avail)
            local pick = avail[math.random(1, k)]
            best, bd = pick.c, pick.d
        end

        if best and bd <= 600 then
            STATE.status = "กำลังเก็บ... " .. getCoinCount() .. "/" .. STATE.target
            glideTo(root, best.Position)
            collected[best] = true
        else
            for k in pairs(collected) do if not k.Parent then collected[k] = nil end end
            STATE.farming = false
            STATE.status  = "รอเหรียญ... " .. getCoinCount() .. "/" .. STATE.target
            task.wait(0.4)
        end
    end
    STATE.farming = false
end)

--==================== AUTO CLAIM (รางวัล Shells ฯลฯ) ====================--
-- ป๊อปอัพ NewItem เป็นฝั่ง client ล้วน มีคิวหลายชิ้น -> ยิง Activated วนจนหมดคิว
task.spawn(function()
    while not STATE.stop do
        if STATE.claim then
            pcall(function()
                local cp  = player.PlayerGui:FindFirstChild("CrossPlatform")
                local ni  = cp and cp:FindFirstChild("NewItem")
                local med = ni and ni:FindFirstChild("Medium")
                local con = med and med:FindFirstChild("Container")
                local btn = con and con:FindFirstChild("Claim")
                if med and med.Visible and btn then
                    -- นับ Shells จากรางวัลที่กำลังโชว์ (best-effort)
                    pcall(function()
                        local item = med.Container and med.Container:FindFirstChild("NewItem")
                        local nameLbl = item and item:FindFirstChild("ItemName")
                        nameLbl = nameLbl and nameLbl:FindFirstChildWhichIsA("TextLabel")
                        if item and nameLbl and nameLbl.Text:lower():find("shell") then
                            local amt = 1
                            for _, l in ipairs(item:GetDescendants()) do
                                if l:IsA("TextLabel") then
                                    local num = l.Text:match("x?(%d+)")
                                    if num and (l.Name:lower():find("amount") or l.Text:lower():find("x")) then
                                        amt = tonumber(num) ; break
                                    end
                                end
                            end
                            local sig = nameLbl.Text .. "_" .. tostring(amt)
                            if sig ~= lastShellSig then
                                lastShellSig = sig
                                session.shells = session.shells + amt
                            end
                        end
                    end)
                    local conns = getconnections(btn.Activated)
                    for _, c in ipairs(conns) do c:Fire() end
                end
            end)
        end
        task.wait(0.25)
    end
end)

--==================== CRATE OPENERS (เปิดตอนพักรอบเท่านั้น) ====================--
-- โหมด 2: กล่องโกลด์ (เหรียญ)  | โหมด 3: กล่อง Summer (เปลือกหอย/Shells)
local OPEN_GOLD     = cfg("OpenCrates", false)
local GOLD_CRATES   = cfg("Crates", {})
local GOLD_AMOUNT   = cfg("OpenAmount", 1)
local GOLD_MAX      = cfg("OpenMax", 0)
local GOLD_NEED     = cfg("CratesNeed", 0)      -- เหรียญครบเท่านี้ค่อยเริ่มเปิด (0=เปิดเลย)

local OPEN_SUMMER   = cfg("OpenSummer", false)
local SUMMER_AMOUNT = cfg("SummerAmount", 1)
local SUMMER_MAX    = cfg("SummerMax", 0)
local SUMMER_NEED   = cfg("SummerNeed", 240)    -- หอยครบเท่านี้ค่อยเริ่มเปิด
local TARGET_SKINS  = cfg("TargetSkins", {})

-- rarity ที่ถือว่า "ของดี" (log เฉพาะพวกนี้)
local NOTABLE = { Legendary = true, Godly = true, Unique = true, Ancient = true }
do
    local extra = cfg("LogRarities", nil)
    if type(extra) == "table" then NOTABLE = {} for _, r in ipairs(extra) do NOTABLE[tostring(r)] = true end end
end

-- ข้อมูลอาวุธ (id -> {Rarity, ItemName}) ดึงจาก BoxModule
local WEAPONS
pcall(function()
    local m = require(game.ReplicatedStorage.Modules.BoxModule)
    WEAPONS = debug.getupvalues(m.OpenBox)[3].Weapons
end)

local function addSkin(text)
    for _, s in ipairs(obtainedSkins) do if s == text then return end end
    obtainedSkins[#obtainedSkins + 1] = text
    if #obtainedSkins > 15 then table.remove(obtainedSkins, 1) end
end

-- res มี target ไหม (recursive)
local function resHasTarget(res, targets)
    if type(targets) ~= "table" or #targets == 0 then return nil end
    local found
    local function scan(v, depth)
        if depth > 6 or found then return end
        local t = type(v)
        if t == "string" then
            for _, tgt in ipairs(targets) do
                if v == tostring(tgt) or v:find(tostring(tgt), 1, true) then found = v ; return end
            end
        elseif t == "table" then
            for k, vv in pairs(v) do scan(k, depth + 1) ; scan(vv, depth + 1) end
        end
    end
    pcall(function() scan(res, 0) end)
    return found
end

-- สแกน res หาไอเทม -> log เฉพาะ rarity ของดี (Legendary/Godly)
local function logNotable(res)
    if not WEAPONS then return end
    local function scan(v, depth)
        if depth > 6 then return end
        local t = type(v)
        if t == "string" then
            local w = WEAPONS[v]
            if type(w) == "table" and w.Rarity and NOTABLE[tostring(w.Rarity)] then
                addSkin(tostring(w.ItemName) .. " [" .. tostring(w.Rarity) .. "]")
            end
        elseif t == "table" then
            for k, vv in pairs(v) do scan(k, depth + 1) ; scan(vv, depth + 1) end
        end
    end
    pcall(function() scan(res, 0) end)
end

-- ตัวเปิดกล่องทั่วไป
--   needAmount + currencyFn -> รอสะสมเงิน/หอยให้ครบก่อนเริ่มเปิด
--   changeWhenBroke -> เปิดไม่ได้ติดกัน (เงิน/หอยหมด) = เปลี่ยนไอดี
local function runOpener(boxes, amount, maxOpen, targets, label, changeWhenBroke, needAmount, currencyFn, currency)
    task.spawn(function()
        local rf
        pcall(function() rf = game.ReplicatedStorage.Remotes.Shop:FindFirstChild("OpenCrate") end)
        if not rf then return end
        local opened, done, fails, low = 0, false, 0, 0
        local need = tonumber(needAmount) or 0
        local function changeId(reason)
            done = true
            STATE.status = reason
            managerDone()   -- แจ้งเสร็จทั้ง Horst + Masterp
        end
        while not STATE.stop and not done do
            if amIPlaying() then          -- กำลังเล่นเก็บเหรียญจริง = ยังไม่เปิด (กันชนกับฟาร์ม)
                task.wait(1)               -- ตอนพักรอบ/ล็อบบี้/รอตาเล่น(ผู้ชม) = เปิดได้เลย
            elseif need > 0 and opened == 0 and ((currencyFn and currencyFn()) or 0) < need then
                -- ★ บัญชีสด/ยังไม่เคยเปิด + หอย/เงินยังไม่ถึงเกณฑ์เริ่มเปิด (need)
                --   = กำลัง "สะสม" -> รอเรื่อยๆ ไม่เปลี่ยนไอดีทิ้ง
                --   (แก้บั๊ก: เลเวล 1 หอย 0 แล้วโดนเปลี่ยนไอดีทันที)
                --   หมายเหตุ: need คุมแค่ "การเปิดครั้งแรก" เท่านั้น พอเริ่มเปิดแล้ว
                --   จะเปิดรัวจนหอยไม่พอเปิดกล่อง แล้วค่อยเปลี่ยนไอดี (ผ่าน fails ด้านล่าง)
                local cur = (currencyFn and currencyFn()) or 0
                STATE.status = label .. " รอสะสมหอย " .. cur .. "/" .. need
                task.wait(3)
            else
                low = 0
                for _, box in ipairs(boxes) do
                    if STATE.stop or done or amIPlaying() then break end
                    if maxOpen > 0 and opened >= maxOpen then done = true ; break end
                    -- arg ที่ 3 = "สกุลเงิน" (Coins / SummerKey2026) | คืนค่า = item id (string) หรือ false
                    local ok, res = pcall(function() return rf:InvokeServer(box, "MysteryBox", currency) end)
                    if ok and res and res ~= false then
                        fails = 0
                        opened += 1
                        logNotable(res)     -- log เฉพาะของดี (Legendary/Godly)
                        STATE.status = "เปิด " .. label .. " (" .. opened .. ")"
                        -- อัปเดตเลขเงิน/หอยทันทีหลังเปิด (ไม่ต้องรอ refresher 6 วิ)
                        pcall(fetchProfile)
                        pcall(function() if reportHorst then reportHorst(false) end end)
                        local hit = resHasTarget(res, targets)
                        if hit then
                            local w = WEAPONS and WEAPONS[hit]
                            addSkin((w and tostring(w.ItemName) or tostring(hit)) .. " ★TARGET")
                            changeId("🎉 ได้เป้าหมาย -> เปลี่ยนไอดี")
                        end
                        task.wait(0.7)
                    else
                        fails += 1
                        -- ★ เปลี่ยนไอดี "เฉพาะตอนเคยเปิดไปแล้ว" (opened>0) = ใช้หอย/เงินหมดจริง
                        --   บัญชีสดที่ยังเปิดไม่ได้เลย จะไม่โดนเปลี่ยนไอดีทิ้ง (รอสะสมต่อ)
                        if changeWhenBroke and fails >= 5 and opened > 0 then
                            changeId(label .. " หมด (เปิดไป " .. opened .. ") -> เปลี่ยนไอดี")
                        elseif opened == 0 then
                            STATE.status = label .. " รอสะสมหอย (ยังเปิดไม่ได้)"
                        end
                        task.wait(0.7)
                    end
                end
                task.wait(0.5)
            end
        end
    end)
end

-- โหมด 2: กล่องโกลด์ (เหรียญ) — รอเหรียญครบ CratesNeed / หมดแล้วเปลี่ยนไอดี (ChangeAtCoinOut)
if OPEN_GOLD and type(GOLD_CRATES) == "table" and #GOLD_CRATES > 0 then
    runOpener(GOLD_CRATES, GOLD_AMOUNT, GOLD_MAX, {}, "กล่องโกลด์",
        cfg("ChangeAtCoinOut", true), GOLD_NEED, getTotalCoins, cfg("CratesCurrency", "Coins"))
end
-- โหมด 3: Summer (เปลือกหอย) — รอหอยครบ SummerNeed / หมดแล้วเปลี่ยนไอดี (ChangeAtShellOut)
if OPEN_SUMMER then
    runOpener({ "Summer2026Box" }, SUMMER_AMOUNT, SUMMER_MAX, TARGET_SKINS, "Summer",
        cfg("ChangeAtShellOut", true), SUMMER_NEED, getTotalShells, cfg("SummerCurrency", "SummerKey2026"))
end

--==================== AUTO PLAY (ข้ามหน้า "Joining a friend?") ====================--
local AUTO_PLAY = cfg("AutoPlay", true)

local function reallyVisible(g)
    local cur = g
    while cur and cur:IsA("GuiObject") do
        if not cur.Visible then return false end
        cur = cur.Parent
    end
    return true
end

-- ยิงปุ่มแบบครบทุกวิธี (บางปุ่ม connection=0 ต้องใช้ firesignal/VIM)
local function firePlay(btn)
    pcall(function() for _, c in ipairs(getconnections(btn.Activated)) do c:Fire() end end)
    pcall(function() for _, c in ipairs(getconnections(btn.MouseButton1Click)) do c:Fire() end end)
    pcall(function() firesignal(btn.MouseButton1Click) end)
    pcall(function() firesignal(btn.Activated) end)
    -- คลิกจริงด้วย VirtualInputManager (เผื่อปุ่มไม่มี connection ให้ยิง)
    pcall(function()
        local vim = game:GetService("VirtualInputManager")
        local p, s = btn.AbsolutePosition, btn.AbsoluteSize
        local x, y = p.X + s.X / 2, p.Y + s.Y / 2 + 36
        vim:SendMouseButtonEvent(x, y, 0, true, game, 0)
        vim:SendMouseButtonEvent(x, y, 0, false, game, 0)
    end)
end

-- เมนู "Joining a friend?" = PlayerGui.Join.Friends  (ปุ่มใหญ่ = Join.Friends.Play)
task.spawn(function()
    while not STATE.stop do
        if AUTO_PLAY then
            pcall(function()
                local join = player.PlayerGui:FindFirstChild("Join")
                local fr = join and join:FindFirstChild("Friends")
                if fr and fr.Visible then
                    local btn = fr:FindFirstChild("Play")
                    if btn and reallyVisible(btn) then firePlay(btn) end
                end
            end)
        end
        task.wait(0.25)
    end
end)

--==================== BOOST FPS + จอดำ (ประหยัด CPU/GPU/RAM) ====================--
local ULTRA_LITE   = cfg("UltraLite",      true)   -- เบาสุด (จอดำ + ลดกราฟิก) เปิดหลายจอ
local BOOST_FPS    = cfg("BoostFPS",       ULTRA_LITE)  -- ลดกราฟิก/ปิดเอฟเฟกต์
local BLACK_SCREEN = cfg("BlackScreen",    ULTRA_LITE)  -- ปิดเรนเดอร์ 3D (จอดำ)
local BLACK_KEY    = cfg("BlackScreenKey", "RightShift") -- ปุ่มเปิด/ปิดจอดำ
local LOCK_FPS     = cfg("LockFPS", cfg("lockfps", 0))   -- จำกัด FPS (0=ไม่จำกัด, เช่น 5 = เบามาก)

local Lighting = game:GetService("Lighting")

-- ปิดเอฟเฟกต์/เท็กซ์เจอร์ราย instance
local function stripInst(v)
    if not BOOST_FPS then return end
    pcall(function()
        if v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Smoke") or v:IsA("Fire")
        or v:IsA("Sparkles") or v:IsA("Beam") then
            v.Enabled = false
        elseif v:IsA("Decal") or v:IsA("Texture") then
            v.Transparency = 1
        elseif v:IsA("SpecialMesh") then
            v.TextureId = ""
        elseif v:IsA("BasePart") then
            v.Material = Enum.Material.SmoothPlastic
            v.Reflectance = 0
            v.CastShadow = false
        end
    end)
end

local function applyBoost()
    if not BOOST_FPS then return end
    -- กราฟิกต่ำสุด
    pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
    pcall(function() sethiddenproperty(settings().Rendering, "QualityLevel", 1) end)
    -- แสง/เงา
    pcall(function()
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 1e9
        Lighting.ShadowSoftness = 0
    end)
    for _, v in ipairs(Lighting:GetChildren()) do
        if v:IsA("PostEffect") or v:IsA("Atmosphere") or v:IsA("Clouds") or v:IsA("Sky") then
            pcall(function() v.Enabled = false end)
        end
    end
    -- น้ำ/พื้นผิว terrain
    local ter = workspace:FindFirstChildOfClass("Terrain")
    if ter then
        pcall(function()
            ter.WaterWaveSize = 0 ; ter.WaterWaveSpeed = 0
            ter.WaterReflectance = 0 ; ter.WaterTransparency = 1 ; ter.Decoration = false
        end)
    end
    -- กวาดของที่มีอยู่ (แบ่งเป็นชุด กันเครื่องกระตุก) + ของที่เกิดใหม่
    task.spawn(function()
        local n = 0
        for _, v in ipairs(game:GetDescendants()) do
            stripInst(v) ; n += 1
            if n % 400 == 0 then task.wait() end
        end
    end)
    game.DescendantAdded:Connect(stripInst)
end

-- จอดำ: ปิดเรนเดอร์ 3D (ประหยัดสุด) + ม่านดำสำรอง
local blackOn = false
local blackGui
local function setBlack(on)
    blackOn = on
    pcall(function() game:GetService("RunService"):Set3dRenderingEnabled(not on) end)
    if on then
        if not blackGui then
            blackGui = Instance.new("ScreenGui")
            blackGui.Name = "VCPP_Black" ; blackGui.IgnoreGuiInset = true
            blackGui.ResetOnSpawn = false ; blackGui.DisplayOrder = 9999
            pcall(function() blackGui.Parent = gethui and gethui() or game:GetService("CoreGui") end)
            if not blackGui.Parent then blackGui.Parent = player:WaitForChild("PlayerGui") end
            local f = Instance.new("Frame")
            f.Size = UDim2.fromScale(1, 1) ; f.BackgroundColor3 = Color3.new(0, 0, 0)
            f.BorderSizePixel = 0 ; f.Parent = blackGui
            local t = Instance.new("TextLabel")
            t.Size = UDim2.new(1, 0, 0, 16) ; t.Position = UDim2.new(0, 0, 1, -22)
            t.BackgroundTransparency = 1 ; t.Font = Enum.Font.Gotham ; t.TextSize = 11
            t.TextColor3 = Color3.fromRGB(70, 70, 88)
            t.Text = "กด " .. BLACK_KEY .. " เปิดจอ"
            t.Parent = f
        end
        blackGui.Enabled = true
    elseif blackGui then
        blackGui.Enabled = false
    end
end

do
    local ke = toKeyCode(BLACK_KEY)
    if ke then
        UserInput.InputBegan:Connect(function(input, gp)
            if gp then return end
            if input.KeyCode == ke then setBlack(not blackOn) end
        end)
    end
end

task.spawn(function()
    pcall(function() if LOCK_FPS and LOCK_FPS > 0 and setfpscap then setfpscap(LOCK_FPS) end end)
    applyBoost()
    if BLACK_SCREEN then task.wait(0.5) setBlack(true) end
end)

--==================== ปิดแชท + ANTI-AFK ====================--
local HIDE_CHAT = cfg("HideChat", true)   -- ปิด/ซ่อนช่องแชท + ปุ่มแชทบนบาร์
local ANTI_AFK  = cfg("AntiAFK",  true)   -- กันโดนเตะออกเพราะ AFK (ไม่ขยับ 20 นาที)

-- ปิดแชท (ทั้งระบบเก่า LegacyChat และ TextChatService ใหม่)
local function hideChat()
    if not HIDE_CHAT then return end
    pcall(function()
        game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false)
    end)
    -- TextChatService (แชทแบบใหม่) -> ปิด BubbleChat + ซ่อนหน้าต่างแชท
    pcall(function()
        local TCS = game:GetService("TextChatService")
        local wcw = TCS:FindFirstChild("ChatWindowConfiguration")
        if wcw then wcw.Enabled = false end
        local bcc = TCS:FindFirstChild("BubbleChatConfiguration")
        if bcc then bcc.Enabled = false end
    end)
    -- ซ่อน frame แชทใน PlayerGui (เผื่อยังโผล่)
    pcall(function()
        local cg = player:FindFirstChild("PlayerGui")
        for _, n in ipairs({ "Chat", "TextChat", "BubbleChat" }) do
            local g = cg and cg:FindFirstChild(n)
            if g then g.Enabled = false end
        end
    end)
end

do
    hideChat()
    -- แชทบางทีโหลดช้า/รีเซ็ตหลังเกิดใหม่ -> ปิดซ้ำเป็นระยะ
    task.spawn(function()
        for _ = 1, 10 do task.wait(1) hideChat() end
    end)
    if player.CharacterAdded then
        player.CharacterAdded:Connect(function() task.wait(1) hideChat() end)
    end
end

-- ANTI-AFK: พอ Roblox จะเตะเพราะ AFK -> ขยับ controller หลอกว่ายัง active
if ANTI_AFK then
    pcall(function()
        local VU = game:GetService("VirtualUser")
        player.Idled:Connect(function()
            pcall(function()
                VU:CaptureController()
                VU:ClickButton2(Vector2.new())
            end)
        end)
    end)
end

--=========================================================--
--                        GUI  (VC++ hub)
--=========================================================--
-- default = ปิด UI (ฟาร์ม+Horst ยังทำงานปกติ) | กด RightCtrl เรียกดูได้ | ตั้ง ShowUI=true ให้ขึ้นตลอด
local SHOW_UI    = cfg("ShowUI", false)
local TOGGLE_KEY = cfg("ToggleKey", "RightControl")

local ACCENT = Color3.fromRGB(168, 85, 247)
local BG     = Color3.fromRGB(24, 24, 30)
local BG2    = Color3.fromRGB(34, 34, 44)
local OFFCOL = Color3.fromRGB(60, 60, 72)
local TXT    = Color3.fromRGB(235, 235, 245)

local function corner(inst, r)
    local c = Instance.new("UICorner") ; c.CornerRadius = UDim.new(0, r or 8) ; c.Parent = inst
end
local function pad(inst, p)
    local u = Instance.new("UIPadding")
    u.PaddingLeft = UDim.new(0,p) u.PaddingRight = UDim.new(0,p)
    u.PaddingTop = UDim.new(0,p) u.PaddingBottom = UDim.new(0,p) u.Parent = inst
end

-- remove old
pcall(function()
    local old = (gethui and gethui() or game:GetService("CoreGui")):FindFirstChild("VenozHub")
    if old then old:Destroy() end
end)

local gui = Instance.new("ScreenGui")
gui.Name = "VenozHub"
gui.ResetOnSpawn = false
gui.Enabled = SHOW_UI            -- ปิด UI ได้จาก config (ShowUI=false)
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() gui.Parent = gethui and gethui() or game:GetService("CoreGui") end)
if not gui.Parent then gui.Parent = player:WaitForChild("PlayerGui") end

-- ปุ่มลัด เปิด/ปิด UI (default = RightControl)
do
    local keyEnum = toKeyCode(TOGGLE_KEY)
    if keyEnum then
        UserInput.InputBegan:Connect(function(input, gp)
            if gp then return end
            if input.KeyCode == keyEnum then gui.Enabled = not gui.Enabled end
        end)
    end
end
pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)

-- main window
local main = Instance.new("Frame")
main.Name = "Main"
main.Size = UDim2.new(0, 300, 0, 448)
main.Position = UDim2.new(0, 40, 0.5, -224)
main.BackgroundColor3 = BG
main.BorderSizePixel = 0
main.Active = true
main.Parent = gui
corner(main, 12)
local stroke = Instance.new("UIStroke")
stroke.Color = ACCENT ; stroke.Thickness = 1.5 ; stroke.Transparency = 0.3 ; stroke.Parent = main

-- title bar
local bar = Instance.new("Frame")
bar.Size = UDim2.new(1, 0, 0, 40)
bar.BackgroundColor3 = BG2
bar.BorderSizePixel = 0
bar.Parent = main
corner(bar, 12)
local barFix = Instance.new("Frame")
barFix.Size = UDim2.new(1,0,0,14) barFix.Position = UDim2.new(0,0,1,-14)
barFix.BackgroundColor3 = BG2 barFix.BorderSizePixel = 0 barFix.Parent = bar

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, -80, 1, 0)
title.Position = UDim2.new(0, 14, 0, 0)
title.Font = Enum.Font.GothamBold
title.Text = "VC++ hub"
title.TextSize = 18
title.TextColor3 = TXT
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = bar
local dot = Instance.new("TextLabel")
dot.BackgroundTransparency = 1 ; dot.Size = UDim2.new(0,20,1,0) ; dot.Position = UDim2.new(0,0,0,0)
dot.Text = "" ; dot.Parent = bar

-- minimize button
local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 28, 0, 28) ; minBtn.Position = UDim2.new(1, -36, 0, 6)
minBtn.BackgroundColor3 = OFFCOL ; minBtn.Text = "—" ; minBtn.TextColor3 = TXT
minBtn.Font = Enum.Font.GothamBold ; minBtn.TextSize = 16 ; minBtn.Parent = bar
corner(minBtn, 6)

-- content holder
local body = Instance.new("Frame")
body.Size = UDim2.new(1, 0, 1, -40) ; body.Position = UDim2.new(0, 0, 0, 40)
body.BackgroundTransparency = 1 ; body.Parent = main
pad(body, 12)
local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 8) ; list.SortOrder = Enum.SortOrder.LayoutOrder ; list.Parent = body

-- toggle factory
local function makeToggle(text, key, order)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 40)
    btn.BackgroundColor3 = BG2 ; btn.AutoButtonColor = false
    btn.Text = "" ; btn.LayoutOrder = order ; btn.Parent = body
    corner(btn, 8)
    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1 ; lbl.Size = UDim2.new(1, -60, 1, 0) ; lbl.Position = UDim2.new(0, 12, 0, 0)
    lbl.Font = Enum.Font.GothamMedium ; lbl.Text = text ; lbl.TextSize = 14 ; lbl.TextColor3 = TXT
    lbl.TextXAlignment = Enum.TextXAlignment.Left ; lbl.Parent = btn
    local pill = Instance.new("Frame")
    pill.Size = UDim2.new(0, 40, 0, 22) ; pill.Position = UDim2.new(1, -52, 0.5, -11)
    pill.BackgroundColor3 = STATE[key] and ACCENT or OFFCOL ; pill.Parent = btn
    corner(pill, 11)
    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 18, 0, 18)
    knob.Position = STATE[key] and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9)
    knob.BackgroundColor3 = Color3.fromRGB(255,255,255) ; knob.Parent = pill
    corner(knob, 9)
    local function refresh()
        local on = STATE[key]
        TweenService:Create(pill, TweenInfo.new(0.15), {BackgroundColor3 = on and ACCENT or OFFCOL}):Play()
        TweenService:Create(knob, TweenInfo.new(0.15), {Position = on and UDim2.new(1,-20,0.5,-9) or UDim2.new(0,2,0.5,-9)}):Play()
    end
    btn.MouseButton1Click:Connect(function()
        STATE[key] = not STATE[key] ; refresh()
    end)
    return btn
end

makeToggle("Auto Farm เหรียญ", "farm",  1)
makeToggle("Auto Rejoin (เก็บครบ)", "hop", 2)
makeToggle("Auto Claim รางวัล", "claim", 3)
makeToggle("Noclip (ทะลุกำแพง)", "noclip",4)

-- number input factory
local function makeInput(text, key, order)
    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1, 0, 0, 40) ; holder.BackgroundColor3 = BG2
    holder.LayoutOrder = order ; holder.Parent = body
    corner(holder, 8)
    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1 ; lbl.Size = UDim2.new(1, -80, 1, 0) ; lbl.Position = UDim2.new(0, 12, 0, 0)
    lbl.Font = Enum.Font.GothamMedium ; lbl.Text = text ; lbl.TextSize = 14 ; lbl.TextColor3 = TXT
    lbl.TextXAlignment = Enum.TextXAlignment.Left ; lbl.Parent = holder
    local box = Instance.new("TextBox")
    box.Size = UDim2.new(0, 56, 0, 26) ; box.Position = UDim2.new(1, -66, 0.5, -13)
    box.BackgroundColor3 = BG ; box.Text = tostring(STATE[key]) ; box.TextColor3 = ACCENT
    box.Font = Enum.Font.GothamBold ; box.TextSize = 14 ; box.ClearTextOnFocus = false ; box.Parent = holder
    corner(box, 6)
    box.FocusLost:Connect(function()
        local v = tonumber(box.Text)
        if v then STATE[key] = v else box.Text = tostring(STATE[key]) end
    end)
    return holder
end

makeInput("ความเร็ว (Speed)", "speed",  5)
makeInput("เป้าเหรียญ (Target)", "target", 6)

-- status
local statusFrame = Instance.new("Frame")
statusFrame.Size = UDim2.new(1, 0, 0, 44) ; statusFrame.BackgroundColor3 = BG2 ; statusFrame.LayoutOrder = 7 ; statusFrame.Parent = body
corner(statusFrame, 8)
local statusLbl = Instance.new("TextLabel")
statusLbl.BackgroundTransparency = 1 ; statusLbl.Size = UDim2.new(1, -20, 1, 0) ; statusLbl.Position = UDim2.new(0, 10, 0, 0)
statusLbl.Font = Enum.Font.GothamMedium ; statusLbl.Text = "..." ; statusLbl.TextSize = 12.5
statusLbl.TextColor3 = Color3.fromRGB(180, 180, 200) ; statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.TextWrapped = true ; statusLbl.Parent = statusFrame

-- log (เงิน / หอย / เวลา)
local logFrame = Instance.new("Frame")
logFrame.Size = UDim2.new(1, 0, 0, 44) ; logFrame.BackgroundColor3 = BG2 ; logFrame.LayoutOrder = 8 ; logFrame.Parent = body
corner(logFrame, 8)
local logStripe = Instance.new("Frame")
logStripe.Size = UDim2.new(0, 3, 1, -12) ; logStripe.Position = UDim2.new(0, 6, 0, 6)
logStripe.BackgroundColor3 = ACCENT ; logStripe.BorderSizePixel = 0 ; logStripe.Parent = logFrame
corner(logStripe, 2)
local logLbl = Instance.new("TextLabel")
logLbl.BackgroundTransparency = 1 ; logLbl.Size = UDim2.new(1, -22, 1, 0) ; logLbl.Position = UDim2.new(0, 16, 0, 0)
logLbl.Font = Enum.Font.GothamMedium ; logLbl.Text = "..." ; logLbl.TextSize = 12.5
logLbl.TextColor3 = TXT ; logLbl.TextXAlignment = Enum.TextXAlignment.Left ; logLbl.TextWrapped = true ; logLbl.Parent = logFrame

-- credit
local credit = Instance.new("TextLabel")
credit.BackgroundTransparency = 1 ; credit.Size = UDim2.new(1, 0, 0, 14) ; credit.LayoutOrder = 9
credit.Font = Enum.Font.Gotham ; credit.Text = "VC++ hub • MM2" ; credit.TextSize = 10
credit.TextColor3 = Color3.fromRGB(120, 120, 140) ; credit.Parent = body

-- status + log updater
task.spawn(function()
    while gui.Parent and not STATE.stop do
        statusLbl.Text = "● " .. tostring(STATE.status) .. "  •  กระเป๋า " .. getCoinCount() .. "/" .. STATE.target
        logLbl.Text = string.format("💰 %d   🐚 %d   ⭐ Lv %d", getTotalCoins(), getTotalShells(), getLevel())
        task.wait(0.5)
    end
end)

-- minimize
local minimized = false
minBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    body.Visible = not minimized
    TweenService:Create(main, TweenInfo.new(0.2), {Size = minimized and UDim2.new(0,300,0,40) or UDim2.new(0,300,0,448)}):Play()
    minBtn.Text = minimized and "+" or "—"
end)

-- dragging (mouse + touch)
do
    local dragging, dragStart, startPos
    local function begin(input)
        dragging = true ; dragStart = input.Position ; startPos = main.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
    bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            begin(input)
        end
    end)
    UserInput.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

-- intro pop
main.Size = UDim2.new(0, 300, 0, 0)
TweenService:Create(main, TweenInfo.new(0.3, Enum.EasingStyle.Back), {Size = UDim2.new(0, 300, 0, 448)}):Play()

--=========================================================--
--                  INFO PANEL (สไตล์ DuckHub)
--=========================================================--
local INFO_PANEL = cfg("ShowInfo", cfg("InfoPanel", true))   -- ข้อความสถานะกลางจอ (Phase/Role/Map/Coin/Bag/Total/Shells)
local INFO_TITLE = cfg("InfoTitle", "VC++ Hub")
local INFO_SUB   = cfg("InfoSub", "discord.gg/vcpp")

-- Role / Dead จากข้อมูลรอบ (getgc) — รีเฟรชทุก 4 วิ
local infoRole, infoDead = "-", false
task.spawn(function()
    while not STATE.stop do
        pcall(function()
            local uid = player.UserId
            local found = false
            for _, o in ipairs(getgc(true)) do
                if type(o) == "table" and rawget(o, "UserId") == uid and rawget(o, "Role") ~= nil then
                    infoRole = tostring(rawget(o, "Role"))
                    infoDead = rawget(o, "Dead") and true or false
                    found = true ; break
                end
            end
            if not found then infoRole = "-" ; infoDead = false end
        end)
        task.wait(4)
    end
end)

local function getMapName()
    local m = "-"
    pcall(function()
        for _, d in ipairs(workspace:GetChildren()) do
            if d:IsA("Model") and d.Name ~= "Lobby" and d:FindFirstChild("CoinContainer") then
                m = d.Name ; break
            end
        end
    end)
    return m
end

local function getPhase()
    if infoDead then return "DEAD" end
    local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health <= 0 then return "DEAD" end
    if roundActive then return "ALIVE" end
    return "LOBBY"
end

if INFO_PANEL then
    local igui = Instance.new("ScreenGui")
    igui.Name = "VCPP_Info" ; igui.ResetOnSpawn = false ; igui.DisplayOrder = 10000  -- เหนือจอดำ
    pcall(function() igui.Parent = gethui and gethui() or game:GetService("CoreGui") end)
    if not igui.Parent then igui.Parent = player:WaitForChild("PlayerGui") end

    -- ข้อความล้วน (text overlay) ไม่มีกล่อง/หัว/ลาก
    local txt = Instance.new("TextLabel")
    txt.Name = "Info"
    txt.BackgroundTransparency = 1
    txt.AnchorPoint = Vector2.new(0.5, 0.5)
    txt.Size = UDim2.new(0, 520, 0, 200)
    txt.Position = UDim2.new(0.5, 0, 0.5, 0)   -- กลางจอ
    txt.Font = Enum.Font.GothamBold
    txt.TextSize = 18
    txt.RichText = true
    txt.TextXAlignment = Enum.TextXAlignment.Center
    txt.TextYAlignment = Enum.TextYAlignment.Center
    txt.TextColor3 = Color3.fromRGB(235, 235, 245)
    txt.TextStrokeTransparency = 0.35   -- อ่านง่ายบนพื้นใดๆ
    txt.LineHeight = 1.25
    txt.Text = ""
    txt.Parent = igui

    local function col(c, s) return "<font color='#" .. c .. "'>" .. s .. "</font>" end
    task.spawn(function()
        while igui.Parent and not STATE.stop do
            local bag = getCoinCount()
            local full = isBagFull()
            local total = getTotalCoins()
            local shells = getTotalShells()
            local phase = getPhase()
            local phaseC = (phase == "DEAD") and "ff5555" or (phase == "ALIVE") and "51cf66" or "adb5bd"
            local active = STATE.farming
            txt.Text =
                col("b877ff", INFO_TITLE) .. "  " .. col("8891ff", INFO_SUB) .. "\n"
                .. "🩸 Phase: " .. col(phaseC, phase) .. "   👤 Role: " .. col("ffffff", infoRole) .. "\n"
                .. "🗺️ Map: " .. col("e9ecef", getMapName()) .. "\n"
                .. "🪙 Coin: " .. col("ffd43b", bag .. "/" .. STATE.target) .. "   "
                    .. (active and col("51cf66", "✓ Active") or col("868e96", "○ Idle")) .. "\n"
                .. "🎒 Bag: " .. (full and col("ff922b", "FULL") or col("51cf66", "OK"))
                    .. "   🪙 Total: " .. col("ffd43b", tostring(total)) .. " " .. col("868e96", "(+" .. bag .. ")") .. "\n"
                .. "🐚 Shells: " .. col("f783ac", tostring(shells))
            task.wait(0.4)
        end
    end)
end

print("[VC++ hub] โหลดสำเร็จ! ฟาร์มเฉพาะตอนถึงตาเราเล่นจริง")
