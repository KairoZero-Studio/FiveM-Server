
RegisterNetEvent('cookie_taxi:client:adminPay',function(d) SendNUIMessage({action='npcTaxiPay',data=d or {}}) end)
RegisterNUICallback('taxiPayGet',function(_,cb)cb({ok=true});TriggerServerEvent('cookie_taxi:server:adminPayGet')end)
RegisterNUICallback('taxiPaySave',function(d,cb)cb({ok=true});TriggerServerEvent('cookie_taxi:server:adminPaySave',d)end)

RegisterNetEvent('cookie_trucker:client:adminPay',function(d) SendNUIMessage({action='npcTruckPay',data=d or {}}) end)
RegisterNUICallback('truckPayGet',function(_,cb)cb({ok=true});TriggerServerEvent('cookie_trucker:server:adminPayGet')end)
RegisterNUICallback('truckPaySave',function(d,cb)cb({ok=true});TriggerServerEvent('cookie_trucker:server:adminPaySave',d)end)


local npcs = {}
local npcMeta = {}
local editing = false
local editPed = 0

local eId, eLabel = 0, ''
local eModel = 'a_m_y_business_01'
local eScenario = ''
local eComps = {}
local eX, eY, eZ, eHeading = 0.0, 0.0, 0.0, 0.0

local flatPeds = {}

local STEP = 0.05
local STEP_Z = 0.05
local STEP_R = 5.0

local function loadModel(model)
    local hash = (type(model) == 'string') and joaat(model) or model
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then return nil end
    RequestModel(hash)
    local t = GetGameTimer()
    while not HasModelLoaded(hash) do
        if GetGameTimer() - t > 5000 then return nil end
        Wait(0)
    end
    return hash
end

local function compKey(id, prop) return (prop and 'p' or 'c') .. id end

local function placePed(ped, x, y, z, heading)
    if not DoesEntityExist(ped) then return end

    FreezeEntityPosition(ped, false)
    SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
    SetEntityHeading(ped, heading)
    FreezeEntityPosition(ped, true)
end

local function applyComponents(ped, comps)
    for _, c in pairs(comps or {}) do
        local d = math.floor(tonumber(c.drawable) or 0)
        local t = math.floor(tonumber(c.texture) or 0)
        if c.prop then
            if d < 0 then ClearPedProp(ped, c.id) else SetPedPropIndex(ped, c.id, d, t, true) end
        else
            SetPedComponentVariation(ped, c.id, d, t, 0)
        end
    end
end

local function spawnNpc(row)
    local hash = loadModel(row.model)
    if not hash then

        return
    end

    local ped = CreatePed(4, hash, row.x + 0.0, row.y + 0.0, row.z + 0.0, row.heading + 0.0, false, true)
    SetModelAsNoLongerNeeded(hash)
    if not DoesEntityExist(ped) then return end

    placePed(ped, row.x + 0.0, row.y + 0.0, row.z + 0.0, row.heading + 0.0)

    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    SetPedDiesWhenInjured(ped, false)
    SetPedFleeAttributes(ped, 0, false)
    SetEntityAsMissionEntity(ped, true, true)

    if row.components and row.components ~= '' then
        local ok, comps = pcall(json.decode, row.components)
        if ok and comps then applyComponents(ped, comps) end
    end
    if row.scenario and row.scenario ~= '' then
        TaskStartScenarioInPlace(ped, row.scenario, 0, true)

        placePed(ped, row.x + 0.0, row.y + 0.0, row.z + 0.0, row.heading + 0.0)
    end

    npcs[row.id] = ped
    npcMeta[row.id] = {
        label = row.label,
        job_key = (type(row.job_key) == 'string' and row.job_key ~= '') and row.job_key or nil,
        x = row.x + 0.0, y = row.y + 0.0, z = row.z + 0.0,
    }
end

local function clearNpcs()
    for id, ped in pairs(npcs) do
        if DoesEntityExist(ped) then DeletePed(ped) end
        npcs[id] = nil
    end
    npcMeta = {}
end

exports('getNpcPed', function(id)
    local ped = npcs[tonumber(id) or 0]
    if ped and DoesEntityExist(ped) then return ped end
    return nil
end)

