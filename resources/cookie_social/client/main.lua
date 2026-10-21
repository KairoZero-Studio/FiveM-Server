local RESOURCE = GetCurrentResourceName()
local SCULLY = 'scully_emotemenu'

local menuOpen = false
local built = false
local itemsById = {}
local favorites = {}
local loadErrors = {}

local catalog = {
    favorite = {},
    dance = {},
    action = {},
    prop = {},
    sync = {},
    walk = {},
    face = {},
}

local carry = {
    active = false,
    role = nil,
    partner = nil,
}

local function notify(message, isError)
    if lib and lib.notify then
        lib.notify({
            title = '모션 메뉴',
            description = tostring(message or ''),
            type = isError and 'error' or 'inform'
        })
        return
    end
    TriggerEvent('chat:addMessage', { args = { 'COOKIE', tostring(message or '') } })
end

local function setFocus(on)
    if on then
        if GetResourceState('cookie_core') == 'started' then
            local ok, owner = exports.cookie_core:Acquire(RESOURCE, false)
            if ok ~= true then return false, owner end
        end
        SetNuiFocus(true, true)
        if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
        return true
    end

    SetNuiFocus(false, false)
    if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
    if GetResourceState('cookie_core') == 'started' then
        exports.cookie_core:Release(RESOURCE)
    end
    return true
end

local function closeMenu()
    if not menuOpen then return end
    menuOpen = false
    setFocus(false)
    SendNUIMessage({ action = 'close' })
end

local function deepCopy(v, seen)
    if type(v) ~= 'table' then return v end
    seen = seen or {}
    if seen[v] then return seen[v] end
    local out = {}
    seen[v] = out
    for k, value in pairs(v) do
        out[deepCopy(k, seen)] = deepCopy(value, seen)
    end
    return setmetatable(out, getmetatable(v))
end

