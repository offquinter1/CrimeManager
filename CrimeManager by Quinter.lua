script_name('CrimeManager')
script_author('Dima Quinter')
require("lib.moonloader")
local inicfg = require('inicfg')
local imgui = require("imgui")
imgui.HotKey = require('imgui_addons').HotKey
local encoding = require('encoding')
encoding.default = 'CP1251'
u8 = encoding.UTF8
local sampev = require('samp.events')
local ffi = require('ffi')
local memory = require('memory')

-- ========== FFI ==========
ffi.cdef[[
struct stKillEntry {
    char szKiller[25];
    char szVictim[25];
    uint32_t clKillerColor;
    uint32_t clVictimColor;
    uint8_t byteType;
} __attribute__ ((packed));

struct stKillInfo {
    int iEnabled;
    struct stKillEntry killEntry[5];
    int iLongestNickLength;
    int iOffsetX;
    int iOffsetY;
    void *pD3DFont;
    void *pWeaponFont1;
    void *pWeaponFont2;
    void *pSprite;
    void *pD3DDevice;
    int iAuxFontInited;
    void *pAuxFont1;
    void *pAuxFont2;
} __attribute__ ((packed));

struct stGangzone {
    float fPosition[4];
    uint32_t dwColor;
    uint32_t dwAltColor;
};

struct stGangzonePool {
    struct stGangzone *pGangzone[1024];
    int iIsListed[1024];
};
]]

-- ========== ������� ������� ==========
local function encodeKey(t)
    if type(t) ~= "table" then return "" end
    return tostring(t[1] or 0)
end

local function decodeKey(s)
    local num = tonumber(s)
    if num and num > 0 then return { num } else return {} end
end

local function utf8toCp1251(str) return str ~= "" and u8:decode(str) or "" end
local function cp1251toUtf8(str) return str ~= "" and u8(str) or "" end

local path_ini = '..\\config\\CrimeManager.ini'

-- ========== ������������� INI ==========
local mainIni = inicfg.load({
    maincfg = {
        deletekiy=false, smskontr=false, uvedkontr=false, autobar=false, admcopyid=false,
        autom4g=false,
        automget="bget",
        captureEnabled=false, captureCommand="/capture", captureKey=0, captureDelay=650,
        sellGunWeapon=0, sellGunAmmo=50, sellGunPrice=5,
        sellDrugsGrams=25, sellDrugsPrice=25,
        autoleech=false,
        fastMaskEnabled=false,
        fastMaskCommand="/fmask",
        autogiverank=false,
        giverankValue=6,
        showKillIds=false,
        autoWarehouseEnabled=false,
        warehouseTriggerWord="exorcist wl",
        warehouseCommand="/warelock",
        warehouseDelay=5,
        autoFixcarEnabled=false,
        fixcarTriggerWord="exorcist ffix",
        fixcarCommand="/ffixcar",
        frangEnabled=true,
        frangCommand="frang",
        mafiaDelivery=false,
        matsput_enabled=false,
        matsput_cmd="lsa",
        matsput_delay=1000,
        hideFamilyEvent=false,
        ammo_enabled=false,
        ammo_x=550,
        ammo_y=550,
        ammo_size=9,
        ammo_timers={},
        bank_enabled=false,
        bank_x=10,
        bank_y=600,
        bank_size=10,
        bank_ls=0,
        bank_sf=0,
        bank_lv=0,
        zone_enabled=false,
        zone_x=10,
        zone_y=50,
        zone_size=12,
    },
    weather_commands = {
        enabled = true,
        stime_cmd = "stime",
        sweat_cmd = "sweat",
        btime_cmd = "btime",
        bweat_cmd = "bweat",
        time_locked = false,
        locked_time = 0,
        weather_locked = false,
        locked_weather = 0,
    },
    binders={}
}, path_ini) or {}

if type(mainIni.maincfg.ammo_timers) ~= "table" then
    mainIni.maincfg.ammo_timers = {}
end

-- ========== ���������� ������ ==========
local sw, sh = getScreenResolution()
local data = {
    sw = sw, sh = sh;
    activeautoload = false;
    proccesautoload = false;
    admids = "";
    health = nil;
    offmembers = {};
    offmembersrangs = {};
    ghettoMembers = {};
    ghettoRangs = {};
    mafiaMembers = {};
    mafiaRangs = {};
    familyMembers = {};
    waitingForFamily = false;
    captureActive = false;
    captureFloodThread = nil;
    recording_binder_idx = nil;
    recording_start_time = 0;
    lastUPress = 0;
    uPressCount = 0;
    wasDead = false;
    mask_equipped = false;
    fmask_active = false;
    mask_found = false;
    fastMaskRegisteredCmd = "";
    killInfoPtr = nil;
    time_locked = false;
    weather_locked = false;
    locked_time = nil;
    locked_weather = nil;
    default_patch = nil;
    lastCaptureKeyState = false;
    warehouseThreadActive = false;
    awaitingRespawnMessage = false;
    isCheckingFamily = false;
    collectingMembers = false;
    membersList = {};
    frangRegisteredCmd = "";
    collectingFor = nil;
    collectTimer = nil;
    selectedFaction = "bikers";
    matsputActive = false;
    matsputThread = nil;
    matsputRegisteredCmd = "";
    ammo_in_biz = "";
    ammo_font = nil;
    houseLineEnabled = false;
    houseLineActivated = false;
    houseLinePickups = {};
    bank_timers = {
        LS = mainIni.maincfg.bank_ls or 0,
        SF = mainIni.maincfg.bank_sf or 0,
        LV = mainIni.maincfg.bank_lv or 0,
    },
    bank_font = nil,
    zone_gangzones = {},
    zone_flashing = {},
    zone_font = nil,
    _zoneLoadAttempt = 0,
    drag_mode = false,
    drag_type = nil,
    drag_saved_x = 0,
    drag_saved_y = 0,
}

if mainIni.weather_commands.time_locked then
    data.time_locked = true
    data.locked_time = mainIni.weather_commands.locked_time
end
if mainIni.weather_commands.weather_locked then
    data.weather_locked = true
    data.locked_weather = mainIni.weather_commands.locked_weather
end

-- ========== AMMO ==========
local ammo_biz_names = {
    ammols = "LS",
    ammosf = "SF",
    ammolv = "LV",
}
local ammo_biz_map = {
    LS = "ammols",
    SF = "ammosf",
    LV = "ammolv",
}
local ammo_business = {
    ammols = {x = 1366.6401367188, y = -1279.4899902344, z = 13.546875, group = 'ammo'},
    ammosf = {x = -2626.4050292969, y = 210.6088104248, z = 4.6033186912537, group = 'ammo'},
    ammolv = {x = 2158.3286132813, y = 943.17541503906, z = 10.371940612793, group = 'ammo'},
}
local ammo_list = {"ammols", "ammosf", "ammolv"}
local ammo_timers = {}
for _, biz in ipairs(ammo_list) do
    ammo_timers[biz] = mainIni.maincfg.ammo_timers[biz] or 0
end

-- ========== UI ==========
local ui = {
    main_window = imgui.ImBool(false);
    familyInput = imgui.ImBuffer("", 4096);
    activeTab = 1;
    deletekiy = imgui.ImBool(mainIni.maincfg.deletekiy);
    smskontr = imgui.ImBool(mainIni.maincfg.smskontr);
    uvedkontr = imgui.ImBool(mainIni.maincfg.uvedkontr);
    autobar = imgui.ImBool(mainIni.maincfg.autobar);
    admcopyid = imgui.ImBool(mainIni.maincfg.admcopyid);
    autom4g = imgui.ImBool(mainIni.maincfg.autom4g);
    captureEnabled = imgui.ImBool(mainIni.maincfg.captureEnabled);
    automget = imgui.ImBuffer(u8(mainIni.maincfg.automget), 265);
    captureCommand = imgui.ImBuffer(mainIni.maincfg.captureCommand, 128);
    captureDelay = imgui.ImInt(mainIni.maincfg.captureDelay);
    captureHotkey = { v = { mainIni.maincfg.captureKey } };
    sellGunWeapon = mainIni.maincfg.sellGunWeapon or 0;
    sellGunAmmo = mainIni.maincfg.sellGunAmmo or 50;
    sellGunPrice = mainIni.maincfg.sellGunPrice or 5;
    sellDrugsGrams = mainIni.maincfg.sellDrugsGrams or 25;
    sellDrugsPrice = mainIni.maincfg.sellDrugsPrice or 25;
    autoleech = imgui.ImBool(mainIni.maincfg.autoleech or false);
    fastMaskEnabled = imgui.ImBool(mainIni.maincfg.fastMaskEnabled or false);
    fastMaskCommand = imgui.ImBuffer(mainIni.maincfg.fastMaskCommand or "/fmask", 32);
    autogiverank = imgui.ImBool(mainIni.maincfg.autogiverank or false);
    giverankValue = imgui.ImInt(mainIni.maincfg.giverankValue or 6);
    showKillIds = imgui.ImBool(mainIni.maincfg.showKillIds or false);
    weather_enabled = imgui.ImBool(mainIni.weather_commands.enabled);
    stime_cmd = imgui.ImBuffer(mainIni.weather_commands.stime_cmd, 32);
    sweat_cmd = imgui.ImBuffer(mainIni.weather_commands.sweat_cmd, 32);
    btime_cmd = imgui.ImBuffer(mainIni.weather_commands.btime_cmd, 32);
    bweat_cmd = imgui.ImBuffer(mainIni.weather_commands.bweat_cmd, 32);
    autoWarehouseEnabled = imgui.ImBool(mainIni.maincfg.autoWarehouseEnabled or false);
    warehouseTriggerWord = imgui.ImBuffer(mainIni.maincfg.warehouseTriggerWord or "exorcist wl", 64);
    warehouseCommand = imgui.ImBuffer(mainIni.maincfg.warehouseCommand or "/warelock", 32);
    warehouseDelay = imgui.ImInt(mainIni.maincfg.warehouseDelay or 5);
    autoFixcarEnabled = imgui.ImBool(mainIni.maincfg.autoFixcarEnabled or false);
    fixcarTriggerWord = imgui.ImBuffer(mainIni.maincfg.fixcarTriggerWord or "exorcist ffix", 64);
    fixcarCommand = imgui.ImBuffer(mainIni.maincfg.fixcarCommand or "/ffixcar", 32);
    frangEnabled = imgui.ImBool(mainIni.maincfg.frangEnabled ~= false);
    frangCommand = imgui.ImBuffer(mainIni.maincfg.frangCommand or "frang", 32);
    mafiaDelivery = imgui.ImBool(mainIni.maincfg.mafiaDelivery or false);
    matsputEnabled = imgui.ImBool(mainIni.maincfg.matsput_enabled or false);
    matsputCmd = imgui.ImBuffer(mainIni.maincfg.matsput_cmd or "lsa", 32);
    matsputDelay = imgui.ImInt(mainIni.maincfg.matsput_delay or 1000);
    hideFamilyEvent = imgui.ImBool(mainIni.maincfg.hideFamilyEvent or false);
    ammoEnabled = imgui.ImBool(mainIni.maincfg.ammo_enabled or false);
    ammoX = imgui.ImInt(mainIni.maincfg.ammo_x or 550);
    ammoY = imgui.ImInt(mainIni.maincfg.ammo_y or 550);
    ammoSize = imgui.ImInt(mainIni.maincfg.ammo_size or 9);
    bankEnabled = imgui.ImBool(mainIni.maincfg.bank_enabled or false),
    bankX = imgui.ImInt(mainIni.maincfg.bank_x or 10),
    bankY = imgui.ImInt(mainIni.maincfg.bank_y or 600),
    bankSize = imgui.ImInt(mainIni.maincfg.bank_size or 10),
    houseLineEnabled = imgui.ImBool(false);
    houseLinePassword = imgui.ImBuffer("", 32);
    zoneEnabled = imgui.ImBool(mainIni.maincfg.zone_enabled or false),
    zoneX = imgui.ImInt(mainIni.maincfg.zone_x or 10),
    zoneY = imgui.ImInt(mainIni.maincfg.zone_y or 50),
    zoneSize = imgui.ImInt(mainIni.maincfg.zone_size or 12),
}

local binders = {}

-- ========== ��������������� ������� ==========
local function keyCodeToName(code)
    if code == 0 or code == nil then return "�� ���������" end
    local keys = {
        [1]="LMB",[2]="RMB",[4]="MMB",[6]="XButton1",[7]="XButton2",
        [8]="Backspace",[9]="Tab",[13]="Enter",[27]="Esc",[32]="Space",
        [33]="PgUp",[34]="PgDn",[35]="End",[36]="Home",[37]="Left",[38]="Up",
        [39]="Right",[40]="Down",[45]="Insert",[46]="Delete",[44]="PrintScreen",
        [145]="ScrollLock",[19]="Pause",[112]="F1",[113]="F2",[114]="F3",[115]="F4",
        [116]="F5",[117]="F6",[118]="F7",[119]="F8",[120]="F9",[121]="F10",
        [122]="F11",[123]="F12",[96]="Num0",[97]="Num1",[98]="Num2",[99]="Num3",
        [100]="Num4",[101]="Num5",[102]="Num6",[103]="Num7",[104]="Num8",[105]="Num9",
        [106]="Num*",[107]="Num+",[109]="Num-",[111]="Num/",[110]="Num.",
        [160]="LShift",[161]="RShift",[162]="LCtrl",[163]="RCtrl",[164]="LAlt",[165]="RAlt",
        [91]="LWin",[92]="RWin",
    }
    if (code >= 65 and code <= 90) or (code >= 48 and code <= 57) then return string.char(code)
    elseif keys[code] then return keys[code] end
    return "?"