RegisterNetEvent('cookie_admin:client:npcList', function(list)
    clearNpcs()
    local count=0
    for _, row in ipairs(list or {}) do spawnNpc(row); count=count+1 end
    print(('[cookie_admin] NPC sync received: %d'):format(count))
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        clearNpcs()
        if DoesEntityExist(editPed) then DeletePed(editPed) end
    end
end)

local function requestNpcSyncV166(reason)
    TriggerServerEvent('cookie_admin:server:requestNpcs', reason or 'client')
end

CreateThread(function()
    Wait(2000)
    requestNpcSyncV166('startup')
    -- 접속 직후 DB/플레이어 로딩 타이밍 때문에 최초 요청이 유실되어도 자동 복구한다.
    while true do
        Wait(30000)
        requestNpcSyncV166('periodic')
    end
end)

AddEventHandler('playerSpawned', function()
    CreateThread(function()
        Wait(1500)
        requestNpcSyncV166('spawn')
    end)
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    CreateThread(function()
        Wait(1000)
        requestNpcSyncV166('playerLoaded')
    end)
end)

local function buildFlatPeds()
    flatPeds = {}
    for _, cat in ipairs(Config.NpcPeds or {}) do
        for _, p in ipairs(cat.items or {}) do
            flatPeds[#flatPeds + 1] = { model = p.model, label = p.label, group = cat.label }
        end
    end
end

local function pedIndexOf(model)
    for i, p in ipairs(flatPeds) do
        if p.model == model then return i end
    end
    return 1
end

local function scenarioIndexOf(key)
    for i, s in ipairs(Config.NpcScenarios or {}) do
        if s.key == key then return i end
    end
    return 1
end

local function destroyEditPed()
    if DoesEntityExist(editPed) then DeletePed(editPed) end
    editPed = 0
end

local function respawnEditPed()
    destroyEditPed()

    local hash = loadModel(eModel)
    if not hash then
        TriggerEvent('cookie_admin:client:notify', ('없는 ped 모델입니다: %s'):format(eModel), true)
        return
    end

    editPed = CreatePed(4, hash, eX, eY, eZ, eHeading, false, false)
    SetModelAsNoLongerNeeded(hash)
    if not DoesEntityExist(editPed) then return end

    SetEntityInvincible(editPed, true)
    SetBlockingOfNonTemporaryEvents(editPed, true)
    SetEntityCollision(editPed, false, false)

    applyComponents(editPed, eComps)
    if eScenario ~= '' then TaskStartScenarioInPlace(editPed, eScenario, 0, true) end

    placePed(editPed, eX, eY, eZ, eHeading)
end

local function moveEditPed()
    placePed(editPed, eX, eY, eZ, eHeading)
end

local function pushEditUi()
    local p = flatPeds[pedIndexOf(eModel)]
    local s = (Config.NpcScenarios or {})[scenarioIndexOf(eScenario)]

    local comps = {}
    for _, c in ipairs(Config.NpcComponents or {}) do
        local key = compKey(c.id, c.prop and true or false)
        local cur = eComps[key]
        comps[#comps + 1] = {
            key = key,
            label = c.label,
            value = cur and (tostring(cur.drawable) .. ' / ' .. tostring(cur.texture)) or '기본',
            changed = cur and true or false,
        }
    end

    SendNUIMessage({
        action = 'npcEditUi',
        modelLabel = (p and p.label) or eModel,
        modelGroup = (p and p.group) or '',
        model = eModel,
        scenarioLabel = (s and s.label) or '없음',
        comps = comps,
        heading = math.floor(eHeading),
        z = string.format('%.2f', eZ),
    })
end

RegisterNUICallback('npcEditStart', function(data, cb)
    cb({ ok = true })

    buildFlatPeds()

    eId = math.floor(tonumber(data and data.id) or 0)
    eLabel = (data and data.label) or ''
    eModel = (data and data.model) or (flatPeds[1] and flatPeds[1].model) or 'a_m_y_business_01'
    eScenario = (data and data.scenario) or ''

    eComps = {}
    if data and type(data.components) == 'table' then
        for _, c in ipairs(data.components) do
            eComps[compKey(c.id, c.prop)] = {
                id = c.id, prop = c.prop and true or false,
                drawable = c.drawable, texture = c.texture or 0,
            }
        end
    end

    local me = PlayerPedId()
    local pos = (data and data.x)
        and vec3(data.x + 0.0, data.y + 0.0, data.z + 0.0)
        or GetOffsetFromEntityInWorldCoords(me, 0.0, 1.5, 0.0)

    eX, eY, eZ = pos.x, pos.y, pos.z
    eHeading = tonumber(data and data.heading) or ((GetEntityHeading(me) + 180.0) % 360.0)

    if eId > 0 and npcs[eId] and DoesEntityExist(npcs[eId]) then
        DeletePed(npcs[eId])
        npcs[eId] = nil
        npcMeta[eId] = nil
    end

    editing = true
    respawnEditPed()
    pushEditUi()
end)

RegisterNUICallback('npcMove', function(data, cb)
    cb({ ok = true })
    if not editing then return end

    local dx = tonumber(data and data.dx) or 0
    local dy = tonumber(data and data.dy) or 0
    local dz = tonumber(data and data.dz) or 0

    if dz ~= 0 then
        eZ = eZ + (dz * STEP_Z)
    end

    if dx ~= 0 or dy ~= 0 then

        local rot = GetGameplayCamRot(2)
        local rad = math.rad(rot.z)
        local fx, fy = -math.sin(rad), math.cos(rad)
        local rx, ry = math.cos(rad), math.sin(rad)

        eX = eX + (fx * dy * STEP) + (rx * dx * STEP)
        eY = eY + (fy * dy * STEP) + (ry * dx * STEP)
    end

    moveEditPed()
    pushEditUi()
end)

RegisterNUICallback('npcRotate', function(data, cb)
    cb({ ok = true })
    if not editing then return end
    local d = tonumber(data and data.d) or 0
    eHeading = (eHeading + (d * STEP_R)) % 360.0
    moveEditPed()
    pushEditUi()
end)

RegisterNUICallback('npcToMe', function(_, cb)
    cb({ ok = true })
    if not editing then return end
    local me = PlayerPedId()
    local pos = GetOffsetFromEntityInWorldCoords(me, 0.0, 1.5, 0.0)
    eX, eY, eZ = pos.x, pos.y, pos.z
    eHeading = (GetEntityHeading(me) + 180.0) % 360.0
    moveEditPed()
    pushEditUi()
end)

RegisterNUICallback('npcGround', function(_, cb)
    cb({ ok = true })
    if not editing then return end
    local me = GetEntityCoords(PlayerPedId())
    eZ = me.z
    moveEditPed()
    pushEditUi()
end)

RegisterNUICallback('npcModel', function(data, cb)
    cb({ ok = true })
    if not editing then return end

    local dir = tonumber(data and data.d) or 1
    local i = pedIndexOf(eModel) + dir
    if i < 1 then i = #flatPeds elseif i > #flatPeds then i = 1 end

    eModel = flatPeds[i].model
    eComps = {}
    respawnEditPed()
    pushEditUi()
end)

RegisterNUICallback('npcScenario', function(data, cb)
    cb({ ok = true })
    if not editing then return end

    local list = Config.NpcScenarios or {}
    local dir = tonumber(data and data.d) or 1
    local i = scenarioIndexOf(eScenario) + dir
    if i < 1 then i = #list elseif i > #list then i = 1 end

    eScenario = list[i].key
    respawnEditPed()
    pushEditUi()
end)

RegisterNUICallback('npcComp', function(data, cb)
    cb({ ok = true })
    if not editing or not DoesEntityExist(editPed) then return end

    local id = math.floor(tonumber(data and data.id) or 0)
    local prop = (data and data.prop) and true or false
    local dir = tonumber(data and data.d) or 1
    local tex = (data and data.tex) and true or false

    local key = compKey(id, prop)
    local cur = eComps[key]

    if tex then
        if not cur then return end
        local maxT = prop
            and GetNumberOfPedPropTextureVariations(editPed, id, cur.drawable)
            or GetNumberOfPedTextureVariations(editPed, id, cur.drawable)
        if maxT <= 0 then return end

        cur.texture = (cur.texture + dir) % maxT
        if prop then
            SetPedPropIndex(editPed, id, cur.drawable, cur.texture, true)
        else
            SetPedComponentVariation(editPed, id, cur.drawable, cur.texture, 0)
        end
        pushEditUi()
        return
    end

    local now = cur and cur.drawable or -1
    local maxN = prop
        and GetNumberOfPedPropDrawableVariations(editPed, id)
        or GetNumberOfPedDrawableVariations(editPed, id)

    local nxt = now + dir
    if nxt < -1 then nxt = maxN - 1 end
    if nxt > maxN - 1 then nxt = -1 end

    if nxt < 0 then
        eComps[key] = nil
        if prop then ClearPedProp(editPed, id) else SetPedComponentVariation(editPed, id, 0, 0, 0) end
    else
        eComps[key] = { id = id, prop = prop, drawable = nxt, texture = 0 }
        if prop then
            SetPedPropIndex(editPed, id, nxt, 0, true)
        else
            SetPedComponentVariation(editPed, id, nxt, 0, 0)
        end
    end

    pushEditUi()
end)

RegisterNUICallback('npcConfirm', function(_, cb)
    cb({ ok = true })
    if not editing then return end

    local comps = {}
    for _, c in pairs(eComps) do comps[#comps + 1] = c end

    editing = false
    destroyEditPed()

    SendNUIMessage({
        action = 'npcPlaced',
        id = eId, label = eLabel, model = eModel, scenario = eScenario,
        components = comps,
        x = eX, y = eY, z = eZ, heading = eHeading,
    })
end)

RegisterNUICallback('npcCancel', function(_, cb)
    cb({ ok = true })
    editing = false
    destroyEditPed()

    if eId > 0 then TriggerServerEvent('cookie_admin:server:requestNpcs') end
    SendNUIMessage({ action = 'npcEditCancel' })
end)

RegisterNUICallback('npcEditStop', function(_, cb)
    cb({ ok = true })
    editing = false
    destroyEditPed()
    TriggerServerEvent('cookie_admin:server:requestNpcs')
end)

RegisterNUICallback('npcSave', function(data, cb)
    cb({ ok = true })
    editing = false
    destroyEditPed()
    TriggerServerEvent('cookie_admin:server:npcSave', data)
end)

RegisterNUICallback('npcDelete', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:npcDelete', data and data.id)
end)

RegisterNUICallback('requestNpcAdmin', function(_, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:requestNpcAdmin')
end)

RegisterNUICallback('npcGoto', function(data, cb)
    cb({ ok = true })
    local x, y, z = tonumber(data and data.x), tonumber(data and data.y), tonumber(data and data.z)
    if not (x and y and z) then return end
    SetEntityCoords(PlayerPedId(), x + 1.0, y + 1.0, z, false, false, false, false)
end)

RegisterNetEvent('cookie_admin:client:npcAdmin', function(payload)
    if not payload then return end
    payload.action = 'npcAdmin'
    SendNUIMessage(payload)
end)

RegisterNetEvent('cookie_taxi:client:hailList', function(p)
    if not p then return end
    p.action = 'npcHails'
    SendNUIMessage(p)
end)

RegisterNUICallback('hailList', function(_, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_taxi:server:hailList')
end)

RegisterNUICallback('callAdd', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_taxi:server:callAdd', { name = data and data.name })
end)

RegisterNUICallback('callRename', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_taxi:server:callRename', {
        id = data and data.id, name = data and data.name,
    })
end)

RegisterNUICallback('callSetCoord', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_taxi:server:callSetCoord', {
        id = data and data.id, kind = data and data.kind,
    })
end)