local function loadScully(path)
    local raw = LoadResourceFile(SCULLY, path)
    if not raw or raw == '' then
        loadErrors[#loadErrors + 1] = '파일 없음: ' .. path
        return nil
    end

    local chunk, err = load(raw, ('@@%s/%s'):format(SCULLY, path), 't', _ENV)
    if not chunk then
        loadErrors[#loadErrors + 1] = ('로드 실패 %s: %s'):format(path, tostring(err))
        return nil
    end

    local ok, data = pcall(chunk)
    if not ok then
        loadErrors[#loadErrors + 1] = ('실행 실패 %s: %s'):format(path, tostring(data))
        return nil
    end
    return data
end

local function rowsOf(data)
    if type(data) ~= 'table' then return {} end
    if type(data.options) == 'table' then return data.options end
    if type(data.Options) == 'table' then return data.Options end
    return data
end

local function labelOf(e)
    local s = tostring((e and (e.Label or e.label or e.Name or e.name or e.Command or e.command)) or '모션')
    return s:gsub('[\r\n\t]', ' '):gsub('%s+', ' ')
end

local function commandOf(e)
    return tostring((e and (e.Command or e.command)) or '')
end

local function visible(e)
    if type(e) ~= 'table' then return false end
    if e.Hide == true then return false end
    if Config.ExcludeNSFW and e.NSFW == true then return false end
    if Config.ExcludeAnimal and e.PedTypes ~= nil then return false end
    return true
end

local function hasProps(e)
    local opts = type(e) == 'table' and e.Options or nil
    local props = type(opts) == 'table' and opts.Props or nil
    return type(props) == 'table' and next(props) ~= nil
end

local function scenarioIsProp(e)
    local s = tostring((e and (e.Scenario or e.scenario or e.Command or '')) or ''):upper()
    local keys = {
        'PROP_', 'SMOK', 'MOBILE', 'CLIPBOARD', 'HAMMER', 'DRILL',
        'BBQ', 'BINOCULAR', 'JANITOR', 'MAID', 'PARKING_METER',
        'MUSICIAN', 'ATM', 'DRINK', 'FOOD'
    }
    for _, key in ipairs(keys) do
        if s:find(key, 1, true) then return true end
    end
    return false
end

local serial = 0
local function addItem(category, kind, data)
    if not visible(data) then return end
    serial = serial + 1
    local id = ('%s:%s:%d'):format(category, commandOf(data):gsub('[^%w_%-]', '_'), serial)

    itemsById[id] = {
        category = category,
        kind = kind,
        data = data,
    }

    catalog[category][#catalog[category] + 1] = {
        id = id,
        label = labelOf(data),
        command = commandOf(data),
        favoritable = true,
    }
end

local function addRows(category, kind, data, classify)
    for _, e in ipairs(rowsOf(data)) do
        if type(e) == 'table' then
            local target = category
            if classify then target = classify(e) or category end
            addItem(target, kind, e)
        end
    end
end

local function loadFavorites()
    favorites = {}
    local raw = GetResourceKvpString('cookie_social_favorites_v2')
    if not raw or raw == '' then return end

    local ok, data = pcall(json.decode, raw)
    if not ok or type(data) ~= 'table' then return end

    for _, id in ipairs(data) do
        if type(id) == 'string' then favorites[id] = true end
    end
end

local function saveFavorites()
    local data = {}
    for id, on in pairs(favorites) do
        if on == true and itemsById[id] then
            data[#data + 1] = id
        end
    end
    table.sort(data)
    SetResourceKvp('cookie_social_favorites_v2', json.encode(data))
end

local function sortAll()
    for _, key in ipairs({ 'dance', 'action', 'prop', 'sync', 'walk', 'face' }) do
        table.sort(catalog[key], function(a, b)
            return tostring(a.label):lower() < tostring(b.label):lower()
        end)
    end
end

local function favoriteRows()
    local out = {}
    for id, on in pairs(favorites) do
        local item = itemsById[id]
        if on and item then
            for _, row in ipairs(catalog[item.category] or {}) do
                if row.id == id then
                    out[#out + 1] = {
                        id = row.id,
                        label = row.label,
                        command = row.command,
                        favoritable = true,
                        sourceCategory = item.category,
                    }
                    break
                end
            end
        end
    end

    table.sort(out, function(a, b)
        return tostring(a.label):lower() < tostring(b.label):lower()
    end)
    return out
end

local function payload()
    return {
        favorite = favoriteRows(),
        dance = catalog.dance,
        action = catalog.action,
        prop = catalog.prop,
        sync = catalog.sync,
        walk = catalog.walk,
        face = catalog.face,
    }
end

local function buildCatalog()
    built = false
    serial = 0
    itemsById = {}
    loadErrors = {}
    catalog = { favorite={}, dance={}, action={}, prop={}, sync={}, walk={}, face={} }

    if GetResourceState(SCULLY) ~= 'started' then
        loadErrors[#loadErrors + 1] = 'scully_emotemenu 미실행'
        return false
    end

    local dance = loadScully('shared/data/emotes/dance_emotes.lua')
    local general = loadScully('shared/data/emotes/general_emotes.lua')
    local props = loadScully('shared/data/emotes/prop_emotes.lua')
    local consumable = loadScully('shared/data/emotes/consumable_emotes.lua')
    local sync = loadScully('shared/data/emotes/synchronized_emotes.lua')
    local syncDance = loadScully('shared/data/emotes/synchronized_dance_emotes.lua')
    local scenarios = loadScully('shared/data/scenarios.lua')
    local walks = loadScully('shared/data/walks.lua')
    local expressions = loadScully('shared/data/expressions.lua')

    addRows('dance', 'emote', dance)
    addRows('action', 'emote', general, function(e)
        return hasProps(e) and 'prop' or 'action'
    end)
    addRows('prop', 'emote', props)
    addRows('prop', 'emote', consumable)
    addRows('sync', 'sync', sync)
    addRows('sync', 'sync', syncDance)
    addRows('action', 'scenario', scenarios, function(e)
        return scenarioIsProp(e) and 'prop' or 'action'
    end)
    addRows('walk', 'walk', walks)
    addRows('face', 'face', expressions)

    local walkReset = 'walk:reset:0'
    itemsById[walkReset] = { category='walk', kind='walk_reset' }
    table.insert(catalog.walk, 1, {
        id=walkReset, label='기본 걸음걸이', command='', favoritable=false
    })

    local faceReset = 'face:reset:0'
    itemsById[faceReset] = { category='face', kind='face_reset' }
    table.insert(catalog.face, 1, {
        id=faceReset, label='기본 표정', command='', favoritable=false
    })

    sortAll()
    loadFavorites()

    local changed = false
    for id in pairs(favorites) do
        if not itemsById[id] then
            favorites[id] = nil
            changed = true
        end
    end
    if changed then saveFavorites() end

    built = true

    print(('[cookie_social] V2 catalog · 춤 %d / 행동 %d / 물건 %d / 같이 %d / 걸음 %d / 표정 %d')
        :format(#catalog.dance, #catalog.action, #catalog.prop, #catalog.sync, #catalog.walk, #catalog.face))

    if #loadErrors > 0 then
        for _, err in ipairs(loadErrors) do
            print(('^3[cookie_social]^7 %s'):format(err))
        end
    end

    return (#catalog.dance + #catalog.action + #catalog.prop + #catalog.sync + #catalog.walk + #catalog.face) > 2
end

local function openMenu()
    if menuOpen then
        closeMenu()
        return
    end
    if IsPauseMenuActive() or IsEntityDead(PlayerPedId()) then return end

    if not built and not buildCatalog() then
        return notify('Scully 모션 목록을 불러오지 못했습니다. F8 로그를 확인해주세요.', true)
    end

    pcall(function() exports.scully_emotemenu:closeMenu() end)
    TriggerEvent('scully_emotemenu:closeMenu')

    local ok, owner = setFocus(true)
    if ok == false then
        return notify(('다른 UI(%s)를 먼저 닫아주세요.'):format(tostring(owner or 'unknown')), true)
    end

    menuOpen = true
    SendNUIMessage({
        action = 'open',
        catalog = payload(),
        favorites = favorites,
    })
end

RegisterCommand('cookie_social_menu', openMenu, false)
RegisterKeyMapping('cookie_social_menu', 'COOKIE 모션 메뉴', 'keyboard', Config.MenuKey or 'F9')

RegisterCommand('em', openMenu, false)
RegisterCommand('emotemenu', openMenu, false)

RegisterNUICallback('close', function(_, cb)
    cb({ ok=true })
    closeMenu()
end)

RegisterNUICallback('favorite', function(data, cb)
    local id = tostring(data and data.id or '')
    if not itemsById[id] then
        cb({ ok=false })
        return
    end

    favorites[id] = not favorites[id]
    saveFavorites()
    cb({
        ok=true,
        on=favorites[id] == true,
        favorites=favoriteRows()
    })
end)

local function withConsent(data)
    local out = deepCopy(data)
    out.SkipRequest = false
    if type(out.Options) == 'table' and type(out.Options.Shared) == 'table' then
        out.Options.Shared.SkipRequest = false
    end
    return out
end

RegisterNUICallback('play', function(data, cb)
    local id = tostring(data and data.id or '')
    local item = itemsById[id]
    if not item then
        cb({ ok=false })
        return
    end

    cb({ ok=true })
    closeMenu()

    local ok, err = pcall(function()
        if item.kind == 'emote' or item.kind == 'scenario' then
            exports.scully_emotemenu:playEmote(deepCopy(item.data))
        elseif item.kind == 'sync' then
            -- COOKIE: 같이 행동은 SkipRequest 모션도 무조건 상대 동의를 받게 함.
            exports.scully_emotemenu:playEmote(withConsent(item.data))
        elseif item.kind == 'walk' then
            local walk = item.data.Walk or item.data.walk or item.data.Clipset or item.data.clipset
            if walk then exports.scully_emotemenu:setWalk(walk) end
        elseif item.kind == 'face' then
            local expression = item.data.Expression or item.data.expression
            if expression then exports.scully_emotemenu:setExpression(expression) end
        elseif item.kind == 'walk_reset' then
            exports.scully_emotemenu:resetWalk()
        elseif item.kind == 'face_reset' then
            exports.scully_emotemenu:resetExpression()
        end
    end)

    if not ok then
        print(('^1[cookie_social]^7 play error %s: %s'):format(id, tostring(err)))
        notify('모션 실행 중 오류가 발생했습니다.', true)
    end
end)

RegisterNUICallback('rebuild', function(_, cb)
    local ok = buildCatalog()
    cb({ ok=ok, catalog=ok and payload() or {}, favorites=favorites, errors=loadErrors })
end)

-- U 업기
local function loadAnim(dict)
    RequestAnimDict(dict)
    local untilAt = GetGameTimer() + 2500
    while not HasAnimDictLoaded(dict) and GetGameTimer() < untilAt do Wait(0) end
    return HasAnimDictLoaded(dict)
end

local function clearCarryLocal()
    if not carry.active then return end
    local ped = PlayerPedId()
    DetachEntity(ped, true, false)
    ClearPedTasks(ped)
    carry.active = false
    carry.role = nil
    carry.partner = nil
end

RegisterNetEvent('cookie_social:client:carryRequest', function(requestId, fromServerId, fromName)
    if carry.active or IsEntityDead(PlayerPedId()) or IsPedInAnyVehicle(PlayerPedId(), false) then
        TriggerServerEvent('cookie_social:server:carryResponse', requestId, false)
        return
    end

    CreateThread(function()
        local answer = lib.alertDialog({
            header = '업기 요청',
            content = ('**%s**님이 같이 업기를 하시겠습니까?'):format(tostring(fromName or ('ID '..tostring(fromServerId)))),
            centered = true,
            cancel = true,
            labels = { confirm='수락', cancel='거절' }
        })
        TriggerServerEvent('cookie_social:server:carryResponse', requestId, answer == 'confirm')
    end)
end)

RegisterNetEvent('cookie_social:client:carryStart', function(role, partnerId)
    clearCarryLocal()

    local player = GetPlayerFromServerId(tonumber(partnerId) or -1)
    if player == -1 then
        TriggerServerEvent('cookie_social:server:carryStop')
        return
    end

    local partnerPed = GetPlayerPed(player)
    if partnerPed == 0 or not DoesEntityExist(partnerPed) then
        TriggerServerEvent('cookie_social:server:carryStop')
        return
    end

    carry.active = true
    carry.role = role
    carry.partner = tonumber(partnerId)

    local ped = PlayerPedId()
    if role == 'carrier' then
        if loadAnim('missfinale_c2mcs_1') then
            TaskPlayAnim(ped, 'missfinale_c2mcs_1', 'fin_c2_mcs_1_camman', 8.0, -8.0, -1, 49, 0.0, false, false, false)
        end
        notify('업기를 시작했습니다. U를 다시 누르면 내려놓습니다.', false)
    else
        if loadAnim('nm') then
            AttachEntityToEntity(ped, partnerPed, 0, 0.27, 0.15, 0.63, 0.5, 0.5, 180.0, false, false, false, false, 2, false)
            TaskPlayAnim(ped, 'nm', 'firemans_carry', 8.0, -8.0, -1, 33, 0.0, false, false, false)
        end
        notify('업기에 수락했습니다. U를 누르면 내려달라고 할 수 있습니다.', false)
    end
end)

RegisterNetEvent('cookie_social:client:carryStop', function(message)
    clearCarryLocal()
    if message and message ~= '' then notify(message, false) end
end)

RegisterNetEvent('cookie_social:client:notify', function(message, isError)
    notify(message, isError == true)
end)

RegisterCommand('cookie_social_carry', function()
    if carry.active then
        TriggerServerEvent('cookie_social:server:carryStop')
        return
    end

    local ped = PlayerPedId()
    if IsEntityDead(ped) then return end
    if IsPedInAnyVehicle(ped, false) then
        notify('차량 안에서는 업기를 사용할 수 없습니다.', true)
        return
    end

    local playerId = lib.getClosestPlayer(GetEntityCoords(ped), Config.CarryDistance or 2.5, false)
    if not playerId then
        notify('가까운 사람이 없습니다.', true)
        return
    end

    local target = GetPlayerServerId(playerId)
    if not target or target <= 0 then
        notify('대상을 찾지 못했습니다.', true)
        return
    end

    TriggerServerEvent('cookie_social:server:carryRequest', target)
end, false)

RegisterKeyMapping('cookie_social_carry', 'COOKIE 업기 / 내려놓기', 'keyboard', Config.CarryKey or 'U')

CreateThread(function()
    while true do
        if carry.active then
            local ped = PlayerPedId()
            local p = GetPlayerFromServerId(carry.partner or -1)
            local invalid = IsEntityDead(ped)
                or IsPedInAnyVehicle(ped, false)
                or p == -1
                or not DoesEntityExist(GetPlayerPed(p))

            if invalid then
                TriggerServerEvent('cookie_social:server:carryStop')
                Wait(800)
            elseif carry.role == 'carried' then
                DisableControlAction(0, 21, true)
                DisableControlAction(0, 22, true)
                DisableControlAction(0, 24, true)
                DisableControlAction(0, 25, true)
                DisableControlAction(0, 37, true)
                DisableControlAction(0, 75, true)
                Wait(0)
            else
                Wait(250)
            end
        else
            Wait(400)
        end
    end
end)

CreateThread(function()
    Wait(1500)
    buildCatalog()
end)

AddEventHandler('onClientResourceStart', function(res)
    if res == SCULLY then
        Wait(1000)
        buildCatalog()
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RESOURCE then return end
    if menuOpen then setFocus(false) end
    clearCarryLocal()
end)