end

-- ========== ������ ==========
local function saveBindersToIni()
    if not mainIni then return end
    for k in pairs(mainIni.binders) do mainIni.binders[k] = nil end
    mainIni.binders.count = #binders
    for i, b in ipairs(binders) do
        mainIni.binders["key"..i] = b.keyCode or 0
        mainIni.binders["cmd"..i] = utf8toCp1251(b.command or "")
        mainIni.binders["active"..i] = b.active and 1 or 0
        mainIni.binders["flood"..i] = b.flood and 1 or 0
        mainIni.binders["interval"..i] = b.interval or 15
    end
    saveIniFile()
end

local function loadBindersFromIni()
    binders = {}
    if not mainIni.binders then mainIni.binders = {} return end
    local count = mainIni.binders.count or 0
    for i = 1, count do
        local keyCode = mainIni.binders["key"..i]
        local cmd = cp1251toUtf8(mainIni.binders["cmd"..i] or "")
        local active = mainIni.binders["active"..i] == 1
        local flood = mainIni.binders["flood"..i] == 1
        local interval = mainIni.binders["interval"..i] or 15
        if interval < 1 then interval = 1 end
        if interval > 120 then interval = 120 end
        binders[#binders+1] = {
            keyCode = (keyCode and keyCode ~= 0) and keyCode or 0,
            command = cmd,
            active = active,
            flood = flood,
            interval = interval,
            lastTriggerTick = 0,
            lastFloodTick = 0
        }
    end
end

