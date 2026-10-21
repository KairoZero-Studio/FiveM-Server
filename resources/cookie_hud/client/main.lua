local lastHealth = -1
local lastArmor = -1
local hunger = 100
local thirst = 100
local playerNick = nil

local function sendNeeds()
    SendNUIMessage({ action = 'updateNeeds', hunger = hunger, thirst = thirst })
end

AddStateBagChangeHandler('hunger', ('player:%s'):format(cache.serverId), function(_, _, value)
    hunger = value or 100
    sendNeeds()
end)

AddStateBagChangeHandler('thirst', ('player:%s'):format(cache.serverId), function(_, _, value)
    thirst = value or 100
    sendNeeds()
end)

local lastStamina = -1
local lastOxygen = -1
local lastUnderwater = false

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local health = math.max(0, math.min(100, GetEntityHealth(ped) - 100))
        local armor = math.max(0, math.min(100, GetPedArmour(ped)))
        local stamina = math.max(0, math.min(100, math.floor(GetPlayerSprintStaminaRemaining(PlayerId()) + 0.5)))
        local underwater = IsPedSwimmingUnderWater(ped)
        local oxygen = 100

        if underwater then
            local remaining = tonumber(GetPlayerUnderwaterTimeRemaining(PlayerId())) or 0.0
            oxygen = math.max(0, math.min(100, math.floor((remaining / 10.0) * 100.0 + 0.5)))
        end

        if health ~= lastHealth or armor ~= lastArmor or stamina ~= lastStamina
            or oxygen ~= lastOxygen or underwater ~= lastUnderwater then
            SendNUIMessage({
                action = 'updateStatus',
                health = health,
                armor = armor,
                stamina = stamina,
                oxygen = oxygen,
                underwater = underwater,
            })
            lastHealth = health
            lastArmor = armor
            lastStamina = stamina
            lastOxygen = oxygen
            lastUnderwater = underwater
        end
        Wait(180)
    end
end)


CreateThread(function()
    local lastLocation = nil
    while true do
        Wait(700)
        if isLoaded and not cameraModeHidden then
            local ped = PlayerPedId()
            local c = GetEntityCoords(ped)
            local streetHash, crossingHash = GetStreetNameAtCoord(c.x, c.y, c.z)
            local street = streetHash and GetStreetNameFromHashKey(streetHash) or ''
            local crossing = crossingHash and crossingHash ~= 0 and GetStreetNameFromHashKey(crossingHash) or ''
            local zoneCode = GetNameOfZone(c.x, c.y, c.z)
            local zone = zoneCode and GetLabelText(zoneCode) or ''
            if zone == 'NULL' then zone = '' end
            local label = street
            if crossing ~= '' and crossing ~= street then label = label ~= '' and (label .. ' / ' .. crossing) or crossing end
            if zone ~= '' then label = label ~= '' and (zone .. ' · ' .. label) or zone end
            if label ~= lastLocation then
                lastLocation = label
                SendNUIMessage({ action = 'updateLocation', text = label })
            end
        end
    end
end)

local isLoaded = false
local cameraModeHidden = LocalPlayer.state.cookieCameraMode == true

local jobDisplay = nil

local function buildInfoPayload(data)
    local head = LocalPlayer.state.ckHead
    return {
        action = 'updateInfo',

        job = (jobDisplay and jobDisplay ~= '' and jobDisplay)
            or (data.job and data.job.label)
            or '백수',

        name = (playerNick and playerNick ~= '' and playerNick)
            or (head and head.nick and head.nick ~= '' and head.nick)
            or '-',

        gobun = (head and head.gobun) and (tostring(head.gobun) .. '번') or '-',
        cash = (data.money and data.money.cash) or 0,
        bank = (data.money and data.money.bank) or 0,
    }
end

local function updatePlayerInfo()
    local data = exports.qbx_core:GetPlayerData()
    if not data then return end
    SendNUIMessage(buildInfoPayload(data))

end

RegisterNetEvent('cookie_admin:client:jobDisplay', function(txt)
    jobDisplay = txt

    if isLoaded then updatePlayerInfo() end
end)

RegisterNetEvent('cookie_hud:setName', function(nick)
    playerNick = nick

    TriggerServerEvent('cookie_admin:server:requestJobDisplay')
    if isLoaded then updatePlayerInfo() end
end)

RegisterNetEvent('cookie_hud:setClock', function(data)
    SendNUIMessage({ action = 'updateInfoBar', text = data.text, players = data.players })
end)

local TAG_DIST = 22.0
local TAG_FADE = 16.0