RegisterNUICallback('callDelete', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_taxi:server:callDelete', data and data.id)
end)

RegisterNUICallback('hailGoto', function(data, cb)
    cb({ ok = true })
    local x, y, z = tonumber(data and data.x), tonumber(data and data.y), tonumber(data and data.z)
    if not (x and y and z) then return end
    SetEntityCoords(PlayerPedId(), x, y, z, false, false, false, false)
end)


RegisterNetEvent('cookie_mechanic:client:adminData', function(p)
    SendNUIMessage({ action='npcMechanic', data=p or {} })
end)

RegisterNUICallback('mechanicList', function(d,cb) cb({ok=true});TriggerServerEvent('cookie_mechanic:server:adminList',d and d.npcId) end)
RegisterNUICallback('mechanicAdd', function(d,cb) cb({ok=true});TriggerServerEvent('cookie_mechanic:server:adminAdd',d) end)
RegisterNUICallback('mechanicUpdate', function(d,cb) cb({ok=true});TriggerServerEvent('cookie_mechanic:server:adminUpdate',d) end)
RegisterNUICallback('mechanicSetCoord', function(d,cb) cb({ok=true});TriggerServerEvent('cookie_mechanic:server:adminSetCoord',d) end)
RegisterNUICallback('mechanicDelete', function(d,cb) cb({ok=true});TriggerServerEvent('cookie_mechanic:server:adminDelete',d) end)

