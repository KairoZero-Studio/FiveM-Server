local furniture = {}
local entities = {}
local cosmetics = {}
local placing = false
local ownCitizenid = nil
local seatedFurniture = nil
local seatedStartedAt = 0

local function notify(msg, bad)
    TriggerEvent('cookie_admin:client:notify', tostring(msg or ''), bad == true)
end

local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(tostring(model or ''))
    if hash == 0 or not IsModelInCdimage(hash) or not IsModelValid(hash) then return nil end
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(0) end
    if not HasModelLoaded(hash) then return nil end
    return hash
end

local function destroyEntity(id)
    local ent = entities[tonumber(id)]
    if ent and DoesEntityExist(ent) then DeleteEntity(ent) end
    entities[tonumber(id)] = nil
end

local function spawnOne(info)
    if type(info) ~= 'table' then return end
    local id = tonumber(info.id)
    if not id then return end
    destroyEntity(id)

    local hash = loadModel(info.model)
    if not hash then return end
    local obj = CreateObjectNoOffset(hash, info.x+0.0, info.y+0.0, info.z+0.0, false, false, false)
    if obj and obj ~= 0 then
        SetEntityHeading(obj, tonumber(info.heading) or 0.0)
        FreezeEntityPosition(obj, true)
        SetEntityInvincible(obj, true)
        SetEntityAsMissionEntity(obj, true, false)
        entities[id] = obj
    end
    SetModelAsNoLongerNeeded(hash)
end

RegisterNetEvent('cookie_assets:client:syncFurniture', function(rows)
    for id in pairs(entities) do destroyEntity(id) end
    furniture = {}
    if type(rows) ~= 'table' then return end
    for k, v in pairs(rows) do
        local id = tonumber(v.id or k)
        if id then
            v.id = id
            furniture[id] = v
            spawnOne(v)
        end
    end
end)

RegisterNetEvent('cookie_assets:client:setOwnCitizenid', function(cid)
    ownCitizenid = cid and tostring(cid) or nil
end)

RegisterNetEvent('cookie_assets:client:addFurniture', function(info)
    if not info or not info.id then return end
    local id = tonumber(info.id)
    furniture[id] = info
    spawnOne(info)
end)

RegisterNetEvent('cookie_assets:client:removeFurniture', function(id)
    id = tonumber(id)
    if not id then return end
    destroyEntity(id)
    furniture[id] = nil
end)

local function applyCosmetic(data)
    if type(data) ~= 'table' then return end
    local slot = tonumber(data.slot)
    local drawable = tonumber(data.drawable)
    local texture = tonumber(data.texture) or 0
    if not slot or not drawable then return end
    cosmetics[slot] = {slot=slot,drawable=drawable,texture=texture}
    local ped = PlayerPedId()
    if drawable < 0 then
        ClearPedProp(ped, slot)
    else
        SetPedPropIndex(ped, slot, drawable, texture, true)
    end
end

RegisterNetEvent('cookie_assets:client:applyCosmetic', applyCosmetic)
RegisterNetEvent('cookie_assets:client:clearCosmetic', function(slot)
    slot = tonumber(slot)
    if not slot then return end
    cosmetics[slot] = nil
    ClearPedProp(PlayerPedId(), slot)
end)

RegisterNetEvent('cookie_assets:client:syncCosmetics', function(rows)
    cosmetics = {}
    if type(rows) ~= 'table' then return end
    for _, r in ipairs(rows) do
        local slot, drawable, texture = tostring(r.reward_key or ''):match('^prop:(%d+):(%-?%d+):(%d+)$')
        if slot then
            applyCosmetic({slot=tonumber(slot),drawable=tonumber(drawable),texture=tonumber(texture)})
        end
    end
end)

local function drawHelp(text)
    SetTextFont(0)
    SetTextScale(0.34, 0.34)
    SetTextColour(255,255,255,235)
    SetTextCentre(true)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.5, 0.88)
end

local function draw3d(x,y,z,text)
    local ok,sx,sy = World3dToScreen2d(x,y,z)
    if not ok then return end
    SetTextScale(0.30,0.30)
    SetTextFont(0)
    SetTextProportional(1)
    SetTextColour(255,255,255,220)
    SetTextCentre(true)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(sx,sy)
end