-- 진행 중 강도 범위 안에 있는 플레이어는 이름/고번/직업 등 머리 위 태그를 표시하지 않는다.
-- cookie_robbery가 GlobalState.cookieRobberyNameHideZones 로 범위를 동기화한다.
local robberyNameHideZones = {}

local function refreshRobberyNameHideZones()
    local raw = GlobalState.cookieRobberyNameHideZones
    robberyNameHideZones = type(raw) == 'table' and raw or {}
end

local function pointInsidePolygon2D(coords,points)
    if type(points)~='table' or #points<3 then return false end
    local inside=false
    local j=#points
    for i=1,#points do
        local pi,pj=points[i],points[j]
        local xi,yi=tonumber(pi.x),tonumber(pi.y)
        local xj,yj=tonumber(pj.x),tonumber(pj.y)
        if xi and yi and xj and yj then
            local crosses=((yi>coords.y)~=(yj>coords.y))
                and (coords.x < (xj-xi)*(coords.y-yi)/((yj-yi)+0.0000001)+xi)
            if crosses then inside=not inside end
        end
        j=i
    end
    return inside
end

local function isInsideRobberyNameHideZone(coords)
    if type(robberyNameHideZones)~='table' then return false end
    for _,zone in pairs(robberyNameHideZones) do
        if tostring(zone.boundaryMode or 'circle')=='polygon'
            and type(zone.boundaryPoints)=='table' and #zone.boundaryPoints>=3 then
            if pointInsidePolygon2D(coords,zone.boundaryPoints) then return true end
        else
            local radius=tonumber(zone.radius) or 0.0
            if radius>0.0 then
                local dx=coords.x-(tonumber(zone.x) or 0.0)
                local dy=coords.y-(tonumber(zone.y) or 0.0)
                if (dx*dx+dy*dy)<=(radius*radius) then return true end
            end
        end
    end
    return false
end

CreateThread(function()
    while true do
        refreshRobberyNameHideZones()
        Wait(350)
    end
end)

local showSelfTag = false

RegisterKeyMapping('cookiehud_nametag', '내 네임태그 표시/숨김', 'keyboard', 'TAB')
RegisterCommand('cookiehud_nametag', function()
    showSelfTag = not showSelfTag
    TriggerEvent('cookie_admin:client:notify',
        showSelfTag and '내 네임태그를 표시합니다' or '내 네임태그를 숨깁니다', false)
end, false)

CreateThread(function()

    Wait(3000)
    TriggerServerEvent('cookie_admin:server:requestNameTag')
end)

CreateThread(function()
    while true do
        local tags = {}

        if isLoaded and not cameraModeHidden and not IsPauseMenuActive() then
            local myPed = PlayerPedId()
            local myCoords = GetEntityCoords(myPed)

            for _, pid in ipairs(GetActivePlayers()) do
                local ped = GetPlayerPed(pid)

                local isMe = (ped == myPed)
                if (not isMe or showSelfTag) and DoesEntityExist(ped) and not IsEntityDead(ped) then
                    local coords = GetEntityCoords(ped)
                    local dist = #(coords - myCoords)

                    -- 강도 범위 안의 대상은 관리자/경찰/시민 구분 없이 네임태그 전체 숨김.
                    local hiddenByRobbery = isInsideRobberyNameHideZone(coords)

                    if dist <= TAG_DIST and not hiddenByRobbery then
                        local st = Player(GetPlayerServerId(pid)).state.cookieTag

                        if st and st.name then

                            local head = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)
                            local onScreen, sx, sy = World3dToScreen2d(head.x, head.y, head.z + 0.32)

                            if onScreen then

                                local t = math.min(1.0, math.max(0.0, (dist - 2.0) / TAG_DIST))
                                local alpha = 1.0
                                if dist > TAG_FADE then
                                    alpha = 1.0 - ((dist - TAG_FADE) / (TAG_DIST - TAG_FADE))
                                end

                                tags[#tags + 1] = {
                                    id = GetPlayerServerId(pid),
                                    name = st.name,
                                    gobun = st.gobun,
                                    emoji = st.emoji,
                                    org = st.org,
                                    orgDuty = st.orgDuty,
                                    orgColor = st.orgColor,
                                    badge = st.badge,
                                    lover = st.lover,
                                    jobless = st.jobless,
                                    talking = (pid == PlayerId() and MumbleIsPlayerTalking(PlayerId()) == 1)
                                        or NetworkIsPlayerTalking(pid),
                                    x = sx, y = sy,
                                    scale = 1.0 - (t * 0.38),
                                    alpha = alpha,
                                }
                            end
                        end
                    end
                end
            end
        end

        SendNUIMessage({ action = 'nametags', tags = tags })
        Wait(0)
    end
end)