RegisterNetEvent('cookie_delivery:client:adminData', function(p)
    SendNUIMessage({ action='npcDelivery', data=p or {} })
end)
RegisterNUICallback('deliveryList', function(d,cb) cb({ok=true}); TriggerServerEvent('cookie_delivery:server:adminList',d and d.npcId) end)
RegisterNUICallback('deliveryAddRestaurant', function(d,cb) cb({ok=true}); TriggerServerEvent('cookie_delivery:server:addRestaurant',d) end)
RegisterNUICallback('deliveryAddDropoff', function(d,cb) cb({ok=true}); TriggerServerEvent('cookie_delivery:server:addDropoff',d) end)
RegisterNUICallback('deliveryDeleteRestaurant', function(d,cb) cb({ok=true}); TriggerServerEvent('cookie_delivery:server:deleteRestaurant',d) end)
RegisterNUICallback('deliveryDeleteDropoff', function(d,cb) cb({ok=true}); TriggerServerEvent('cookie_delivery:server:deleteDropoff',d) end)
RegisterNUICallback('deliveryUpdateRestaurant', function(d,cb) cb({ok=true}); TriggerServerEvent('cookie_delivery:server:updateRestaurant',d) end)
RegisterNUICallback('deliverySetRestaurantCoord', function(d,cb) cb({ok=true}); TriggerServerEvent('cookie_delivery:server:setRestaurantCoord',d) end)
RegisterNUICallback('deliveryUpdateDropoff', function(d,cb) cb({ok=true}); TriggerServerEvent('cookie_delivery:server:updateDropoff',d) end)
RegisterNUICallback('deliverySetDropoffCoord', function(d,cb) cb({ok=true}); TriggerServerEvent('cookie_delivery:server:setDropoffCoord',d) end)