local function addEmptyBinder()
    binders[#binders+1] = {keyCode=0, command="", active=true, flood=false, interval=15, lastTriggerTick=0, lastFloodTick=0}
    saveBindersToIni()
end

local function removeBinder(idx)
    table.remove(binders, idx)
    saveBindersToIni()
end

local function updateBinder(idx)
    saveBindersToIni()
end

local function startRecordingBinder(idx)
    data.recording_binder_idx = idx
    data.recording_start_time = os.clock()
    sampAddChatMessage("{008080}[CrimeManager] {ffffff}������� ����� ������� ��� ����������...", -1)
end

local function sendCommand(cmd)
    if cmd and cmd ~= "" then sampSendChat(utf8toCp1251(cmd)) end
end

local function processBinders()
    if data.isCheckingFamily then return end
    if sampIsChatInputActive() or sampIsDialogActive() or sampIsCursorActive() then return end
    if imgui.Process and imgui.IsAnyItemActive() then return end

    local currentTime = os.clock() * 1000
    for _, b in ipairs(binders) do
        if b.active then
            if b.keyCode ~= 0 and isKeyJustPressed(b.keyCode) and currentTime - (b.lastTriggerTick or 0) >= 300 then
                b.lastTriggerTick = currentTime
                sendCommand(b.command)
            end
            if b.flood and b.interval > 0 and currentTime - (b.lastFloodTick or 0) >= b.interval * 1000 then
                b.lastFloodTick = currentTime
                sendCommand(b.command)
            end
        end
    end
end

-- ========== ���� ����������� ==========
local function startCaptureFlood()
    if data.captureFloodThread then return end
    data.captureFloodThread = lua_thread.create(function()
        while data.captureActive do
            sampSendChat(ui.captureCommand.v)
            wait(ui.captureDelay.v)
        end
        data.captureFloodThread = nil
    end)
end

local function stopCaptureFlood()
    data.captureActive = false
    if data.captureFloodThread then
        data.captureFloodThread = nil
    end
end

local function toggleCaptureFlood()
    if not ui.captureEnabled.v then
        sampAddChatMessage("{008080}[CrimeManager] {ffffff}���������� �������� � ����������.", -1)
        return
    end
    data.captureActive = not data.captureActive
    if data.captureActive then
        startCaptureFlood()
        sampAddChatMessage("{008080}[CrimeManager] {ffffff}���������� ������� (�������: "..ui.captureCommand.v..", ��������: "..ui.captureDelay.v.." ��).", -1)
    else
        stopCaptureFlood()
        sampAddChatMessage("{008080}[CrimeManager] {ffffff}���������� ����������.", -1)
    end
end

-- ========== ���� /mats put ==========
local function startMatsPutFlood()
    if data.matsputThread then return end
    data.matsputThread = lua_thread.create(function()
        while data.matsputActive do
            sampSendChat("/mats put")
            wait(ui.matsputDelay.v)
        end
        data.matsputThread = nil
    end)
end

local function stopMatsPutFlood()
    data.matsputActive = false
    if data.matsputThread then
        data.matsputThread = nil
    end
end

local function toggleMatsPutFlood()
    if not ui.matsputEnabled.v then
        sampAddChatMessage("{008080}[CrimeManager] {ffffff}���� /mats put �������� � ����������.", -1)
        return
    end
    data.matsputActive = not data.matsputActive
    if data.matsputActive then
        startMatsPutFlood()
        sampAddChatMessage("{008080}[CrimeManager] {ffffff}���� /mats put ������� (��������: "..ui.matsputDelay.v.." ��).", -1)
    else
        stopMatsPutFlood()
        sampAddChatMessage("{008080}[CrimeManager] {ffffff}���� /mats put ����������.", -1)
    end
end

-- ========== ������� ����� ==========
local mask_models = {19036,19037,19038,18911,18912,18913,18914,18915,18916,18917,18918,18919,18920,11704}

local function fastmask_command_handler()
    if not ui.fastMaskEnabled.v then
        sampAddChatMessage("{008080}[CrimeManager] {ffffff}������� ����� ��������� � ����������.", -1)
        return
    end
    local server = sampGetCurrentServerName()
    if not server or not server:find('Evolve%-Rp%.Ru') then
        sampAddChatMessage("{008080}[CrimeManager] {ffffff}������� ����� ������ �� Evolve-Rp.", -1)
        return
    end
    if data.mask_equipped then
        sampSendChat("/mask")
        data.mask_equipped = false
        return
    end
    data.fmask_active = true
    data.mask_found = false
    sampSendChat('/items')
end

function sampev.onShowTextDraw(id, data_td)
    if not data.fmask_active then return true end
    local server = sampGetCurrentServerName()
    if not server or not server:find('Evolve%-Rp%.Ru') then return true end
    for _, model in ipairs(mask_models) do
        if data_td.modelId == model then
            sampSendClickTextdraw(id)
            data.mask_found = true
            return true
        end
    end
    if id == 2183 and not data.mask_found then
        if data_td.text == '1' then
            sampSendClickTextdraw(2184)
        elseif data_td.text == '2' then
            sampAddChatMessage("{008080}[CrimeManager] {ff0000}� ��� ��� �����", -1)
            sampSendClickTextdraw(90)
            data.fmask_active = false
        end
    end
    return true
end

function sampev.onShowDialog(id, style, title, button1, button2, text)
    if not data.fmask_active then return true end
    local server = sampGetCurrentServerName()
    if not server or not server:find('Evolve%-Rp%.Ru') then return true end
    if id == 24700 then
        if text:find("������") then
            sampSendDialogResponse(id, 1, 1)
            data.mask_equipped = true
            lua_thread.create(function()
                wait(888)
                sampSendChat("/mask")
            end)
        else
            sampSendDialogResponse(id, 0, 0)
            data.mask_equipped = false
        end
        sampSendClickTextdraw(90)
        data.fmask_active = false
        return false
    end
    return true
end

-- ========== ���������� ����� ==========
local function getPlayerIdByNickname(nick)
    if not nick or nick == "" then return nil end
    for i = 0, 1000 do
        if sampIsPlayerConnected(i) then
            local name = sampGetPlayerNickname(i)
            if name and name:lower() == nick:lower() then
                return i
            end
        end
    end
    return nil
end

local function autoGiveRank(nick)
    if not ui.autogiverank.v then return end
    local playerId = getPlayerIdByNickname(nick)
    if playerId then
        local rank = ui.giverankValue.v
        if rank < 1 then rank = 1 end
        sampSendChat(string.format("/giverank %d %d", playerId, rank))
    else
        sampAddChatMessage(string.format("{008080}[CrimeManager] {ff0000}�� ������� ����� ID ������ %s ��� ������ �����.", nick), -1)
    end
end

-- ========== ����-��� � ID ==========
local function updateKillFeed(killerId, killedId)
    if not ui.showKillIds.v then return end
    if not data.killInfoPtr then return end
    local _, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
    if not myId then myId = -1 end

    local killerNick = nil
    local killedNick = nil

    if killerId >= 0 and (sampIsPlayerConnected(killerId) or killerId == myId) then
        killerNick = sampGetPlayerNickname(killerId)
        if killerNick then
            killerNick = killerNick .. "[" .. killerId .. "]"
        end
    end
    if killedId >= 0 and (sampIsPlayerConnected(killedId) or killedId == myId) then
        killedNick = sampGetPlayerNickname(killedId)
        if killedNick then
            killedNick = killedNick .. "[" .. killedId .. "]"
        end
    end
    if killerNick then
        ffi.copy(data.killInfoPtr.killEntry[4].szKiller, killerNick:sub(1, 24))
    end
    if killedNick then
        ffi.copy(data.killInfoPtr.killEntry[4].szVictim, killedNick:sub(1, 24))
    end
end

-- ========== �����/������ ==========
local function getCurrentWeather()
    return readMemory(13112096, 4, true)
end

local function getCurrentHour()
    local hour, minute = getTimeOfDay()
    return hour
end

local function patch_samp_time_set(enable)
    if enable and data.default_patch == nil then
        data.default_patch = readMemory(sampGetBase() + 639136, 4, true)
        writeMemory(sampGetBase() + 639136, 4, 2242, true)
    elseif not enable and data.default_patch ~= nil then
        writeMemory(sampGetBase() + 639136, 4, data.default_patch, true)
        data.default_patch = nil
    end
end

local function setTimeLock(enable, hour)
    if enable then
        if hour then
            data.locked_time = hour
            data.time_locked = true
            setTimeOfDay(hour, 0)
            patch_samp_time_set(true)
        end
    else
        data.time_locked = false
        data.locked_time = nil
        patch_samp_time_set(false)
    end
    saveIniFile()
end

local function setWeatherLock(enable, weather)
    if enable then
        if weather then
            data.locked_weather = weather
            data.weather_locked = true
            forceWeatherNow(weather)
        end
    else
        data.weather_locked = false
        data.locked_weather = nil
    end
    saveIniFile()
end

local function updateWeatherTimeLoop()
    if not ui.weather_enabled.v then return end
    if data.time_locked and data.locked_time ~= nil then
        setTimeOfDay(data.locked_time, 0)
        patch_samp_time_set(true)
    elseif not data.time_locked and data.default_patch ~= nil then
        patch_samp_time_set(false)
    end
    if data.weather_locked and data.locked_weather ~= nil then
        forceWeatherNow(data.locked_weather)
    end
end

local function cmdSetTime(param)
    local hour = tonumber(param)
    if hour and hour >= 0 and hour <= 23 then
        setTimeLock(true, hour)
        sampAddChatMessage(string.format("{00FF00}[CrimeManager] ����� ����������� �� %02d:00 � �������������.", hour), -1)
    else
        sampAddChatMessage("{FF0000}[CrimeManager] ������: /"..ui.stime_cmd.v.." [0-23]", -1)
    end
end

local function cmdSetWeather(param)
    local weather = tonumber(param)
    if weather and weather >= 0 and weather <= 45 then
        setWeatherLock(true, weather)
        sampAddChatMessage(string.format("{00FF00}[CrimeManager] ������ ����������� �� %d � �������������.", weather), -1)
    else
        sampAddChatMessage("{FF0000}[CrimeManager] ������: /"..ui.sweat_cmd.v.." [0-45]", -1)
    end
end

local function cmdToggleTimeLock()
    if data.time_locked then
        setTimeLock(false)
        sampAddChatMessage("{FFAA00}[CrimeManager] ���������� ������� �����. ������ ��������� ��������.", -1)
    else
        local hour = getCurrentHour()
        if hour then
            setTimeLock(true, hour)
            sampAddChatMessage(string.format("{00FF00}[CrimeManager] ������� ����� (%02d:00) �������������.", hour), -1)
        else
            sampAddChatMessage("{FF0000}[CrimeManager] �� ������� �������� ������� �����.", -1)
        end
    end
end

local function cmdToggleWeatherLock()
    if data.weather_locked then
        setWeatherLock(false)
        sampAddChatMessage("{FFAA00}[CrimeManager] ���������� ������ �����. ������ ��������� �������.", -1)
    else
        local weather = getCurrentWeather()
        if weather and weather >= 0 and weather <= 45 then
            setWeatherLock(true, weather)
            sampAddChatMessage(string.format("{00FF00}[CrimeManager] ������� ������ (ID %d) �������������.", weather), -1)
        else
            sampAddChatMessage("{FF0000}[CrimeManager] �� ������� �������� ������� ������.", -1)
        end
    end
end

local function registerWeatherCommands()
    if not ui.weather_enabled.v then return end
    sampRegisterChatCommand(ui.stime_cmd.v, cmdSetTime)
    sampRegisterChatCommand(ui.sweat_cmd.v, cmdSetWeather)
    sampRegisterChatCommand(ui.btime_cmd.v, cmdToggleTimeLock)
    sampRegisterChatCommand(ui.bweat_cmd.v, cmdToggleWeatherLock)
end

local function unregisterWeatherCommands()
    sampUnregisterChatCommand(ui.stime_cmd.v)
    sampUnregisterChatCommand(ui.sweat_cmd.v)
    sampUnregisterChatCommand(ui.btime_cmd.v)
    sampUnregisterChatCommand(ui.bweat_cmd.v)
end

-- ========== �������������� ������� ��� ����� ==========
local function autoWarehouseSequence()
    if data.warehouseThreadActive then return end
    data.warehouseThreadActive = true
    lua_thread.create(function()
        sampSendChat(ui.warehouseCommand.v)
        wait(ui.warehouseDelay.v * 1000)
        sampSendChat(ui.warehouseCommand.v)
        wait(500)
        data.warehouseThreadActive = false
    end)
end

local function autoFixcarSequence()
    sampSendChat(ui.fixcarCommand.v)
    data.awaitingRespawnMessage = true
    lua_thread.create(function()
        wait(5000)
        data.awaitingRespawnMessage = false
    end)
end

-- ========== AMMO ==========
local function ammoFormatTime(remaining)
    if remaining <= 0 then return "��:��" end
    local minutes = math.floor(remaining / 60)
    local seconds = remaining % 60
    return string.format("%d:%02d", minutes, seconds)
end

local function ammoGetStatusString()
    local currentTime = os.time()
    local parts = {}
    for _, biz in ipairs(ammo_list) do
        local name = ammo_biz_names[biz]
        local remaining = ammo_timers[biz] - currentTime
        if remaining > 0 then
            parts[#parts+1] = string.format("%s: %s", name, ammoFormatTime(remaining))
        else
            parts[#parts+1] = string.format("%s: ��:��", name)
        end
    end
    return "AMMO " .. table.concat(parts, " | ")
end

local function ammoUpdateTimersFromMessage(message)
    local pattern = "AMMO%s+(%S+)[%s:-]+(%S+)"
    local currentTime = os.time()
    local updated = false
    for city, timestr in string.gmatch(message, pattern) do
        local biz_id = ammo_biz_map[city]
        if biz_id then
            if timestr == "xx:xx" or timestr == "�� ����" or timestr == "00:00" then
                if ammo_timers[biz_id] ~= 0 then
                    ammo_timers[biz_id] = 0
                    updated = true
                end
            else
                local min, sec = string.match(timestr, "(%d+):(%d+)")
                if min and sec then
                    local total_sec = tonumber(min)*60 + tonumber(sec)
                    local newTime = currentTime + total_sec
                    if ammo_timers[biz_id] ~= newTime then
                        ammo_timers[biz_id] = newTime
                        updated = true
                    end
                end
            end
        end
    end
    if updated then
        for biz, val in pairs(ammo_timers) do
            mainIni.maincfg.ammo_timers[biz] = val
        end
        saveIniFile()
        sampAddChatMessage("[AMMO] ������� ��������� �� ��������� �������.", 4294427136)
    end
end

-- ========== ���������� ������� ==========
local function formatBankTime(sec)
    if sec <= 0 then return "��:��" end
    local days = math.floor(sec / 86400)
    sec = sec % 86400
    local hours = math.floor(sec / 3600)
    sec = sec % 3600
    local minutes = math.floor(sec / 60)
    if days > 0 then
        return string.format("%d� %02d:%02d", days, hours, minutes)
    else
        return string.format("%02d:%02d", hours, minutes)
    end
end

local function bankGetStatusString()
    local currentTime = os.time()
    local parts = {}
    local cities = {"LS", "SF", "LV"}
    for _, city in ipairs(cities) do
        local remaining = (data.bank_timers[city] or 0) - currentTime
        if remaining > 0 then
            parts[#parts+1] = string.format("%s: %s", city, formatBankTime(remaining))
        else
            parts[#parts+1] = string.format("%s: ��:��", city)
        end
    end
    return "BANK " .. table.concat(parts, " | ")
end

-- ========== ������ ���� ==========
local function zoneLoadGangZones()
    data.zone_gangzones = {}
    local poolPtr = 0

    poolPtr = sampGetGangzonePoolPtr()
    if poolPtr == 0 then
        poolPtr = readMemory(sampGetBase() + 2203900, 4, true)
    end
    if poolPtr == 0 then
        poolPtr = readMemory(sampGetBase() + 2203896, 4, true)
    end
    if poolPtr == 0 then
        return false
    end

    local pool = ffi.cast("struct stGangzonePool*", poolPtr)
    if pool == nil then return false end

    local count = 0
    for i = 0, 1023 do
        if pool.iIsListed[i] ~= 0 and pool.pGangzone[i] ~= nil then
            local z = pool.pGangzone[i]
            local pos = z.fPosition
            data.zone_gangzones[i] = {
                x1 = pos[0],
                y1 = pos[1],
                x2 = pos[2],
                y2 = pos[3]
            }
            count = count + 1
        end
    end
    if count > 0 then
        sampAddChatMessage("[ZONE] ��������� "..count.." �������", 4278255360)
        return true
    end
    return false
end

local function zonePointInRect(px, py, x1, y1, x2, y2)
    return px >= math.min(x1, x2) and px <= math.max(x1, x2) and
           py >= math.min(y1, y2) and py <= math.max(y1, y2)
end

local function zoneGetStatus()
    local ped = PLAYER_PED
    if not doesCharExist(ped) then return "��������...", 4294967295 end
    local x, y, z = getCharCoordinates(ped)
    local inZone = false

    for id, z in pairs(data.zone_gangzones) do
        if zonePointInRect(x, y, z.x1, z.y1, z.x2, z.y2) then
            inZone = true
            break
        end
    end

    if inZone then
        return "� ��������", 4278255360
    else
        return "��� ����", 4294901760
    end
end

-- ========== ���������� INI ==========
function saveIniFile()
    mainIni.maincfg.deletekiy = ui.deletekiy.v
    mainIni.maincfg.smskontr = ui.smskontr.v
    mainIni.maincfg.uvedkontr = ui.uvedkontr.v
    mainIni.maincfg.autobar = ui.autobar.v
    mainIni.maincfg.admcopyid = ui.admcopyid.v
    mainIni.maincfg.autom4g = ui.autom4g.v
    mainIni.maincfg.automget = tostring(u8:decode(ui.automget.v))
    mainIni.maincfg.captureEnabled = ui.captureEnabled.v
    mainIni.maincfg.captureCommand = ui.captureCommand.v
    mainIni.maincfg.captureKey = (ui.captureHotkey.v and ui.captureHotkey.v[1]) or 0
    mainIni.maincfg.captureDelay = ui.captureDelay.v
    mainIni.maincfg.sellGunWeapon = ui.sellGunWeapon
    mainIni.maincfg.sellGunAmmo = ui.sellGunAmmo
    mainIni.maincfg.sellGunPrice = ui.sellGunPrice
    mainIni.maincfg.sellDrugsGrams = ui.sellDrugsGrams
    mainIni.maincfg.sellDrugsPrice = ui.sellDrugsPrice
    mainIni.maincfg.autoleech = ui.autoleech.v
    mainIni.maincfg.fastMaskEnabled = ui.fastMaskEnabled.v
    mainIni.maincfg.fastMaskCommand = ui.fastMaskCommand.v
    mainIni.maincfg.autogiverank = ui.autogiverank.v
    mainIni.maincfg.giverankValue = ui.giverankValue.v
    mainIni.maincfg.showKillIds = ui.showKillIds.v
    mainIni.maincfg.autoWarehouseEnabled = ui.autoWarehouseEnabled.v
    mainIni.maincfg.warehouseTriggerWord = ui.warehouseTriggerWord.v
    mainIni.maincfg.warehouseCommand = ui.warehouseCommand.v
    mainIni.maincfg.warehouseDelay = ui.warehouseDelay.v
    mainIni.maincfg.autoFixcarEnabled = ui.autoFixcarEnabled.v
    mainIni.maincfg.fixcarTriggerWord = ui.fixcarTriggerWord.v
    mainIni.maincfg.fixcarCommand = ui.fixcarCommand.v
    mainIni.maincfg.frangEnabled = ui.frangEnabled.v
    mainIni.maincfg.frangCommand = ui.frangCommand.v
    mainIni.maincfg.mafiaDelivery = ui.mafiaDelivery.v
    mainIni.maincfg.matsput_enabled = ui.matsputEnabled.v
    mainIni.maincfg.matsput_cmd = ui.matsputCmd.v
    mainIni.maincfg.matsput_delay = ui.matsputDelay.v
    mainIni.maincfg.hideFamilyEvent = ui.hideFamilyEvent.v
    mainIni.maincfg.ammo_enabled = ui.ammoEnabled.v
    mainIni.maincfg.ammo_x = ui.ammoX.v
    mainIni.maincfg.ammo_y = ui.ammoY.v
    mainIni.maincfg.ammo_size = ui.ammoSize.v
    if type(mainIni.maincfg.ammo_timers) ~= "table" then
        mainIni.maincfg.ammo_timers = {}
    end
    for biz, val in pairs(ammo_timers) do
        mainIni.maincfg.ammo_timers[biz] = val
    end
    mainIni.maincfg.bank_enabled = ui.bankEnabled.v
    mainIni.maincfg.bank_x = ui.bankX.v
    mainIni.maincfg.bank_y = ui.bankY.v
    mainIni.maincfg.bank_size = ui.bankSize.v
    mainIni.maincfg.bank_ls = data.bank_timers.LS or 0
    mainIni.maincfg.bank_sf = data.bank_timers.SF or 0
    mainIni.maincfg.bank_lv = data.bank_timers.LV or 0
    mainIni.maincfg.zone_enabled = ui.zoneEnabled.v
    mainIni.maincfg.zone_x = ui.zoneX.v
    mainIni.maincfg.zone_y = ui.zoneY.v
    mainIni.maincfg.zone_size = ui.zoneSize.v
    mainIni.weather_commands.enabled = ui.weather_enabled.v
    mainIni.weather_commands.stime_cmd = ui.stime_cmd.v
    mainIni.weather_commands.sweat_cmd = ui.sweat_cmd.v
    mainIni.weather_commands.btime_cmd = ui.btime_cmd.v
    mainIni.weather_commands.bweat_cmd = ui.bweat_cmd.v
    mainIni.weather_commands.time_locked = data.time_locked
    mainIni.weather_commands.locked_time = data.locked_time or 0
    mainIni.weather_commands.weather_locked = data.weather_locked
    mainIni.weather_commands.locked_weather = data.locked_weather or 0
    inicfg.save(mainIni, path_ini)
end

loadBindersFromIni()

-- =====================================================================
-- �������������� ���������� (������ �������� ���������)
-- =====================================================================

local SCRIPT_VERSION = "1.0.2"   -- �������� ��� ������ ������
local VERSION_URL = "https://raw.githubusercontent.com/offquinter1/CrimeManager/main/version.txt"
local SCRIPT_UPDATE_URL = "https://raw.githubusercontent.com/offquinter1/CrimeManager/main/CrimeManager%20by%20Quinter.luac"

local updateCheckRunning = false

-- ������� �������� (curl + ssl.https)
local function fetchBinary(url)
    -- ������� curl (� User-Agent)
    local curl_cmd = 'curl -s -L -A "Mozilla/5.0" "' .. url .. '"'
    local file = io.popen(curl_cmd, 'r')
    if file then
        local content = file:read('*all')
        file:close()
        if content and #content > 0 then
            return content, 200
        end
    end

    -- ������� ssl.https
    local ok, https = pcall(require, "ssl.https")
    if ok then
        local ltn12 = require("ltn12")
        local response = {}
        local res, code = https.request{
            url = url,
            sink = ltn12.sink.table(response),
            headers = { ["User-Agent"] = "Mozilla/5.0" }
        }
        if code == 200 then
            return table.concat(response), code
        end
    end
    return nil, 404
end

-- �������� ��������� Lua 5.1
local function isValidLua51(data)
    if #data < 4 then return false end
    return string.byte(data, 1) == 27 and
           string.byte(data, 2) == 76 and
           string.byte(data, 3) == 117 and
           string.byte(data, 4) == 97
end

local function downloadAndApplyUpdate()
    sampAddChatMessage("{008080}[CrimeManager] {ffffff}�������� ����������...", -1)
    local new_data, code = fetchBinary(SCRIPT_UPDATE_URL)

    if code ~= 200 then
        sampAddChatMessage(string.format("{008080}[CrimeManager] {ff0000}������ �������� (��� %d).", code), -1)
        return false
    end

    local temp_path = os.tmpname() .. ".luac"
    local f = io.open(temp_path, "wb")
    if not f then
        sampAddChatMessage("{008080}[CrimeManager] {ff0000}������ �������� ���������� �����.", -1)
        return false
    end
    f:write(new_data)
    f:close()

    local script_path = debug.getinfo(1).source:gsub("^@", "")
    if script_path == "" then script_path = "moonloader\\CrimeManager.lua" end

    local ok, err = os.rename(temp_path, script_path)
    if not ok then
        local old = io.open(temp_path, "rb")
        if old then
            local new = io.open(script_path, "wb")
            if new then
                new:write(old:read("*all"))
                new:close()
                ok = true
            end
            old:close()
        end
        os.remove(temp_path)
    end

    if not ok then
        sampAddChatMessage("{008080}[CrimeManager] {ff0000}������ ������ �����.", -1)
        return false
    end

    sampAddChatMessage("{008080}[CrimeManager] {00ff00}���������� �����������. ������������ ����� 1 ���...", -1)
    lua_thread.create(function()
        wait(1000)
        package.loaded["CrimeManager"] = nil
        local fn, err_load = loadfile(script_path)
        if fn then
            fn()
        else
            sampAddChatMessage("{008080}[CrimeManager] {ff0000}������ ������������: "..tostring(err_load), -1)
        end
    end)
    return true
end

local function checkVersionAndUpdate()
    if updateCheckRunning then return end
    updateCheckRunning = true
    sampAddChatMessage("{008080}[CrimeManager] {ffffff}�������� ����������...", -1)

    local version_text, code = fetchBinary(VERSION_URL)
    if code ~= 200 then
        sampAddChatMessage(string.format("{008080}[CrimeManager] {ff0000}�� ������� ��������� version.txt (��� %d).", code), -1)
        updateCheckRunning = false
        return
    end

    local remote_version = version_text:match("%S+") or ""
    if remote_version == "" then
        sampAddChatMessage("{008080}[CrimeManager] {ff0000}������ ������ � version.txt.", -1)
        updateCheckRunning = false
        return
    end

    if remote_version ~= SCRIPT_VERSION then
        sampAddChatMessage(string.format("{008080}[CrimeManager] {ffff00}����� ������: %s (������� %s). ���������...", remote_version, SCRIPT_VERSION), -1)
        downloadAndApplyUpdate()
    else
        sampAddChatMessage("{008080}[CrimeManager] {00ff00}������ ��������.", -1)
    end

    updateCheckRunning = false
end

local function scheduleUpdateCheck(delay)
    lua_thread.create(function()
        wait(delay or 3000)
        checkVersionAndUpdate()
    end)
end

-- =====================================================================

-- ========== �������������� ������� ==========
local function getCoordinates(player)
    if isCharInAnyCar(player) then
        local car = storeCarCharIsInNoSave(player)
        return getCarCoordinates(car)
    else
        return getCharCoordinates(player)
    end
end

local function getDistance(x1, y1, z1, x2, y2, z2)
    return math.sqrt((x1 - x2)^2 + (y1 - y2)^2 + (z1 - z2)^2)
end

-- ========== ������� SAMP ==========
function sampev.onServerMessage(color, text)
    if text:find("�����������: �������������") and ui.smskontr.v then return false end
    if text:find("��������: �������������") and ui.uvedkontr.v then return false end
    if text:find("�������� ����� �� �������� �����������") and ui.mafiaDelivery.v then return false end
    if text:find("����� �������� ����� �� �������� �����������") and ui.mafiaDelivery.v then return false end
    if ui.hideFamilyEvent.v then
        if text:find("����� %d+ ����� �������� �������� ����� �� ����� ����������") or text:find("�������� ����� �� ����� ���������� �������") then
            return false
        end
    end
    if string.find(text, "AMMO") and string.find(text, "-") then
        ammoUpdateTimersFromMessage(text)
    end
    local bank_pattern = "���� (LS|SF|LV) ��� �������� �������. ��������� ���������� ����� ��������%s?(%d+):(%d+) (%d+)%.(%d+)%.(%d+)"
    local city, hour_s, min_s, day_s, month_s, year_s = text:match(bank_pattern)
    if city and hour_s and min_s and day_s and month_s and year_s then
        local hour = tonumber(hour_s)
        local minute = tonumber(min_s)
        local day = tonumber(day_s)
        local month = tonumber(month_s)
        local year = tonumber(year_s)
        if hour and minute and day and month and year then
            local timestamp = os.time({year=year, month=month, day=day, hour=hour, min=minute, sec=0})
            data.bank_timers[city] = timestamp
            saveIniFile()
            sampAddChatMessage(string.format("[BANK] ������ ��� ����� %s ���������� �� %02d:%02d %02d.%02d.%04d", city, hour, minute, day, month, year), 4294427136)
        end
    end
    local min, sec = string.match(text, "�� ���������� ���������� (%d+):(%d+)")
    if min and sec and data.ammo_in_biz ~= '' then
        local plus_time = (tonumber(min) * 60) + tonumber(sec)
        local newTime = os.time() + plus_time
        ammo_timers[data.ammo_in_biz] = newTime
        for biz, val in pairs(ammo_timers) do mainIni.maincfg.ammo_timers[biz] = val end
        saveIniFile()
        sampAddChatMessage(string.format("[AMMO] ������ %s ���������� �� %d:%02d", ammo_biz_names[data.ammo_in_biz], tonumber(min), tonumber(sec)), 4294427136)
        if ammo_business[data.ammo_in_biz] and ammo_business[data.ammo_in_biz].group == "ammo" then
            local timeStr = string.format("%d:%02d", tonumber(min), tonumber(sec))
            sampSendChat("/f " .. string.format("AMMO %s: %s", ammo_biz_names[data.ammo_in_biz], timeStr))
        end
        return true
    end
    local currentTime = os.time()
    for _, biz in ipairs(ammo_list) do
        local bizName = ammo_biz_names[biz]
        local pattern1 = string.format("AMMO %s:.*���� ��", bizName)
        local pattern2 = string.format("%s:.*���� ��", bizName)
        if string.find(text, pattern1) or string.find(text, pattern2) then
            if ammo_timers[biz] > currentTime then
                ammo_timers[biz] = 0
                for b, v in pairs(ammo_timers) do mainIni.maincfg.ammo_timers[b] = v end
                saveIniFile()
                sampAddChatMessage(string.format("[AMMO] ������ %s ������� (������� �����).", bizName), 4294427136)
            end
            break
        end
    end
    if string.find(text, "���������� ������� 3 ��������") and data.ammo_in_biz ~= '' and ammo_business[data.ammo_in_biz] and ammo_business[data.ammo_in_biz].group == "ammo" then
        if ammo_timers[data.ammo_in_biz] > os.time() then
            ammo_timers[data.ammo_in_biz] = 0
            for b, v in pairs(ammo_timers) do mainIni.maincfg.ammo_timers[b] = v end
            saveIniFile()
        end
        sampSendChat("/f " .. string.format("AMMO %s: �� ����", ammo_biz_names[data.ammo_in_biz]))
        return true
    end
    if string.find(text, "�� �������� $2500 �� ��������") and data.ammo_in_biz ~= '' and ammo_business[data.ammo_in_biz] and ammo_business[data.ammo_in_biz].group == "ammo" then
        local thirty_min = 30 * 60
        local newTime = os.time() + thirty_min
        ammo_timers[data.ammo_in_biz] = newTime
        for b, v in pairs(ammo_timers) do mainIni.maincfg.ammo_timers[b] = v end
        saveIniFile()
        local bizName = ammo_biz_names[data.ammo_in_biz]
        sampSendChat("/f " .. string.format("+AMMO %s", bizName))
        sampAddChatMessage(string.format("[AMMO] ����� ���������� �� ��� %s ����������� �� 30 �����.", bizName), 4294427136)
        return true
    end
    if text:find("������ ���� � ������") and data.activeautoload then lua_thread.create(function() data.proccesautoload = false end) end
    if text:find("������ �������� � ������") and data.activeautoload then lua_thread.create(function() data.proccesautoload = false end) end
    if text:find("�� �������") and data.activeautoload then lua_thread.create(function() data.proccesautoload = true end) end
    if text:find("�� �������� � ������") and data.activeautoload then lua_thread.create(function() data.proccesautoload = true end) end
    if text:find("������ Online:") and ui.admcopyid.v then data.admids = ""; return true end
    if text:find(" | ID%: (%d+) | Level") and ui.admcopyid.v then
        local aId = text:match(" | ID%: (%d+) | Level")
        data.admids = data.admids .. aId .. " "
        setClipboardText(data.admids)
    end
    if data.waitingForFamily then
        local nick, rang = text:match("%[([^%]]+)%] %[(%d+)%]")
        if nick and rang then
            table.insert(data.familyMembers, nick)
        end
    end
    local server = sampGetCurrentServerName()
    if server and server:find('Evolve%-Rp%.Ru') and text:find("������� ����� ������ �����") then
        lua_thread.create(function()
            wait(888)
            fastmask_command_handler()
        end)
    end
    if text:find("^�� ������ �����") then
        data.mask_equipped = true
    elseif text:find("^�� ����� �����") then
        data.mask_equipped = false
    end
    if ui.autogiverank.v then
        local nick = nil
        nick = text:match("������� ������ ([%w_]+)")
        if not nick then
            nick = text:match("������� ������� ([%w_]+)")
        end
        if not nick then
            nick = text:match("������� ����� �� ����� ([%w_]+)")
        end
        if nick then
            lua_thread.create(function()
                wait(500)
                autoGiveRank(nick)
            end)
        end
    end
    local msg_lower = text:lower()
    if ui.autoWarehouseEnabled.v and msg_lower:find(ui.warehouseTriggerWord.v:lower(), 1, true) then
        autoWarehouseSequence()
    end
    if ui.autoFixcarEnabled.v and msg_lower:find(ui.fixcarTriggerWord.v:lower(), 1, true) then
        autoFixcarSequence()
    end
    if data.awaitingRespawnMessage and text:find("������� ������������ ������� ����������� ����� �������� �����") then
        data.awaitingRespawnMessage = false
        lua_thread.create(function()
            wait(1000)
            sampSendChat("/f " .. text)
        end)
    end
    if data.collectingFor then
        local rank, nick = text:match("%[(%d+)%] %[(%w+_%w+)%]")
        if rank and nick then
            rank = tonumber(rank)
            if rank then
                if data.collectingFor == "bikers" and rank >= 6 and rank <= 8 then
                    table.insert(data.offmembers, nick)
                    table.insert(data.offmembersrangs, rank)
                elseif data.collectingFor == "ghetto" and rank >= 7 and rank <= 9 then
                    table.insert(data.ghettoMembers, nick)
                    table.insert(data.ghettoRangs, rank)
                elseif data.collectingFor == "mafia" and rank >= 7 and rank <= 9 then
                    table.insert(data.mafiaMembers, nick)
                    table.insert(data.mafiaRangs, rank)
                end
            end
        end
        if not data.collectTimer then
            data.collectTimer = lua_thread.create(function()
                wait(3000)
                data.collectingFor = nil
                data.collectTimer = nil
            end)
        end
    end
    if data.collectingMembers then
        local id = text:match("ID: (%d+)")
        if id then
            local rank = nil
            for num in text:gmatch("%[(%d+)%]") do
                rank = tonumber(num)
                break
            end
            if rank and rank >= 1 and rank <= 6 then
                local exists = false
                for _, m in ipairs(data.membersList) do
                    if m.id == tonumber(id) then exists = true; break end
                end
                if not exists then
                    table.insert(data.membersList, {id=tonumber(id), rank=rank})
                end
            end
        end
    end
    return true
end

function sampev.onChatMessage(playerid, message, color)
    if string.find(message, "AMMO") and string.find(message, "-") then
        ammoUpdateTimersFromMessage(message)
    end
    local bank_pattern = "���� (LS|SF|LV) ��� �������� �������. ��������� ���������� ����� ��������%s?(%d+):(%d+) (%d+)%.(%d+)%.(%d+)"
    local city, hour_s, min_s, day_s, month_s, year_s = message:match(bank_pattern)
    if city and hour_s and min_s and day_s and month_s and year_s then
        local hour = tonumber(hour_s)
        local minute = tonumber(min_s)
        local day = tonumber(day_s)
        local month = tonumber(month_s)
        local year = tonumber(year_s)
        if hour and minute and day and month and year then
            local timestamp = os.time({year=year, month=month, day=day, hour=hour, min=minute, sec=0})
            data.bank_timers[city] = timestamp
            saveIniFile()
            sampAddChatMessage(string.format("[BANK] ������ ��� ����� %s ���������� �� %02d:%02d %02d.%02d.%04d", city, hour, minute, day, month, year), 4294427136)
        end
    end
    return true
end

function sampev.onPlayerDeathNotification(killerId, killedId, reason)
    lua_thread.create(function()
        wait(0)
        updateKillFeed(killerId, killedId)
    end)
end

function sampev.onServerConnect()
    lua_thread.create(function()
        wait(1000)
        if ui.weather_enabled.v then
            if data.time_locked and data.locked_time then
                setTimeLock(true, data.locked_time)
            end
            if data.weather_locked and data.locked_weather then
                setWeatherLock(true, data.locked_weather)
            end
            registerWeatherCommands()
        end
        data.ammo_font = renderCreateFont('Arial', ui.ammoSize.v, 13)
        data.bank_font = renderCreateFont('Arial', ui.bankSize.v, 13)
        data.zone_font = renderCreateFont('Arial', ui.zoneSize.v, 13)
        zoneLoadGangZones()
    end)
    scheduleUpdateCheck(5000)
end

-- ========== ����������� ������� ==========
function sampev.onCreateGangZone(zoneid, start, finish, color)
    data.zone_gangzones[zoneid] = { x1 = start.x, y1 = start.y, x2 = finish.x, y2 = finish.y }
    data.zone_flashing[zoneid] = nil
end

function sampev.onGangZoneDestroy(zoneid)
    data.zone_gangzones[zoneid] = nil
    data.zone_flashing[zoneid] = nil
end

function sampev.onGangZoneFlash(zoneid, color)
    data.zone_flashing[zoneid] = true
end

function sampev.onGangZoneStopFlash(zoneid)
    data.zone_flashing[zoneid] = nil
end

-- ========== HOUSE LINE ==========
function sampev.onCreatePickup(pickupid, model, type, pos)
    if not data.houseLineEnabled then return end
    local x, y, z = pos:get()
    table.insert(data.houseLinePickups, {
        pickupid,
        model,
        type,
        x,
        y,
        z,
    })
    if model == 1273 then
        local px, py, pz = getCoordinates(PLAYER_PED)
        local dist = math.ceil(getDistance(px, py, pz, x, y, z))
        sampAddChatMessage("��������! ������� ������������ ������� ���������! ���������: " .. dist .. " �. ", 65280)
    end
end

function sampev.onDestroyPickup(pickupid)
    if not data.houseLineEnabled then return end
    for i, p in ipairs(data.houseLinePickups) do
        if p[1] == pickupid then
            table.remove(data.houseLinePickups, i)
            break
        end
    end
end

-- ========== �������������� ��������� �������� ==========
local orig_onShowDialog = sampev.onShowDialog
function sampev.onShowDialog(id, style, title, button1, button2, text)
    if data.fmask_active then
        local server = sampGetCurrentServerName()
        if server and server:find('Evolve%-Rp%.Ru') then
            if id == 24700 then
                if text:find("������") then
                    sampSendDialogResponse(id, 1, 1)
                    data.mask_equipped = true
                    lua_thread.create(function()
                        wait(888)
                        sampSendChat("/mask")
                    end)
                else
                    sampSendDialogResponse(id, 0, 0)
                    data.mask_equipped = false
                end
                sampSendClickTextdraw(90)
                data.fmask_active = false
                return false
            end
        end
    end
    if data.houseLineEnabled then
        if title:find("��� ��������") and text:match("/buyhouse ����� ������ ���") then
            sampSendDialogResponse(id, 0, _, _)
            sampSendChat("/buyhouse")
            return false
        end
        if title:match("{FFFFFF}����������� | {......}�����������") or title:match("{FFFFFF}��������� | {......}���� ���������") then
            sampSendDialogResponse(id, 1, nil, "#exorcist")
            return false
        end
    end
    return true
end

-- ========== ��������������� ������� ��� ��������� ==========
local function HelpMarker(desc)
    imgui.TextDisabled("(?)")
    if imgui.IsItemHovered() then
        imgui.BeginTooltip()
        imgui.PushTextWrapPos(imgui.GetFontSize() * 35)
        imgui.TextUnformatted(u8(desc))
        imgui.PopTextWrapPos()
        imgui.EndTooltip()
    end
end

-- ========== MAIN ==========
function main()
    while not isSampAvailable() do wait(100) end

    scheduleUpdateCheck(5000)
    sampAddChatMessage("{008080}[CrimeManager] {FFFFFF}������� ��������. ��������� {008080}/cm (UU). {FFFFFF}����� {008080}Dima Quinter", -1)

    if sampGetKillInfoPtr then
        data.killInfoPtr = ffi.cast('struct stKillInfo*', sampGetKillInfoPtr())
    end

    sampRegisterChatCommand("cm", function() ui.main_window.v = not ui.main_window.v end)
    sampRegisterChatCommand("binder", function() ui.main_window.v = true; ui.activeTab = 3 end)
    sampRegisterChatCommand("famq", function() ui.main_window.v = true; ui.activeTab = 4 end)

    -- ====== /frang ======
    local function registerFrangCommand()
        if data.frangRegisteredCmd ~= "" then
            sampUnregisterChatCommand(data.frangRegisteredCmd)
        end
        if ui.frangEnabled.v then
            local cmd = ui.frangCommand.v:match("^/(.+)$") or ui.frangCommand.v
            if cmd == "" then cmd = "frang" end
            sampRegisterChatCommand(cmd, function()
                if data.collectingMembers then
                    sampAddChatMessage("{008080}[CrimeManager] {ff0000}��� ���� ���� ������ ������.", -1)
                    return
                end
                data.collectingMembers = true
                data.membersList = {}
                sampAddChatMessage("{008080}[CrimeManager] {ffffff}������ /members ��� �����...", -1)
                sampSendChat("/members")
                lua_thread.create(function()
                    wait(2000)
                    data.collectingMembers = false
                    if #data.membersList == 0 then
                        sampAddChatMessage("{008080}[CrimeManager] {ff0000}�� ������� ����� ������ � ������� 1-6.", -1)
                        return
                    end
                    local targetRank = ui.giverankValue.v
                    if targetRank < 1 then targetRank = 1 end
                    local toGive = {}
                    for _, member in ipairs(data.membersList) do
                        if member.rank ~= targetRank then
                            table.insert(toGive, member)
                        end
                    end
                    if #toGive == 0 then
                        sampAddChatMessage("{008080}[CrimeManager] {ffff00}��� ����� � ������� 1-6 ��� ����� ���� "..targetRank..".", -1)
                        return
                    end
                    sampAddChatMessage(string.format("{008080}[CrimeManager] {ffffff}������� %d ������, ��������� ��������� �� ����� %d (��������� %d � ��� ���� ������).", #toGive, targetRank, #data.membersList - #toGive), -1)
                    for _, member in ipairs(toGive) do
                        sampSendChat(string.format("/giverank %d %d", member.id, targetRank))
                        wait(1000)
                    end
                    sampAddChatMessage("{008080}[CrimeManager] {00ff00}������ ������ ���������.", -1)
                end)
            end)
            data.frangRegisteredCmd = cmd
        else
            data.frangRegisteredCmd = ""
        end
    end
    registerFrangCommand()

    -- ====== ���� �������� ======
    sampRegisterChatCommand(mainIni.maincfg.automget, function()
        data.activeautoload = not data.activeautoload
        data.proccesautoload = data.activeautoload
        sampAddChatMessage("{008080}[CrimeManager] {ffffff}���� /materials get � /bput "..(data.activeautoload and "�������" or "����������")..".", -1)
    end)

    -- ====== ���� ����� /mats put ======
    local function registerMatsPutCommand()
        if data.matsputRegisteredCmd and data.matsputRegisteredCmd ~= "" then
            sampUnregisterChatCommand(data.matsputRegisteredCmd)
        end
        if ui.matsputEnabled.v then
            local cmd = ui.matsputCmd.v:match("^/(.+)$") or ui.matsputCmd.v
            if cmd == "" then cmd = "lsa" end
            sampRegisterChatCommand(cmd, function()
                toggleMatsPutFlood()
            end)
            data.matsputRegisteredCmd = cmd
        else
            data.matsputRegisteredCmd = ""
        end
    end
    data.matsputRegisteredCmd = ""
    registerMatsPutCommand()

    -- ====== AMMO ������� ======
    sampRegisterChatCommand("ammosend", function()
        local status = ammoGetStatusString()
        sampSendChat("/f " .. status)
    end)

    -- ====== Bank send ======
    sampRegisterChatCommand("banksend", function()
        local status = bankGetStatusString()
        sampSendChat("/f " .. status)
    end)

    -- ====== ������� ����� ======
    local function registerFastMaskCommand()
        if data.fastMaskRegisteredCmd ~= "" then
            sampUnregisterChatCommand(data.fastMaskRegisteredCmd)
        end
        local cmd = ui.fastMaskCommand.v:match("^/(.+)$") or ui.fastMaskCommand.v
        sampRegisterChatCommand(cmd, fastmask_command_handler)
        data.fastMaskRegisteredCmd = cmd
    end
    registerFastMaskCommand()

    if ui.weather_enabled.v then
        registerWeatherCommands()
    end

    data.ammo_font = renderCreateFont('Arial', ui.ammoSize.v, 13)
    data.bank_font = renderCreateFont('Arial', ui.bankSize.v, 13)
    data.zone_font = renderCreateFont('Arial', ui.zoneSize.v, 13)
    if not data.zone_font then
        data.zone_font = renderCreateFont('Arial', 12, 13)
    end

    sampRegisterChatCommand("zonecheck", function()
        local text, color = zoneGetStatus()
        sampAddChatMessage("[ZONE] ������: "..text, color)
        sampAddChatMessage("[ZONE] ����� ���: "..#data.zone_gangzones, -1)
    end)

    while true do
        wait(0)
        imgui.Process = ui.main_window.v or data.drag_mode

        -- ====== ��������� �������������� ======
        if data.drag_mode then
            local mx, my = getCursorPos()
            if data.drag_type == "ammo" then
                ui.ammoX.v = mx
                ui.ammoY.v = my
            elseif data.drag_type == "bank" then
                ui.bankX.v = mx
                ui.bankY.v = my
            elseif data.drag_type == "zone" then
                ui.zoneX.v = mx
                ui.zoneY.v = my
            end

            if isKeyJustPressed(1) then
                saveIniFile()
                sampAddChatMessage("{008080}[CrimeManager] {ffffff}������� ���������.", -1)
                data.drag_mode = false
                data.drag_type = nil
            end

            if isKeyJustPressed(27) then
                if data.drag_type == "ammo" then
                    ui.ammoX.v = data.drag_saved_x
                    ui.ammoY.v = data.drag_saved_y
                elseif data.drag_type == "bank" then
                    ui.bankX.v = data.drag_saved_x
                    ui.bankY.v = data.drag_saved_y
                elseif data.drag_type == "zone" then
                    ui.zoneX.v = data.drag_saved_x
                    ui.zoneY.v = data.drag_saved_y
                end
                sampAddChatMessage("{008080}[CrimeManager] {ffffff}����������� ��������.", -1)
                data.drag_mode = false
                data.drag_type = nil
            end
        end

        if ui.zoneEnabled.v and next(data.zone_gangzones) == nil then
            if not data._zoneLoadAttempt or os.clock() - data._zoneLoadAttempt > 5 then
                data._zoneLoadAttempt = os.clock()
                zoneLoadGangZones()
            end
        end

        if isKeyJustPressed(27) then
            ui.main_window.v = false
            if data.drag_mode then
                if data.drag_type == "ammo" then
                    ui.ammoX.v = data.drag_saved_x
                    ui.ammoY.v = data.drag_saved_y
                elseif data.drag_type == "bank" then
                    ui.bankX.v = data.drag_saved_x
                    ui.bankY.v = data.drag_saved_y
                elseif data.drag_type == "zone" then
                    ui.zoneX.v = data.drag_saved_x
                    ui.zoneY.v = data.drag_saved_y
                end
                data.drag_mode = false
                data.drag_type = nil
                sampAddChatMessage("{008080}[CrimeManager] {ffffff}����������� �������� (ESC).", -1)
            end
        end

        if not data.isCheckingFamily and isKeyJustPressed(85) then
            local now = os.clock() * 1000
            if now - data.lastUPress < 500 then
                data.uPressCount = data.uPressCount + 1
                if data.uPressCount == 2 then ui.main_window.v = not ui.main_window.v; data.uPressCount = 0 end
            else data.uPressCount = 1 end
            data.lastUPress = now
        end

        local captureKey = (ui.captureHotkey.v and ui.captureHotkey.v[1]) or 0
        if not data.isCheckingFamily and captureKey ~= 0 and isKeyJustPressed(captureKey) then
            toggleCaptureFlood()
        end

        if ui.deletekiy.v then
            local weapon = getCurrentCharWeapon(PLAYER_PED)
            if weapon == 7 or weapon == 5 or weapon == 2 or weapon == 8 then
                removeWeaponFromChar(PLAYER_PED, weapon)
            end
        end

        if data.activeautoload then
            if data.proccesautoload then sampSendChat("/materials get") else sampSendChat("/bput") end
            wait(1000)
        end

        if not data.isCheckingFamily and isKeyJustPressed(71) and isPlayerPlaying(PLAYER_HANDLE) and ui.autom4g.v and not sampIsChatInputActive() and not sampIsDialogActive() and not sampIsScoreboardOpen() and not isSampfuncsConsoleActive() then
            setCurrentCharWeapon(PLAYER_PED, 31)
        end

        data.health = getCharHealth(PLAYER_PED)
        if data.wasDead and data.health > 0 and ui.autoleech.v then
            lua_thread.create(function()
                wait(2500)
                local curHP = getCharHealth(PLAYER_PED)
                if curHP < 100 then
                    local needed = math.ceil((100 - curHP) / 25)
                    for _ = 1, needed do
                        sampSendChat("/healme")
                        wait(500)
                        if getCharHealth(PLAYER_PED) >= 100 then break end
                    end
                end
            end)
        end
        data.wasDead = (data.health == 0)

        if not data.isCheckingFamily and data.recording_binder_idx and (os.clock() - data.recording_start_time) > 5 then
            data.recording_binder_idx = nil
        end
        if not data.isCheckingFamily and data.recording_binder_idx then
            local idx = data.recording_binder_idx
            local binder = binders[idx]
            if binder then
                for code = 1, 255 do
                    if isKeyJustPressed(code) and code ~= 17 and code ~= 18 and code ~= 16 then
                        binder.keyCode = code
                        updateBinder(idx)
                        sampAddChatMessage("{008080}[CrimeManager] {ffffff}��������� �������: "..keyCodeToName(code), -1)
                        data.recording_binder_idx = nil
                        break
                    end
                end
            else data.recording_binder_idx = nil end
        end

        processBinders()

        -- ��������������� ������
        local currentFastCmd = ui.fastMaskCommand.v:match("^/(.+)$") or ui.fastMaskCommand.v
        if data.fastMaskRegisteredCmd ~= currentFastCmd then registerFastMaskCommand() end

        local currentFrangCmd = ui.frangCommand.v:match("^/(.+)$") or ui.frangCommand.v
        if currentFrangCmd == "" then currentFrangCmd = "frang" end
        if data.frangRegisteredCmd ~= currentFrangCmd or (not ui.frangEnabled.v and data.frangRegisteredCmd ~= "") then
            registerFrangCommand()
        end

        local currentMatsCmd = ui.matsputCmd.v:match("^/(.+)$") or ui.matsputCmd.v
        if currentMatsCmd == "" then currentMatsCmd = "lsa" end
        if data.matsputRegisteredCmd ~= currentMatsCmd or (not ui.matsputEnabled.v and data.matsputRegisteredCmd ~= "") then
            registerMatsPutCommand()
        end

        updateWeatherTimeLoop()

        -- ====== ��������� AMMO ======
        if ui.ammoEnabled.v and not isPauseMenuActive() and sampIsChatVisible() and not sampIsScoreboardOpen() and isPlayerPlaying(PLAYER_HANDLE) then
            local font = data.ammo_font
            if font then
                local x = ui.ammoX.v
                local y = ui.ammoY.v
                local currentTime = os.time()

                local header = "����:"
                renderFontDrawText(font, header, x, y, 4294967295)

                local lineHeight = ui.ammoSize.v + 8
                y = y + lineHeight
                x = ui.ammoX.v

                for i, biz in ipairs(ammo_list) do
                    local name = ammo_biz_names[biz]
                    local remaining = ammo_timers[biz] - currentTime
                    local timeStr, valueColor
                    if remaining > 0 then
                        timeStr = ammoFormatTime(remaining)
                        valueColor = 4294901760
                    else
                        timeStr = " ��:�� "
                        valueColor = 4278238467
                    end

                    local nameText = name .. ": "
                    renderFontDrawText(font, nameText, x, y, 4294967295)
                    local nameWidth = renderGetTextSize and renderGetTextSize(font, nameText) or (#nameText * (ui.ammoSize.v * 0.66))
                    renderFontDrawText(font, timeStr, x + nameWidth, y, valueColor)
                    local valueWidth = renderGetTextSize and renderGetTextSize(font, timeStr) or (#timeStr * (ui.ammoSize.v * 0.66))
                    x = x + nameWidth + valueWidth

                    if i < #ammo_list then
                        local sep = " | "
                        renderFontDrawText(font, sep, x, y, 4294967295)
                        x = x + (renderGetTextSize and renderGetTextSize(font, sep) or (#sep * (ui.ammoSize.v * 0.66)))
                    end
                end
            end
        end

        -- ====== ��������� BANK ======
        if ui.bankEnabled.v and not isPauseMenuActive() and sampIsChatVisible() and not sampIsScoreboardOpen() and isPlayerPlaying(PLAYER_HANDLE) then
            if not data.bank_font then
                data.bank_font = renderCreateFont('Arial', ui.bankSize.v, 13)
            end
            local font = data.bank_font
            if font then
                local x = ui.bankX.v
                local y = ui.bankY.v
                local currentTime = os.time()
                local cities = {"LS", "SF", "LV"}

                renderFontDrawText(font, "BANK:", x, y, 4294967295)

                local lineHeight = ui.bankSize.v + 8
                y = y + lineHeight
                x = ui.bankX.v

                for i, city in ipairs(cities) do
                    local timestamp = data.bank_timers[city] or 0
                    local remaining = timestamp - currentTime
                    local timeStr, color
                    if remaining > 0 then
                        timeStr = formatBankTime(remaining)
                        color = 4294901760
                    else
                        timeStr = " ��:�� "
                        color = 4278238467
                    end

                    local nameText = city .. ": "
                    renderFontDrawText(font, nameText, x, y, 4294967295)
                    local nameWidth = renderGetTextSize and renderGetTextSize(font, nameText) or (#nameText * (ui.bankSize.v * 0.66))
                    renderFontDrawText(font, timeStr, x + nameWidth, y, color)
                    local valueWidth = renderGetTextSize and renderGetTextSize(font, timeStr) or (#timeStr * (ui.bankSize.v * 0.66))
                    x = x + nameWidth + valueWidth

                    if i < #cities then
                        local sep = " | "
                        renderFontDrawText(font, sep, x, y, 4294967295)
                        x = x + (renderGetTextSize and renderGetTextSize(font, sep) or (#sep * (ui.bankSize.v * 0.66)))
                    end
                end
            end
        end

        -- ====== ��������� ZONE ======
        if ui.zoneEnabled.v and isPlayerPlaying(PLAYER_HANDLE) then
            if not data.zone_font then
                data.zone_font = renderCreateFont("Arial", ui.zoneSize.v, 13)
                if not data.zone_font then
                    data.zone_font = renderCreateFont("Arial", 12, 13)
                end
            end

            if data.zone_font then
                local text, color = zoneGetStatus()
                if not text then text = "������" end
                renderFontDrawText(data.zone_font, text, ui.zoneX.v, ui.zoneY.v, color)
            end
        end

        -- ====== ��������� HOUSE LINE ======
        if data.houseLineEnabled then
            local sw, sh = getScreenResolution()
            for _, pickup in ipairs(data.houseLinePickups) do
                if pickup[2] == 1273 then
                    local x, y = convert3DCoordsToScreen(pickup[4], pickup[5], pickup[6])
                    if x and y then
                        renderDrawLine(sw / 2, sh / 2 + 200, x, y, 2, 4278255360)
                    end
                end
            end
        end
    end
end

-- ========== IMGUI ==========
function imgui.CenterText(text)
    local w = imgui.GetWindowWidth()
    local tw = imgui.CalcTextSize(text).x
    imgui.SetCursorPosX((w - tw) / 2)
    imgui.Text(text)
end

function imgui.OnDrawFrame()
    local tLastKeys = {}

    if ui.main_window.v then
        imgui.SetNextWindowPos(imgui.ImVec2(data.sw/2, data.sh/2), imgui.Cond.Always, imgui.ImVec2(0.5,0.5))
        if ui.activeTab == 3 then
            imgui.SetNextWindowSize(imgui.ImVec2(1100, 550), imgui.Cond.Always)
        else
            imgui.SetNextWindowSize(imgui.ImVec2(750, 550), imgui.Cond.Always)
        end

        imgui.Begin(u8"CrimeManager | By Dima Quinter", ui.main_window, imgui.WindowFlags.NoCollapse+imgui.WindowFlags.NoResize)

        imgui.Columns(2, "main_columns", false)
        imgui.SetColumnWidth(0, 120)

        imgui.BeginChild("left_panel", imgui.ImVec2(0, 0), true)
        local clr_active = imgui.ImVec4(1, 1, 1, 1)
        local clr_inactive = imgui.ImVec4(0.14, 0.14, 0.14, 1)

        local tabs = {
            {1, u8"��������"},
            {2, u8"�����"},
            {3, u8"������"},
            {4, u8"�����"},
            {5, u8"����������"}
        }
        for _, tab in ipairs(tabs) do
            local id, label = tab[1], tab[2]
            local isActive = (ui.activeTab == id)

            if isActive then
                imgui.PushStyleColor(imgui.Col.Button, clr_active)
                imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0, 0, 0, 1))
            else
                imgui.PushStyleColor(imgui.Col.Button, clr_inactive)
            end

            if imgui.Button(label, imgui.ImVec2(-1, 0)) then
                ui.activeTab = id
            end

            if isActive then
                imgui.PopStyleColor()
                imgui.PopStyleColor()
            else
                imgui.PopStyleColor()
            end
        end

        imgui.EndChild()
        imgui.NextColumn()

        imgui.BeginChild("right_panel", imgui.ImVec2(0, 0), true)

        -- ===== ������� "��������" =====
        if ui.activeTab == 1 then
            imgui.CenterText(u8"�������� ���������")
            imgui.Separator()

            if imgui.CollapsingHeader(u8"����� ���������", imgui.ImBool(true)) then
                if imgui.Checkbox(u8"������� ���, ����, ������, ������", ui.deletekiy) then saveIniFile() end
                imgui.SameLine(); HelpMarker("������������� ������� ������ ��������")
                if imgui.Checkbox(u8"������������� ���������� ID ������� �� /admins", ui.admcopyid) then saveIniFile() end
                imgui.SameLine(); HelpMarker("��� ������ /admins ��� ID ������� ���������� � ����� ������")
                if imgui.Checkbox(u8"���������� ID ������� � Kill List", ui.showKillIds) then saveIniFile() end
                imgui.SameLine(); HelpMarker("��������� ID ������ � Kill List`e")
                if imgui.Checkbox(u8"������� �������� �����", ui.fastMaskEnabled) then saveIniFile() end
                imgui.SameLine(); HelpMarker("��� ����� ������� (�� ��������� /fmask) ������������� ��������� ��������� � �������� �����")
                if ui.fastMaskEnabled.v then
                    imgui.PushItemWidth(120)
                    if imgui.InputText(u8"##fastMaskCmd", ui.fastMaskCommand) then saveIniFile() end
                end
                imgui.Separator()
                if imgui.Checkbox(u8"���������� ����� ��� ����� � �����������", ui.autogiverank) then saveIniFile() end
                imgui.SameLine(); HelpMarker("������������� ����� ���� ������ ��������� ��� ��������� ������/�������/������. ���������� ��������: 1�9.")
                if ui.autogiverank.v then
                    imgui.Text(u8"���� ��� ������:"); imgui.SameLine()
                    imgui.PushItemWidth(100)
                    if imgui.InputInt(u8"##giverankValue", ui.giverankValue) then
                        if ui.giverankValue.v < 1 then ui.giverankValue.v = 1 end
                        if ui.giverankValue.v > 9 then ui.giverankValue.v = 9 end
                        saveIniFile()
                    end
                end
                imgui.Separator()
                if imgui.Checkbox(u8"�������� ����������", ui.captureEnabled) then
                    saveIniFile()
                    if not ui.captureEnabled.v and data.captureActive then stopCaptureFlood() end
                end
                imgui.SameLine(); HelpMarker("������������� ���������� ������� ������� � ���������")
                if ui.captureEnabled.v then
                    imgui.Text(u8"�������:"); imgui.SameLine()
                    imgui.PushItemWidth(200)
                    if imgui.InputText(u8"##captureCommand", ui.captureCommand) then saveIniFile() end
                    imgui.Text(u8"������� ���/����:"); imgui.SameLine()
                    imgui.PushItemWidth(70)
                    if imgui.HotKey('##captureHotkey', ui.captureHotkey, tLastKeys, 100) then saveIniFile() end
                    imgui.Text(u8"�������� (��):"); imgui.SameLine()
                    imgui.PushItemWidth(100)
                    if imgui.InputInt(u8"##captureDelay", ui.captureDelay) then
                        if ui.captureDelay.v < 50 then ui.captureDelay.v = 50 end
                        saveIniFile()
                    end
                end
                imgui.Separator()
                if imgui.Checkbox(u8"������� ��� ������� ������ ������", ui.frangEnabled) then
                    saveIniFile()
                end
                imgui.SameLine(); HelpMarker("������, � ������� ��� ���� ������� ���� (������ � ����� ��� ������), ����� ���������.")
                if ui.frangEnabled.v then
                    imgui.PushItemWidth(150)
                    if imgui.InputText(u8"##frangCommand", ui.frangCommand) then
                        saveIniFile()
                    end
                    imgui.PopItemWidth()
                end
                imgui.Separator()
                imgui.Text(u8"HouseLine:"); imgui.SameLine()
                if data.houseLineActivated then
                    if imgui.Checkbox(u8"##houseLineEnable", ui.houseLineEnabled) then
                        data.houseLineEnabled = ui.houseLineEnabled.v
                    end
                    imgui.SameLine(); HelpMarker("�������� ����������� ����� � ������������ ����� � �������������� �������")
                else
                    imgui.PushStyleVar(imgui.StyleVar.Alpha, 0.4)
                    imgui.Checkbox(u8"##houseLineEnable", ui.houseLineEnabled)
                    imgui.PopStyleVar()
                    imgui.SameLine(); HelpMarker("��� ��������� ������� ������")
                end
                imgui.SameLine()
                if not data.houseLineActivated then
                    imgui.PushItemWidth(120)
                    imgui.InputText(u8"##hlPass", ui.houseLinePassword, imgui.InputTextFlags.Password)
                    imgui.PopItemWidth()
                    imgui.SameLine()
                    if imgui.Button(u8"������������") then
                        if ui.houseLinePassword.v == "1221" then
                            data.houseLineActivated = true
                            data.houseLineEnabled = true
                            ui.houseLineEnabled.v = true
                            ui.houseLinePassword.v = ""
                            sampAddChatMessage("{008080}[CrimeManager] {00ff00}HouseLine �����������.", -1)
                        else
                            sampAddChatMessage("{008080}[CrimeManager] {ff0000}�������� ������!", -1)
                        end
                    end
                else
                    if imgui.Button(u8"�������������� HouseLine") then
                        data.houseLineActivated = false
                        data.houseLineEnabled = false
                        ui.houseLineEnabled.v = false
                        sampAddChatMessage("{008080}[CrimeManager] {ffff00}HouseLine �������������.", -1)
                    end
                end

                -- ==== ���� BANK ====
                imgui.Separator()
                if imgui.Checkbox(u8"���������� ������� ������", ui.bankEnabled) then
                    saveIniFile()
                end
                imgui.SameLine(); HelpMarker("���������� �� ������ ������ ������� ����� (LS, SF, LV) �� ���������� ����������. /banksend ��� �������� ������� � /f")
                if ui.bankEnabled.v then
                    imgui.Text(u8"������ ������:"); imgui.SameLine()
                    imgui.PushItemWidth(82)
                    if imgui.InputInt(u8"##bankSize", ui.bankSize) then
                        if ui.bankSize.v < 5 then ui.bankSize.v = 5 end
                        if ui.bankSize.v > 30 then ui.bankSize.v = 30 end
                        data.bank_font = renderCreateFont('Arial', ui.bankSize.v, 13)
                        saveIniFile()
                    end
                    imgui.SameLine()
                    if imgui.Button(u8"������ �����������##bankMove") then
                        if not data.drag_mode then
                            data.drag_mode = true
                            data.drag_type = "bank"
                            data.drag_saved_x = ui.bankX.v
                            data.drag_saved_y = ui.bankY.v
                            sampAddChatMessage("{008080}[CrimeManager] {ffffff}�������� ����� ��� �����������, ��� - ���������, ESC - ��������.", -1)
                        end
                    end
                end

                -- ==== ���� ZONE ====
                imgui.Separator()
                if imgui.Checkbox(u8"���������� ������ ����", ui.zoneEnabled) then
                    saveIniFile()
                end
                imgui.SameLine(); HelpMarker("���������� ������� ��������� ��������: '� ����' (������) ��� '��� ����' (�������).")
                if ui.zoneEnabled.v then
                    imgui.Text(u8"������ ������:"); imgui.SameLine()
                    imgui.PushItemWidth(82)
                    if imgui.InputInt(u8"##zoneSize", ui.zoneSize) then
                        if ui.zoneSize.v < 5 then ui.zoneSize.v = 5 end
                        if ui.zoneSize.v > 30 then ui.zoneSize.v = 30 end
                        data.zone_font = renderCreateFont('Arial', ui.zoneSize.v, 13)
                        saveIniFile()
                    end
                    imgui.SameLine()
                    if imgui.Button(u8"������ �����������##zoneMove") then
                        if not data.drag_mode then
                            data.drag_mode = true
                            data.drag_type = "zone"
                            data.drag_saved_x = ui.zoneX.v
                            data.drag_saved_y = ui.zoneY.v
                            sampAddChatMessage("{008080}[CrimeManager] {ffffff}�������� ����� ��� �����������, ��� - ���������, ESC - ��������.", -1)
                        end
                    end
                end
            end

            if imgui.CollapsingHeader(u8"��������� ��� ��������", imgui.ImBool(true)) then
                if imgui.Checkbox(u8"�� ���������� SMS �� ��������������", ui.smskontr) then saveIniFile() end
                imgui.SameLine(); HelpMarker("�������� SMS-��������� �� �������������� � ����")
                if imgui.Checkbox(u8"�� ���������� ����������� � ��������� ��������������", ui.uvedkontr) then saveIniFile() end
                imgui.SameLine(); HelpMarker("�������� ����������� � ��������� ��������������")
                if imgui.Checkbox(u8"��� �������� ���� ���� �������������� �� �����", ui.autobar) then saveIniFile() end
                imgui.SameLine(); HelpMarker("������������� ��������� ��� ��� ��� ��������")
                if imgui.Checkbox(u8"������������� ����� � ���� M4 ��� ������� �� ����������", ui.autom4g) then saveIniFile() end
                imgui.SameLine(); HelpMarker("��� ������� �� ������������ ������� ������������� ������ M4")
                imgui.Text(u8"������� �������/��������� ����� /materials get � /bput:"); imgui.SameLine()
                imgui.PushItemWidth(70)
                if imgui.InputText(u8"##automget", ui.automget) then
                    sampUnregisterChatCommand(mainIni.maincfg.automget)
                    saveIniFile()
                    sampRegisterChatCommand(mainIni.maincfg.automget, function()
                        data.activeautoload = not data.activeautoload
                        data.proccesautoload = data.activeautoload
                        sampAddChatMessage("{008080}[CrimeManager] {ffffff}���� /materials get � /bput "..(data.activeautoload and "�������" or "����������")..".", -1)
                    end)
                end
                imgui.PopItemWidth()
                imgui.SameLine(); HelpMarker("������� ��� ���������/���������� ����� ���������� � �����")
            end

            if imgui.CollapsingHeader(u8"��������� ��� �����", imgui.ImBool(true)) then
                if imgui.Checkbox(u8"������������ ������", ui.autoWarehouseEnabled) then saveIniFile() end
                imgui.SameLine(); HelpMarker("��� ���������� ����� ��������� �����, ������ ����� ���������")
                if ui.autoWarehouseEnabled.v then
                    imgui.Text(u8"�������:"); imgui.SameLine()
                    imgui.PushItemWidth(150)
                    if imgui.InputText(u8"##warehouseTrigger", ui.warehouseTriggerWord) then saveIniFile() end
                    imgui.Text(u8"�������:"); imgui.SameLine()
                    imgui.PushItemWidth(120)
                    if imgui.InputText(u8"##warehouseCommand", ui.warehouseCommand) then saveIniFile() end
                    imgui.Text(u8"�������� (���):"); imgui.SameLine()
                    imgui.PushItemWidth(70)
                    if imgui.InputInt(u8"##warehouseDelay", ui.warehouseDelay) then
                        if ui.warehouseDelay.v < 1 then ui.warehouseDelay.v = 1 end
                        saveIniFile()
                    end
                end
                if imgui.Checkbox(u8"����������� ����������� ��", ui.autoFixcarEnabled) then saveIniFile() end
                imgui.SameLine(); HelpMarker("��� ���������� ����� ���������� ������� �������� �� � ��������� ����� � /f")
                if ui.autoFixcarEnabled.v then
                    imgui.Text(u8"�������:"); imgui.SameLine()
                    imgui.PushItemWidth(150)
                    if imgui.InputText(u8"##fixcarTrigger", ui.fixcarTriggerWord) then saveIniFile() end
                    imgui.Text(u8"�������:"); imgui.SameLine()
                    imgui.PushItemWidth(120)
                    if imgui.InputText(u8"##fixcarCommand", ui.fixcarCommand) then saveIniFile() end
                end
                imgui.Separator()
                if imgui.Checkbox(u8"�������� �������� Burrito", ui.matsputEnabled) then
                    saveIniFile()
                    if not ui.matsputEnabled.v and data.matsputActive then stopMatsPutFlood() end
                end
                imgui.SameLine(); HelpMarker("������� ��� ���������/���������� ����� �� ���")
                if ui.matsputEnabled.v then
                    imgui.Text(u8"�������:"); imgui.SameLine()
                    imgui.PushItemWidth(150)
                    if imgui.InputText(u8"##matsputCmd", ui.matsputCmd) then
                        saveIniFile()
                    end
                    imgui.Text(u8"�������� (��):"); imgui.SameLine()
                    imgui.PushItemWidth(100)
                    if imgui.InputInt(u8"##matsputDelay", ui.matsputDelay) then
                        if ui.matsputDelay.v < 50 then ui.matsputDelay.v = 50 end
                        saveIniFile()
                    end
                end
            end

            -- ===== ��������� ��� ����� (� AMMO) =====
            if imgui.CollapsingHeader(u8"��������� ��� �����", imgui.ImBool(true)) then
                if imgui.Checkbox(u8"����������������� ������� ����� ������", ui.autoleech) then saveIniFile() end
                imgui.SameLine(); HelpMarker("����� ����������� ������������� ���������� /healme �� ������� �������������� ��������")
                if imgui.Checkbox(u8"�������� ��������� � �������� �����������", ui.mafiaDelivery) then saveIniFile() end
                imgui.SameLine(); HelpMarker("�������� ��������� '���� ����� �������� ����� �� �������� �����������'")
                
                -- ==== ���� AMMO ====
                imgui.Separator()
                if imgui.Checkbox(u8"���������� ������� AMMO", ui.ammoEnabled) then
                    saveIniFile()
                end
                imgui.SameLine(); HelpMarker("���������� �� ������ ������ ������� AMMO. /ammosend ��� �������� ������� � /f")
                if ui.ammoEnabled.v then
                    imgui.Text(u8"������ ������:"); imgui.SameLine()
                    imgui.PushItemWidth(82)
                    if imgui.InputInt(u8"##ammoSize", ui.ammoSize) then
                        if ui.ammoSize.v < 5 then ui.ammoSize.v = 5 end
                        if ui.ammoSize.v > 30 then ui.ammoSize.v = 30 end
                        data.ammo_font = renderCreateFont('Arial', ui.ammoSize.v, 13)
                        saveIniFile()
                    end
                    imgui.SameLine()
                    if imgui.Button(u8"������ �����������##ammoMove") then
                        if not data.drag_mode then
                            data.drag_mode = true
                            data.drag_type = "ammo"
                            data.drag_saved_x = ui.ammoX.v
                            data.drag_saved_y = ui.ammoY.v
                            sampAddChatMessage("{008080}[CrimeManager] {ffffff}�������� ����� ��� �����������, ��� - ���������, ESC - ��������.", -1)
                        end
                    end
                end
            end

            if imgui.CollapsingHeader(u8"��������� �����", imgui.ImBool(true)) then
                if imgui.Checkbox(u8"�������� ��������� � �������� ������", ui.hideFamilyEvent) then saveIniFile() end
                imgui.SameLine(); HelpMarker("�������� ��� ��������� � ������ ��������� ������ (�� 5 �� 1 ������ � �����)")
            end

            if imgui.CollapsingHeader(u8"��������� ������� � ������", imgui.ImBool(true)) then
                if imgui.Checkbox(u8"�������� ������� �������/������", ui.weather_enabled) then
                    if ui.weather_enabled.v then registerWeatherCommands() else unregisterWeatherCommands(); setTimeLock(false); setWeatherLock(false) end
                    saveIniFile()
                end
                if ui.weather_enabled.v then
                    imgui.Text(u8"������� ��������� ������� (0-23):"); imgui.SameLine()
                    imgui.PushItemWidth(150)
                    if imgui.InputText(u8"##stime_cmd", ui.stime_cmd) then unregisterWeatherCommands(); registerWeatherCommands(); saveIniFile() end
                    imgui.PopItemWidth()
                    imgui.SameLine(); HelpMarker("��������: stime 12")
                    imgui.Text(u8"������� ��������� ������ (0-45):"); imgui.SameLine()
                    imgui.PushItemWidth(150)
                    if imgui.InputText(u8"##sweat_cmd", ui.sweat_cmd) then unregisterWeatherCommands(); registerWeatherCommands(); saveIniFile() end
                    imgui.PopItemWidth()
                    imgui.SameLine(); HelpMarker("��������: sweat 10")
                    imgui.Text(u8"������� ���������� �������:"); imgui.SameLine()
                    imgui.PushItemWidth(150)
                    if imgui.InputText(u8"##btime_cmd", ui.btime_cmd) then unregisterWeatherCommands(); registerWeatherCommands(); saveIniFile() end
                    imgui.PopItemWidth()
                    imgui.SameLine(); HelpMarker("��������� ������� �����")
                    imgui.Text(u8"������� ���������� ������:"); imgui.SameLine()
                    imgui.PushItemWidth(150)
                    if imgui.InputText(u8"##bweat_cmd", ui.bweat_cmd) then unregisterWeatherCommands(); registerWeatherCommands(); saveIniFile() end
                    imgui.PopItemWidth()
                    imgui.SameLine(); HelpMarker("��������� ������� ������")
                end
            end

        -- ===== ������� "�����" =====
        elseif ui.activeTab == 2 then
            imgui.CenterText(u8"���������� ������� �����������")
            imgui.Separator()
            imgui.Text(u8"�������� �������:")
            imgui.Separator()
            local btnWidth = (imgui.GetWindowWidth() - 40) / 2
            local bikersActive = (data.selectedFaction == "bikers")
            local ghettoActive = (data.selectedFaction == "ghetto")

            if bikersActive then
                imgui.PushStyleColor(imgui.Col.Button, clr_active)
                imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0,0,0,1))
            else
                imgui.PushStyleColor(imgui.Col.Button, clr_inactive)
            end
            if imgui.Button(u8"������� (6-8 �����)", imgui.ImVec2(btnWidth, 0)) then
                data.selectedFaction = "bikers"
            end
            if bikersActive then
                imgui.PopStyleColor()
                imgui.PopStyleColor()
            else
                imgui.PopStyleColor()
            end
            imgui.SameLine()

            if ghettoActive then
                imgui.PushStyleColor(imgui.Col.Button, clr_active)
                imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0,0,0,1))
            else
                imgui.PushStyleColor(imgui.Col.Button, clr_inactive)
            end
            if imgui.Button(u8"�����/����� (7-9 �����)", imgui.ImVec2(btnWidth, 0)) then
                data.selectedFaction = "ghetto"
            end
            if ghettoActive then
                imgui.PopStyleColor()
                imgui.PopStyleColor()
            else
                imgui.PopStyleColor()
            end

            imgui.Separator()

            local members = {}
            local ranks = {}
            local rangeText = ""
            local targetRank = 5
            local factionName = ""

            if data.selectedFaction == "bikers" then
                members = data.offmembers
                ranks = data.offmembersrangs
                rangeText = "6-8"
                targetRank = 5
                factionName = "��������"
            elseif data.selectedFaction == "ghetto" then
                for i=1, #data.ghettoMembers do
                    table.insert(members, data.ghettoMembers[i])
                    table.insert(ranks, data.ghettoRangs[i])
                end
                for i=1, #data.mafiaMembers do
                    table.insert(members, data.mafiaMembers[i])
                    table.insert(ranks, data.mafiaRangs[i])
                end
                rangeText = "7-9"
                targetRank = 6
                factionName = "�����/�����"
            end

            imgui.Text(u8("������ ������� ���������� (" .. rangeText .. " �����):"))
            imgui.SameLine()
            if imgui.Button(u8"��������") then
                if data.selectedFaction == "bikers" then
                    data.offmembers = {}; data.offmembersrangs = {}
                    data.collectingFor = "bikers"
                    sampSendChat("/offmembers")
                elseif data.selectedFaction == "ghetto" then
                    data.ghettoMembers = {}; data.ghettoRangs = {}
                    data.mafiaMembers = {}; data.mafiaRangs = {}
                    data.collectingFor = "ghetto"
                    sampSendChat("/offmembers")
                end
                sampAddChatMessage("{008080}[CrimeManager] {ffffff}���������� ������ "..factionName.."...", -1)
            end

            imgui.Separator()

            if #members == 0 then
                imgui.CenterText(u8"������ ����. ������� '��������' ��� ��������.")
            else
                imgui.BeginChild("leader_list", imgui.ImVec2(0, 200), true)
                for i=1, #members do
                    imgui.Text(u8(i..". "..members[i].." - ����: "..ranks[i]))
                    imgui.SameLine()
                    if imgui.Button(u8("�������� �� "..targetRank.." �����##"..i)) then
                        sampSendChat("/offgiverank "..members[i].." "..targetRank)
                        sampAddChatMessage("{008080}[CrimeManager] {ffffff}"..members[i].." ������� �� "..targetRank.." �����.", -1)
                    end
                end
                imgui.EndChild()
                imgui.Separator()
                imgui.Text(u8("�����: " .. #members .. " ����������"))
            end

        -- ===== ������� "������" =====
        elseif ui.activeTab == 3 then
            imgui.CenterText(u8"������")
            imgui.Separator()
            if #binders == 0 then
                imgui.CenterText(u8"��� ��������. ������� ����������.")
            else
                imgui.Columns(6, "binder_columns", false)
                imgui.SetColumnWidth(0, 45)
                imgui.SetColumnWidth(1, 120)
                imgui.SetColumnWidth(2, 430)
                imgui.SetColumnWidth(3, 55)
                imgui.SetColumnWidth(4, 100)
                imgui.SetColumnWidth(5, 210)
                imgui.Text(u8"���."); imgui.NextColumn()
                imgui.Text(u8"�������"); imgui.NextColumn()
                imgui.Text(u8"�������"); imgui.NextColumn()
                imgui.Text(u8"����"); imgui.NextColumn()
                imgui.Text(u8"���. (���)"); imgui.NextColumn()
                imgui.Text(u8"��������"); imgui.NextColumn()
                imgui.Separator()
                for i, b in ipairs(binders) do
                    imgui.PushID(i)
                    local activeBool = imgui.ImBool(b.active)
                    if imgui.Checkbox(u8"##active"..i, activeBool) then
                        b.active = activeBool.v
                        updateBinder(i)
                    end
                    imgui.NextColumn()
                    imgui.Text(u8(keyCodeToName(b.keyCode)))
                    imgui.NextColumn()
                    imgui.PushItemWidth(-1)
                    local cmdBuffer = imgui.ImBuffer(b.command, 256)
                    if imgui.InputText(u8"##cmd"..i, cmdBuffer) then
                        b.command = cmdBuffer.v
                        updateBinder(i)
                    end
                    imgui.PopItemWidth()
                    imgui.NextColumn()
                    local floodBool = imgui.ImBool(b.flood)
                    if imgui.Checkbox(u8"##flood"..i, floodBool) then
                        b.flood = floodBool.v
                        updateBinder(i)
                    end
                    imgui.NextColumn()
                    imgui.PushItemWidth(70)
                    local intervalInt = imgui.ImInt(b.interval)
                    if imgui.InputInt(u8"##interval"..i, intervalInt) then
                        if intervalInt.v < 1 then intervalInt.v = 1 end
                        if intervalInt.v > 120 then intervalInt.v = 120 end
                        b.interval = intervalInt.v
                        updateBinder(i)
                    end
                    imgui.PopItemWidth()
                    imgui.NextColumn()
                    if imgui.Button(u8"���������") then startRecordingBinder(i) end
                    imgui.SameLine()
                    if imgui.Button(u8"�������") then
                        removeBinder(i)
                        imgui.PopID()
                        break
                    end
                    imgui.NextColumn()
                    imgui.PopID()
                end
                imgui.Columns(1)
            end
            imgui.Separator()
            if imgui.Button(u8"�������� ����� ������") then addEmptyBinder() end

        -- ===== ������� "�����" =====
        elseif ui.activeTab == 4 then
            imgui.CenterText(u8"���������� ������")
            imgui.Separator()
            if imgui.Button(u8"�������� ������ ����� (������ �������)", imgui.ImVec2(-1, 0)) then
                data.familyMembers = {}
                data.waitingForFamily = true
                sampSendChat("/offfmembers")
                sampAddChatMessage("{008080}[CrimeManager] {ffffff}������ /offfmembers ���������...", -1)
                lua_thread.create(function()
                    wait(2000)
                    data.waitingForFamily = false
                end)
            end
            imgui.SameLine(); HelpMarker("����������� ������ ������� ���������� ����� ����� /offfmembers")
            imgui.Separator()
            imgui.Text(u8("��������� ����� ("..#data.familyMembers.."):"))
            if #data.familyMembers == 0 then
                imgui.Text(u8"������ ����. ��������.")
            else
                imgui.BeginChild("family_list", imgui.ImVec2(0, 150), true)
                for i, nick in ipairs(data.familyMembers) do
                    imgui.Text(u8(i..". "..nick))
                end
                imgui.EndChild()
            end
            imgui.Separator()
            imgui.Text(u8"������� ���� ��� �������� (������ � ����� ������):")
            imgui.InputTextMultiline("##familyCheckInput", ui.familyInput, imgui.ImVec2(-1, 120))
            if imgui.Button(u8"��������� ������� � �����", imgui.ImVec2(-1, 0)) then
                local text = ui.familyInput.v
                local nicks = {}
                for line in text:gmatch("[^\r\n]+") do
                    local nick = line:gsub("^%s+", ""):gsub("%s+$", "")
                    if nick ~= "" then
                        table.insert(nicks, nick)
                    end
                end
                if #nicks == 0 then
                    sampAddChatMessage("{008080}[CrimeManager] {ff0000}������� ���� �� ���� ���.", -1)
                else
                    local missing = {}
                    for _, nick in ipairs(nicks) do
                        local found = false
                        for _, member in ipairs(data.familyMembers) do
                            if member:lower() == nick:lower() then
                                found = true
                                break
                            end
                        end
                        if not found then
                            table.insert(missing, nick)
                        end
                    end

                    if #missing == 0 then
                        sampAddChatMessage("{008080}[CrimeManager] {00ff00}��� ��������� ������ ������� � ����� (�� ������ /offfmembers).", -1)
                    else
                        local chunkSize = 6
                        for i = 1, #missing, chunkSize do
                            local chunk = {}
                            for j = i, math.min(i + chunkSize - 1, #missing) do
                                table.insert(chunk, missing[j])
                            end
                            local prefix = (i == 1 and "{FF0000}� ����� �����������: " or "{FF0000}                           ")
                            local msg = prefix .. table.concat(chunk, ", ")
                            sampAddChatMessage("{008080}[CrimeManager] " .. msg, -1)
                        end
                        sampAddChatMessage("{008080}[CrimeManager] {FFFF00}��������� ��������� ����� ���� � ����, ���������� � /id Nick_Name � /fmembers", -1)
                    end
                end
            end
            imgui.SameLine(); HelpMarker("��������� �������� ���� �� ������ ����� � ������� �������������")

        -- ===== ������� "����������" =====
        elseif ui.activeTab == 5 then
            imgui.CenterText(u8"����������")
            imgui.Separator()
            imgui.TextWrapped(u8"�����������/�����: vk.com/quinter")
            imgui.TextWrapped(u8"������ ���������: vk.com/territory_ghetto")
            imgui.TextWrapped(u8"YouTube: www.youtube.com/@offquinter")
            imgui.Separator()
            imgui.TextWrapped(u8"������� �� �������������! test")
        end

        imgui.EndChild()
        imgui.Columns(1)
        imgui.End()
    end
end

-- ============================================================
-- �����
-- ============================================================
function apply_custom_style()
    local style = imgui.GetStyle()
    local colors = style.Colors
    local clr = imgui.Col
    local ImVec4 = imgui.ImVec4

    style.WindowRounding = 8
    style.WindowTitleAlign = imgui.ImVec2(0.5, 0.5)
    style.ChildWindowRounding = 5
    style.FrameRounding = 4
    style.ItemSpacing = imgui.ImVec2(6, 5)
    style.ScrollbarSize = 14
    style.ScrollbarRounding = 4
    style.GrabMinSize = 10
    style.GrabRounding = 3
    style.WindowPadding = imgui.ImVec2(6, 6)
    style.FramePadding = imgui.ImVec2(4, 4)
    style.ButtonTextAlign = imgui.ImVec2(0.5, 0.5)

    colors[clr.WindowBg]          = imgui.ImColor(30, 10, 10):GetVec4()
    colors[clr.ChildWindowBg]     = imgui.ImColor(45, 15, 15):GetVec4()
    colors[clr.PopupBg]           = imgui.ImColor(35, 10, 10, 240):GetVec4()
    colors[clr.Border]            = imgui.ImColor(120, 30, 30):GetVec4()
    colors[clr.BorderShadow]      = ImVec4(0,0,0,0)
    colors[clr.Text]              = ImVec4(1, 0.85, 0.85, 1)
    colors[clr.TextDisabled]      = ImVec4(0.6, 0.4, 0.4, 1)
    colors[clr.TitleBg]           = imgui.ImColor(160, 30, 30):GetVec4()
    colors[clr.TitleBgActive]     = imgui.ImColor(200, 40, 40):GetVec4()
    colors[clr.TitleBgCollapsed]  = imgui.ImColor(50, 15, 15):GetVec4()
    colors[clr.Button]            = imgui.ImColor(80, 20, 20):GetVec4()
    colors[clr.ButtonHovered]     = imgui.ImColor(180, 40, 40):GetVec4()
    colors[clr.ButtonActive]      = imgui.ImColor(220, 60, 60):GetVec4()
    colors[clr.FrameBg]           = imgui.ImColor(60, 20, 20):GetVec4()
    colors[clr.FrameBgHovered]    = imgui.ImColor(80, 25, 25):GetVec4()
    colors[clr.FrameBgActive]     = imgui.ImColor(100, 30, 30):GetVec4()
    colors[clr.CheckMark]         = imgui.ImColor(220, 50, 50):GetVec4()
    colors[clr.SliderGrab]        = imgui.ImColor(200, 50, 50):GetVec4()
    colors[clr.SliderGrabActive]  = imgui.ImColor(240, 70, 70):GetVec4()
    colors[clr.ScrollbarBg]       = imgui.ImColor(40, 12, 12):GetVec4()
    colors[clr.ScrollbarGrab]     = imgui.ImColor(120, 30, 30):GetVec4()
    colors[clr.ScrollbarGrabHovered] = imgui.ImColor(160, 40, 40):GetVec4()
    colors[clr.ScrollbarGrabActive]  = imgui.ImColor(200, 50, 50):GetVec4()
    colors[clr.Header]            = imgui.ImColor(140, 30, 30):GetVec4()
    colors[clr.HeaderHovered]     = imgui.ImColor(180, 40, 40):GetVec4()
    colors[clr.HeaderActive]      = imgui.ImColor(200, 50, 50):GetVec4()
    colors[clr.Separator]         = imgui.ImColor(100, 25, 25):GetVec4()
    colors[clr.SeparatorHovered]  = imgui.ImColor(200, 50, 50):GetVec4()
    colors[clr.SeparatorActive]   = imgui.ImColor(220, 60, 60):GetVec4()
    colors[clr.ResizeGrip]        = imgui.ImColor(140, 30, 30):GetVec4()
    colors[clr.ResizeGripHovered] = imgui.ImColor(180, 40, 40):GetVec4()
    colors[clr.ResizeGripActive]  = imgui.ImColor(200, 50, 50):GetVec4()
    colors[clr.PlotLines]         = imgui.ImColor(200, 50, 50):GetVec4()
    colors[clr.PlotLinesHovered]  = imgui.ImColor(230, 70, 70):GetVec4()
    colors[clr.PlotHistogram]     = imgui.ImColor(200, 50, 50):GetVec4()
    colors[clr.PlotHistogramHovered] = imgui.ImColor(230, 70, 70):GetVec4()
    colors[clr.TextSelectedBg]    = imgui.ImColor(180, 40, 40, 80):GetVec4()
    colors[clr.ModalWindowDarkening] = imgui.ImColor(0,0,0,160):GetVec4()
end
apply_custom_style()