CreateThread(function()
    while true do
        local samples, invSum = 0, 0.0
        local start = GetGameTimer()
        while GetGameTimer() - start < 1000 do
            local ft = GetFrameTime()
            if ft > 0 then invSum = invSum + 1.0 / ft; samples = samples + 1 end
            Wait(0)
        end
        if isLoaded and samples > 0 then
            SendNUIMessage({ action = 'updateFps', fps = math.floor(invSum / samples + 0.5) })
        end
    end
end)

RegisterNetEvent('cookie_hud:setWeather', function(data)
    SendNUIMessage({ action = 'updateWeather', desc = data.desc, temp = data.temp, icon = data.icon })
end)

local function pushCameraHudState(value)
    cameraModeHidden = value == true
    SendNUIMessage({ action = 'cameraMode', active = cameraModeHidden })
end

AddStateBagChangeHandler('cookieCameraMode', ('player:%s'):format(cache.serverId), function(_, _, value)
    pushCameraHudState(value == true)
end)

CreateThread(function()
    Wait(700)
    pushCameraHudState(LocalPlayer.state.cookieCameraMode == true)
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    isLoaded = true
    SendNUIMessage({ action = 'hudVisible', visible = not cameraModeHidden })
    updatePlayerInfo()
    hunger = LocalPlayer.state.hunger or 100
    thirst = LocalPlayer.state.thirst or 100
    sendNeeds()
    TriggerServerEvent('cookie_hud:server:requestHud')
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    isLoaded = false
    SendNUIMessage({ action = 'hudVisible', visible = false })
end)

CreateThread(function()
    Wait(500)
    if not isLoaded and LocalPlayer.state.isLoggedIn then
        isLoaded = true

        local head = LocalPlayer.state.ckHead
        if (not playerNick or playerNick == '') and head and head.nick then playerNick = head.nick end
        SendNUIMessage({ action = 'hudVisible', visible = not cameraModeHidden })
        updatePlayerInfo()
        hunger = LocalPlayer.state.hunger or 100
        thirst = LocalPlayer.state.thirst or 100
        sendNeeds()
        TriggerServerEvent('cookie_hud:server:requestHud')

    end
end)

local PROX_LABEL = { '근처', '중간', '멀리' }

local function buildSpeakers()
    local me = PlayerId()
    local speakers = {}
    for _, p in ipairs(GetActivePlayers()) do
        local talking = (p == me and MumbleIsPlayerTalking(me) == 1) or (p ~= me and NetworkIsPlayerTalking(p))
        if talking then
            local sid = GetPlayerServerId(p)
            local head = (p == me) and LocalPlayer.state.ckHead or Player(sid).state.ckHead
            speakers[#speakers + 1] = {
                gobun = head and head.gobun or sid,
                nick = (head and head.nick) or GetPlayerName(p),
            }
        end
    end
    return speakers
end

CreateThread(function()
    local lastSig, lastMode, shown = nil, nil, false
    local activeUntil = 0
    while true do
        Wait(150)
        if isLoaded and not cameraModeHidden then

            local prox = LocalPlayer.state.proximity
            local idx = prox and prox.index or nil
            if idx ~= lastMode then
                if lastMode ~= nil and idx and PROX_LABEL[idx] then
                    SendNUIMessage({ action = 'voiceModeToast', label = PROX_LABEL[idx] })
                end
                lastMode = idx
            end

            local speakers = buildSpeakers()
            if #speakers > 0 then
                activeUntil = GetGameTimer() + 500
                local parts = {}
                for i = 1, #speakers do parts[i] = speakers[i].gobun .. ':' .. speakers[i].nick end
                local sig = table.concat(parts, '|')
                if sig ~= lastSig then
                    lastSig = sig
                    SendNUIMessage({ action = 'updateVoice', speakers = speakers })
                end
                shown = true
            elseif shown and GetGameTimer() >= activeUntil then
                SendNUIMessage({ action = 'hideVoice' })
                shown = false
                lastSig = nil
            end
        end
    end
end)

RegisterNetEvent('QBCore:Player:SetPlayerData', function(data)
    if not isLoaded then return end
    SendNUIMessage(buildInfoPayload(data))
end)

local HB_SLOTS = 8
local HB_IMG = 'nui://ox_inventory/web/images/%s.png'

local function buildHotbar()
    local bySlot = {}
    local ok, items = pcall(function() return exports.ox_inventory:GetPlayerItems() end)
    if ok and type(items) == 'table' then
        for _, it in pairs(items) do
            if type(it) == 'table' and it.slot and it.slot >= 1 and it.slot <= HB_SLOTS then
                bySlot[it.slot] = {
                    name = it.name,
                    count = it.count or 1,
                    image = (it.metadata and it.metadata.imageurl) or HB_IMG:format(it.name),
                }
            end
        end
    end
    local out = {}
    for i = 1, HB_SLOTS do out[i] = bySlot[i] or false end
    return out