RegisterNetEvent('cookie_assets:client:beginFurniturePlacement', function(ownedId)
    if placing then return notify('이미 가구 설치 중입니다.', true) end
    local info = lib.callback.await('cookie_assets:validateFurniture', false, tonumber(ownedId))
    if not info or not info.ok then return notify(info and info.message or '가구 정보를 불러오지 못했습니다.', true) end

    local hash = loadModel(info.model)
    if not hash then return notify(('존재하지 않는 GTA 오브젝트 모델입니다: %s'):format(tostring(info.model)), true) end

    placing = true
    local ped = PlayerPedId()
    local heading = GetEntityHeading(ped)
    local dist = 1.5
    local zOffset = 0.0
    local preview = 0

    CreateThread(function()
        while placing do
            ped = PlayerPedId()
            local pos = GetOffsetFromEntityInWorldCoords(ped, 0.0, dist, 0.0)
            local found, ground = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 2.0, false)
            local z = (found and ground or pos.z) + zOffset

            if preview == 0 or not DoesEntityExist(preview) then
                preview = CreateObjectNoOffset(hash, pos.x, pos.y, z, false, false, false)
                SetEntityAlpha(preview, 170, false)
                SetEntityCollision(preview, false, false)
                FreezeEntityPosition(preview, true)
            else
                SetEntityCoordsNoOffset(preview, pos.x, pos.y, z, false, false, false)
            end
            SetEntityHeading(preview, heading)

            DisableControlAction(0, 172, true)
            DisableControlAction(0, 173, true)
            DisableControlAction(0, 174, true)
            DisableControlAction(0, 175, true)
            DisableControlAction(0, 38, true)
            DisableControlAction(0, 202, true)

            if IsDisabledControlJustPressed(0,174) then heading = heading + (Config.Furniture.RotateStep or 5.0) end
            if IsDisabledControlJustPressed(0,175) then heading = heading - (Config.Furniture.RotateStep or 5.0) end
            if IsDisabledControlPressed(0,172) then dist = math.min(3.5, dist + (Config.Furniture.MoveStep or 0.12)) end
            if IsDisabledControlPressed(0,173) then dist = math.max(0.8, dist - (Config.Furniture.MoveStep or 0.12)) end

            drawHelp('←/→ 회전  ·  ↑/↓ 거리  ·  E 설치  ·  ESC 취소')

            if IsDisabledControlJustReleased(0,38) then
                placing = false
                local c = GetEntityCoords(preview)
                TriggerServerEvent('cookie_assets:server:placeFurniture', {
                    ownedId=info.ownedId, x=c.x,y=c.y,z=c.z,heading=heading
                })
            elseif IsDisabledControlJustReleased(0,202) then
                placing = false
                notify('가구 설치를 취소했습니다.', false)
            end
            Wait(0)
        end

        if preview ~= 0 and DoesEntityExist(preview) then DeleteEntity(preview) end
        SetModelAsNoLongerNeeded(hash)
    end)
end)

CreateThread(function()
    while true do
        local sleep = 700
        local ped = PlayerPedId()
        local pc = GetEntityCoords(ped)
        local myCid = ownCitizenid

        for id, info in pairs(furniture) do
            local dx,dy,dz = pc.x-(info.x or 0), pc.y-(info.y or 0), pc.z-(info.z or 0)
            local d = math.sqrt(dx*dx+dy*dy+dz*dz)
            if d <= (Config.Furniture.InteractDistance or 1.65) then
                sleep = 0
                local own = myCid and tostring(myCid) == tostring(info.citizenid)
                local text
                if info.sit then
                    text = own and '[E] 앉기  [G] 회수' or '[E] 앉기'
                else
                    text = own and '[G] 회수' or tostring(info.label or '가구')
                end
                draw3d(info.x, info.y, info.z + 1.0, text)

                if info.sit and IsControlJustReleased(0,38) then
                    if seatedFurniture then
                        TriggerServerEvent('cookie_assets:server:seatState', seatedFurniture, false)
                    end
                    ClearPedTasksImmediately(ped)
                    TaskStartScenarioAtPosition(
                        ped, 'PROP_HUMAN_SEAT_CHAIR_MP_PLAYER',
                        info.x+0.0, info.y+0.0, info.z+0.45,
                        tonumber(info.heading) or 0.0, -1, true, false
                    )
                    seatedFurniture = id
                    seatedStartedAt = GetGameTimer()
                    TriggerServerEvent('cookie_assets:server:seatState', id, true)
                end
                if own and IsControlJustReleased(0,47) then
                    TriggerServerEvent('cookie_assets:server:pickupFurniture', id)
                    Wait(500)
                end
            end
        end
        Wait(sleep)
    end
end)

-- COOKIE furniture seat lifecycle: movement/standing up ends recovery, AFK does not.
CreateThread(function()
    while true do
        if seatedFurniture then
            local ped = PlayerPedId()
            local info = furniture[seatedFurniture]
            local valid = info and DoesEntityExist(ped)
            if valid then
                local pc = GetEntityCoords(ped)
                local dx,dy,dz = pc.x-(info.x or 0), pc.y-(info.y or 0), pc.z-(info.z or 0)
                local closeEnough = math.sqrt(dx*dx+dy*dy+dz*dz) <= 3.0
                local scenarioReady = (GetGameTimer() - seatedStartedAt) < 2500 or IsPedUsingAnyScenario(ped)
                valid = closeEnough and scenarioReady
            end
            if not valid then
                TriggerServerEvent('cookie_assets:server:seatState', seatedFurniture, false)
                seatedFurniture = nil
                seatedStartedAt = 0
            end
            Wait(500)
        else
            Wait(1000)
        end
    end
end)

CreateThread(function()
    Wait(2200)
    TriggerServerEvent('cookie_assets:server:requestSync')
    while true do
        Wait(10000)
        local ped = PlayerPedId()
        for _, c in pairs(cosmetics) do
            if c.drawable < 0 then
                ClearPedProp(ped,c.slot)
            else
                SetPedPropIndex(ped,c.slot,c.drawable,c.texture or 0,true)
            end
        end
    end
end)

AddEventHandler('playerSpawned', function()
    Wait(1200)
    TriggerServerEvent('cookie_assets:server:requestSync')
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if seatedFurniture then TriggerServerEvent('cookie_assets:server:seatState', seatedFurniture, false) end
    for id in pairs(entities) do destroyEntity(id) end
end)