RegisterNetEvent('cookie_labor:client:adminData', function(p)
    if not p then return end
    SendNUIMessage({ action = 'npcLabor', data = p })
end)

RegisterNUICallback('laborList', function(d, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_labor:server:adminList', d and d.npcId)
end)

RegisterNUICallback('laborAdd', function(d, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_labor:server:adminAdd', d)
end)

RegisterNUICallback('laborUpdate', function(d, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_labor:server:adminUpdate', d)
end)

RegisterNUICallback('laborSetCoord', function(d, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_labor:server:adminSetCoord', d)
end)

RegisterNUICallback('laborDelete', function(d, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_labor:server:adminDelete', d)
end)

RegisterNetEvent('cookie_trucker:client:coordList', function(p)
    if not p then return end
    p.action = 'npcTruck'
    SendNUIMessage(p)
end)
RegisterNUICallback('truckList', function(d, cb)
    cb({ ok = true }); TriggerServerEvent('cookie_trucker:server:coordList', d and d.npcId)
end)
RegisterNUICallback('truckAdd', function(d, cb)
    cb({ ok = true }); TriggerServerEvent('cookie_trucker:server:coordAdd', d and d.kind, d and d.label, d and d.limit, d and d.npcId)
end)
RegisterNUICallback('truckRename', function(d, cb)
    cb({ ok = true }); TriggerServerEvent('cookie_trucker:server:coordRename', d and d.kind, d and d.id, d and d.name, d and d.npcId)
end)

RegisterNUICallback('truckSetCoord', function(d, cb)
    cb({ ok = true }); TriggerServerEvent('cookie_trucker:server:coordSetCoord', d and d.kind, d and d.id, d and d.npcId)
end)
RegisterNUICallback('truckSetLimit', function(d, cb)
    cb({ ok = true }); TriggerServerEvent('cookie_trucker:server:coordSetLimit', d and d.id, d and d.limit, d and d.npcId)
end)
RegisterNUICallback('truckDelete', function(d, cb)
    cb({ ok = true }); TriggerServerEvent('cookie_trucker:server:coordDelete', d and d.kind, d and d.id, d and d.npcId)
end)

RegisterNUICallback('truckDestPay', function(d, cb)
    cb({ ok = true }); TriggerServerEvent('cookie_trucker:server:destPay', d and d.id, d and d.pay, d and d.npcId)
end)

local function ckRotToDir(pitch, heading)
    local p, h = math.rad(pitch), math.rad(heading)
    local cp = math.cos(p)
    return vec3(-math.sin(h) * cp, math.cos(h) * cp, math.sin(p))
end
local ckCapActive = false
local function ckStartCapture(id, npcId)
    if ckCapActive then return end
    ckCapActive = true
    TriggerEvent('cookie_admin:client:forceClosePanel')
    CreateThread(function()
        Wait(80)
        local ped = PlayerPedId()
        FreezeEntityPosition(ped, true)
        SetEntityVisible(ped, false, false)
        local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
        local co = GetGameplayCamCoord()
        local rot = GetGameplayCamRot(2)
        SetCamCoord(cam, co.x, co.y, co.z)
        SetCamRot(cam, rot.x, rot.y, rot.z, 2)
        SetCamActive(cam, true)
        RenderScriptCams(true, false, 0, true, true)
        pcall(function() exports.ox_lib:showTextUI('마우스: 시야 · WASD/Shift: 이동 · Space/Ctrl: 상하 · 좌클릭: 촬영 · ESC: 취소', { position = 'top-center' }) end)

        local px, py, pz = co.x, co.y, co.z
        local pitch, heading = rot.x, rot.z
        local shoot, cancel = false, false
        while ckCapActive and not shoot and not cancel do
            HideHudAndRadarThisFrame()
            DisableAllControlActions(0)
            heading = heading - GetDisabledControlNormal(0, 1) * 8.0
            pitch = math.max(-89.0, math.min(89.0, pitch - GetDisabledControlNormal(0, 2) * 8.0))
            local fwd = ckRotToDir(pitch, heading)
            local right = ckRotToDir(0.0, heading - 90.0)
            local spd = IsDisabledControlPressed(0, 21) and 1.4 or 0.55
            if IsDisabledControlPressed(0, 32) then px, py, pz = px + fwd.x*spd, py + fwd.y*spd, pz + fwd.z*spd end
            if IsDisabledControlPressed(0, 33) then px, py, pz = px - fwd.x*spd, py - fwd.y*spd, pz - fwd.z*spd end
            if IsDisabledControlPressed(0, 34) then px, py, pz = px - right.x*spd, py - right.y*spd, pz - right.z*spd end
            if IsDisabledControlPressed(0, 35) then px, py, pz = px + right.x*spd, py + right.y*spd, pz + right.z*spd end
            if IsDisabledControlPressed(0, 22) then pz = pz + spd end
            if IsDisabledControlPressed(0, 36) then pz = pz - spd end
            SetCamCoord(cam, px, py, pz)
            SetCamRot(cam, pitch, 0.0, heading, 2)
            if IsDisabledControlJustPressed(0, 24) then shoot = true end
            if IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 177) then cancel = true end
            Wait(0)
        end
        pcall(function() exports.ox_lib:hideTextUI() end)

        if shoot then
            local done = false
            pcall(function()
                exports['screenshot-basic']:requestScreenshot({ encoding = 'webp' }, function(data)
                    if type(data) == 'string' and #data > 32 then
                        TriggerLatentServerEvent('cookie_trucker:server:destImage', 500000, id, data, npcId)
                    else
                        TriggerEvent('cookie_admin:client:notify', '촬영 실패(빈 이미지)', true)
                    end
                    done = true
                end)
            end)
            local t = GetGameTimer() + 4000
            while not done and GetGameTimer() < t do HideHudAndRadarThisFrame(); Wait(0) end
        elseif cancel then
            TriggerEvent('cookie_admin:client:notify', '촬영 취소', false)
        end

        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(cam, true)
        SetEntityVisible(PlayerPedId(), true, false)
        FreezeEntityPosition(PlayerPedId(), false)
        ckCapActive = false
    end)
end
RegisterNUICallback('truckDestShot', function(d, cb)
    cb({ ok = true })
    ckStartCapture(d and d.id, d and d.npcId)
end)



-- ─────────────────────────────────────────────────────────────
-- 광물 관리인 F3 설정 브리지
-- ─────────────────────────────────────────────────────────────
RegisterNUICallback('miningAdminList', function(d, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_mining:server:managerAdminRequest', d and d.npcId)
end)
RegisterNUICallback('miningShopSave', function(d, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_mining:server:managerShopSave', d)
end)
RegisterNUICallback('miningMineralSave', function(d, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_mining:server:managerMineralSave', d)
end)
RegisterNetEvent('cookie_admin:client:miningAdminData', function(d)
    SendNUIMessage({ action = 'npcMiningAdmin', data = d })
end)

-- ─────────────────────────────────────────────────────────────
-- 낚시 관리인 F3 설정 브리지
-- ─────────────────────────────────────────────────────────────
RegisterNUICallback('fishAdminList', function(d, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_fishing:server:managerAdminRequest', d and d.npcId)
end)

RegisterNUICallback('fishShopSave', function(d, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_fishing:server:managerShopSave', d)
end)

RegisterNUICallback('fishBuySave', function(d, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_fishing:server:managerFishSave', d)
end)

RegisterNetEvent('cookie_admin:client:fishingAdminData', function(d)
    SendNUIMessage({ action = 'npcFishingAdmin', data = d })
end)

local jobRoute = nil

local function buildJobRoute()
    jobRoute = {}
    for _, j in ipairs(Config.NpcJobKeys or {}) do
        if j.key and j.key ~= '' and j.event then
            jobRoute[j.key] = j
        end
    end

    -- 낚시 관리인은 cookie_fishing이 실제 상호작용을 담당한다.
    jobRoute.fishing = jobRoute.fishing or {
        event = 'cookie_fishing:client:openManager',
        badge = '낚시 관리인과 대화'
    }

    -- V1.6.6: 낚시/광물 관리인 모두 cookie_admin의 공용 NPC 상호작용으로 통일한다.
    -- 별도 거리 루프가 E키를 동시에 먹는 문제를 막고, 동일한 NPC 배지/상호작용 UX를 사용한다.
    jobRoute.mining = jobRoute.mining or {
        event = 'cookie_mining:client:openManager',
        badge = '광물 관리인과 대화'
    }
end

local function nearestJobNpc(pos, maxDist)
    local bestId, bestD = nil, maxDist
    for id, m in pairs(npcMeta) do
        if m.job_key and jobRoute[m.job_key] then
            local d = #(pos - vec3(m.x, m.y, m.z))
            if d < bestD then bestId, bestD = id, d end
        end
    end
    return bestId
end

local TAG_DIST = 18.0

CreateThread(function()
    local lastCount = 0

    while true do
        local wait = 500
        local me = GetEntityCoords(PlayerPedId())
        local tags = {}

        if not editing and not IsPauseMenuActive() then
            for id, m in pairs(npcMeta) do
                local d = #(me - vec3(m.x, m.y, m.z))
                if d <= TAG_DIST and m.label and m.label ~= '' then
                    local onScreen, sx, sy = World3dToScreen2d(m.x, m.y, m.z + 1.12)
                    if onScreen then
                        wait = 0
                        tags[#tags + 1] = {
                            label = m.label,
                            x = sx, y = sy,

                            a = string.format('%.2f', 1.0 - (d / TAG_DIST) * 0.65),
                        }
                    end
                end
            end
        end

        if #tags > 0 or lastCount > 0 then
            SendNUIMessage({ action = 'npcTags', tags = tags })
            lastCount = #tags
        end

        Wait(wait)
    end
end)

CreateThread(function()
    buildJobRoute()

    local shown = false
    local COOLDOWN = 400
    local lastPress = 0

    while true do
        local wait = 500
        local ped = PlayerPedId()

        if not editing and not IsPedInAnyVehicle(ped, false) and not IsPauseMenuActive() then
            local pos = GetEntityCoords(ped)
            local id = nearestJobNpc(pos, Config.NpcInteractDistance or 2.2)

            if id then
                wait = 0
                local m = npcMeta[id]
                local route = jobRoute[m.job_key]

                local onScreen, sx, sy = World3dToScreen2d(m.x, m.y, m.z + 0.95)
                if onScreen then
                    SendNUIMessage({ action = 'npcBadge', show = true, x = sx, y = sy,
                                     text = route.badge or '대화하기' })
                    shown = true
                elseif shown then
                    SendNUIMessage({ action = 'npcBadge', show = false })
                    shown = false
                end

                if IsControlJustReleased(0, 38) or IsDisabledControlJustReleased(0, 38) then
                    local now = GetGameTimer()
                    if now - lastPress > COOLDOWN then
                        lastPress = now
                        SendNUIMessage({ action = 'npcBadge', show = false })
                        shown = false

                        local payload = { npcId = id, label = m.label }

                        -- 택시는 과거 client event가 간헐적으로 열리지 않던 문제가 있어
                        -- client export를 우선 사용하고 실패 시 기존 event로 폴백한다.
                        print(('[cookie_admin][npc] interact id=%s job=%s'):format(tostring(id),tostring(m.job_key)))

                        if m.job_key == 'taxi' and GetResourceState('cookie_taxi') == 'started' then
                            local ok = pcall(function()
                                exports.cookie_taxi:OpenNpcDialog(payload)
                            end)
                            if not ok then TriggerEvent(route.event, payload) end
                        elseif m.job_key == 'fishing' and GetResourceState('cookie_fishing') == 'started' then
                            local ok, opened = pcall(function()
                                return exports.cookie_fishing:OpenManager(payload)
                            end)
                            if not ok or opened == false then TriggerEvent(route.event, payload) end
                        elseif m.job_key == 'mining' and GetResourceState('cookie_mining') == 'started' then
                            -- 광물 관리인은 export를 우선 사용해서 client event 라우팅 누락을 피한다.
                            local ok, opened = pcall(function()
                                return exports.cookie_mining:OpenManager(payload)
                            end)
                            if not ok or opened == false then
                                TriggerEvent(route.event, payload)
                            end
                        else
                            TriggerEvent(route.event, payload)
                        end
                    end
                end
            elseif shown then
                SendNUIMessage({ action = 'npcBadge', show = false })
                shown = false
            end
        elseif shown then
            SendNUIMessage({ action = 'npcBadge', show = false })
            shown = false
        end

        Wait(wait)
    end
end)
RegisterNUICallback('mechanicSetPoint',function(d,cb)cb({ok=true});TriggerServerEvent('cookie_mechanic:server:adminSetPoint',d)end)
RegisterNUICallback('mechanicPricingSave',function(d,cb)cb({ok=true});TriggerServerEvent('cookie_mechanic:server:adminPricingSave',d)end)


-- COOKIE CAPSLOCK interaction test NPC
RegisterNUICallback('interactionTestNpcSpawn', function(_, cb)
    cb({ ok = true })
    TriggerEvent('cookie_interaction:client:spawnTestNpc')
end)

RegisterNUICallback('interactionTestNpcDelete', function(_, cb)
    cb({ ok = true })
    TriggerEvent('cookie_interaction:client:deleteTestNpc')
end)

print('^2[cookie_admin]^7 mining NPC interaction delegated to cookie_mining V1.6.2')

print('^2[cookie_admin]^7 NPC ROUTER V1.6.6 active')

print('^2[cookie_admin]^7 MINING NPC EXPORT ROUTE V1.6.7 active')

print('^2[cookie_admin]^7 NPC INPUT ROUTER V1.6.8 active')