end

local function pushHotbar()
    SendNUIMessage({ action = 'updateHotbar', slots = buildHotbar() })
end

AddEventHandler('ox_inventory:updateInventory', function() pushHotbar() end)

CreateThread(function() Wait(1500); pushHotbar() end)

local HOTKEY_CD_MS = 5000
local hotkeyCd = {}

local function hotkeyBlocked(slot)
    local exp = hotkeyCd[slot]
    return exp ~= nil and GetGameTimer() < exp
end
exports('hotkeyBlocked', hotkeyBlocked)

AddEventHandler('ox_inventory:usedItem', function(name, slot)
    if not slot or slot < 1 or slot > HB_SLOTS then return end
    if type(name) == 'string' and name:sub(1, 7) == 'WEAPON_' then return end
    hotkeyCd[slot] = GetGameTimer() + HOTKEY_CD_MS
    SendNUIMessage({ action = 'hotbarCooldown', slot = slot, ms = HOTKEY_CD_MS })
end)

AddEventHandler('ox_inventory:currentWeapon', function(weapon)
    local slot = weapon and weapon.slot
    if slot and (slot < 1 or slot > HB_SLOTS) then slot = nil end
    SendNUIMessage({ action = 'hotbarEquipped', slot = slot })
end)

for i = 6, HB_SLOTS do
    lib.addKeybind({
        name = ('ckhotkey%d'):format(i),
        description = ('핫바 %d번 사용'):format(i),
        defaultKey = tostring(i),
        onPressed = function()
            if cameraModeHidden or IsNuiFocused() or IsPauseMenuActive() then return end
            if hotkeyBlocked(i) then return end
            pcall(function() exports.ox_inventory:useSlot(i) end)
        end,
    })
end

CreateThread(function()
    local lastPaused = false
    while true do
        Wait(150)
        local paused = IsPauseMenuActive()
        if paused ~= lastPaused then
            lastPaused = paused
            SendNUIMessage({ action = 'hudVisible', visible = (not paused) and isLoaded and not cameraModeHidden or false })
        end
    end
end)

local AMMO_EXCLUDE_GROUP = {
    [`GROUP_UNARMED`] = true, [`GROUP_MELEE`] = true, [`GROUP_THROWN`] = true,
    [`GROUP_PETROLCAN`] = true, [`GROUP_FIREEXTINGUISHER`] = true,
}
local ammoLastSig, ammoLastHash

local function pushAmmo()
    local ped = PlayerPedId()
    local weapon = GetSelectedPedWeapon(ped)
    local show, clip, reserve, ammoItem = false, 0, 0, nil
    if weapon and weapon ~= `WEAPON_UNARMED` and not AMMO_EXCLUDE_GROUP[GetWeapontypeGroup(weapon)] then
        local _, inClip = GetAmmoInClip(ped, weapon)
        clip = inClip or 0
        local ok, a = pcall(function() return exports.cookie_admin:getWeaponAmmo(weapon) end)
        ammoItem = ok and a or nil
        if ammoItem then
            local sok, cnt = pcall(function() return exports.ox_inventory:Search('count', ammoItem) end)
            reserve = (sok and tonumber(cnt)) or 0
        else
            reserve = math.max(0, (GetAmmoInPedWeapon(ped, weapon) or 0) - clip)
        end
        show = true
        if weapon ~= ammoLastHash then
            ammoLastHash = weapon

        end
    else
        ammoLastHash = nil
    end
    local sig = show and (clip .. '|' .. reserve .. '|' .. tostring(ammoItem)) or 'off'
    if sig ~= ammoLastSig then
        ammoLastSig = sig
        if show then
            SendNUIMessage({ action = 'updateAmmo', clip = clip, reserve = reserve, ammo = ammoItem })
        else
            SendNUIMessage({ action = 'hideAmmo' })
        end
    end
end

CreateThread(function() while true do Wait(200); pushAmmo() end end)
AddEventHandler('ox_inventory:updateInventory', function() pushAmmo() end)

RegisterCommand('ibbottom', function(_, args)
    if not Config.Debug then return end
    local v = args[1]
    if not v then
        TriggerEvent('chat:addMessage', { args = { '^3[ibbottom]', '사용법: /ibbottom 2.8  (vh, 값↑=미니맵에 더 붙음)' } })
        return
    end
    SendNUIMessage({ action = 'setIbBottom', value = v })
    TriggerEvent('chat:addMessage', { args = { '[ibbottom]', '정보바 bottom = ' .. tostring(v) .. 'vh' } })
end, false)
