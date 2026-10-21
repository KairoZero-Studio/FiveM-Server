-- Cookie faction shop NPC client V2
-- Distance-streamed local peds + custom prompt/shop HUD.

local peds = {}
local loading = {}
local positions = {}
local shopOpen = false
local currentShopNpc = nil
local promptNpc = nil

local SPAWN_DISTANCE = 110.0
local DESPAWN_DISTANCE = 135.0
local INTERACT_DISTANCE = 2.35

local function notify(message, kind)
    if lib and lib.notify then
        lib.notify({ title = '팩션 상점', description = message, type = kind or 'inform' })
    end
end

local function deletePed(id)
    local ped = peds[id]
    peds[id] = nil
    loading[id] = nil
    if ped and DoesEntityExist(ped) then
        DeleteEntity(ped)
    end
end

local function clearPeds()
    for id in pairs(peds) do deletePed(id) end
    peds = {}
    loading = {}
end

local function applyNpcBehaviour(ped, n)
    SetEntityAsMissionEntity(ped, true, true)
    SetEntityInvincible(ped, true)
    SetEntityCanBeDamaged(ped, false)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    SetPedCanEvasiveDive(ped, false)
    SetPedDropsWeaponsWhenDead(ped, false)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 17, true)
    SetPedSeeingRange(ped, 0.0)
    SetPedHearingRange(ped, 0.0)
    SetPedAlertness(ped, 0)
    SetPedKeepTask(ped, true)
    SetEntityHeading(ped, tonumber(n.heading) or 0.0)
    FreezeEntityPosition(ped, true)

    local scenario = tostring(n.scenario or 'WORLD_HUMAN_STAND_MOBILE')
    if scenario ~= '' and scenario ~= 'NONE' then
        TaskStartScenarioInPlace(ped, scenario, 0, true)
    end
end

local function spawnNpc(id, n)
    if peds[id] or loading[id] then return end
    loading[id] = true

    CreateThread(function()
        local model = joaat(tostring(n.model or 'a_m_y_business_01'))
        if not IsModelInCdimage(model) or not IsModelValid(model) or not IsModelAPed(model) then
            loading[id] = nil
            return
        end

        RequestModel(model)
        local limit = GetGameTimer() + 5000
        while not HasModelLoaded(model) and GetGameTimer() < limit do Wait(0) end

        -- The row may have changed/deleted while the model was loading.
        if not HasModelLoaded(model) or positions[id] ~= n then
            SetModelAsNoLongerNeeded(model)
            loading[id] = nil
            return
        end

        local ped = CreatePed(4, model, tonumber(n.x) or 0.0, tonumber(n.y) or 0.0, tonumber(n.z) or 0.0,
            tonumber(n.heading) or 0.0, false, false)
        if DoesEntityExist(ped) then
            SetEntityCoordsNoOffset(ped, tonumber(n.x) or 0.0, tonumber(n.y) or 0.0, tonumber(n.z) or 0.0, false, false, false)
            applyNpcBehaviour(ped, n)
            peds[id] = ped
        end

        SetModelAsNoLongerNeeded(model)
        loading[id] = nil
    end)
end

local function hidePrompt()
    if promptNpc ~= nil then
        promptNpc = nil
        SendNUIMessage({ action = 'factionNpcPrompt', show = false })
    end
end

local function showPrompt(id, n)
    if promptNpc == id then return end
    promptNpc = id
    SendNUIMessage({
        action = 'factionNpcPrompt',
        show = true,
        label = tostring(n.label or '팩션 판매 담당자'),
        factionName = tostring(n.faction_name or '팩션 상점'),
        factionColor = tostring(n.faction_color or '#FFB800'),
        factionEmoji = tostring(n.faction_emoji or ''),
    })
end

local function releaseShopFocus()
    if CookieAdminSetNuiFocus then
        CookieAdminSetNuiFocus(false, false)
    else
        SetNuiFocus(false, false)
        if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
    end
end

local function closeShop(reason)
    if not shopOpen then return end
    shopOpen = false
    currentShopNpc = nil
    releaseShopFocus()
    SendNUIMessage({ action = 'factionShopClose' })
    TriggerEvent('cookie_hud:client:hudVisible', true)
    if reason then notify(reason, 'error') end
end

RegisterNetEvent('cookie_admin:factionNpcForceClose', function()
    closeShop()
end)

function CookieFactionNpcShopIsOpen()
    return shopOpen
end

RegisterNetEvent('cookie_admin:factionNpcSync', function(rows)
    clearPeds()
    positions = {}
    for _, n in ipairs(rows or {}) do
        local id = tonumber(n.id)
        if id then positions[id] = n end
    end
end)

CreateThread(function()
    Wait(1800)
    TriggerServerEvent('cookie_admin:factionNpcSyncRequest')
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    Wait(1000)
    TriggerServerEvent('cookie_admin:factionNpcSyncRequest')
end)

-- Only create NPC peds near the player. This keeps large faction setups cheap client-side.
CreateThread(function()
    while true do
        local playerPed = PlayerPedId()
        if playerPed ~= 0 and DoesEntityExist(playerPed) then
            local pos = GetEntityCoords(playerPed)
            for id, n in pairs(positions) do
                local dist = #(pos - vector3(tonumber(n.x), tonumber(n.y), tonumber(n.z)))
                if dist <= SPAWN_DISTANCE then
                    spawnNpc(id, n)
                elseif dist >= DESPAWN_DISTANCE then
                    deletePed(id)
                end
            end
        end
        Wait(1000)
    end
end)

local function openShop(id)
    if shopOpen or (CookieAdminPanelIsOpen and CookieAdminPanelIsOpen()) then return end
    local r = lib.callback.await('cookie_admin:factionNpcItems', false, id)
    if not r or r.error then
        notify((r and r.error) or '판매 목록을 불러오지 못했습니다.', 'error')
        return
    end

    local focusOk = true
    if CookieAdminSetNuiFocus then
        focusOk = CookieAdminSetNuiFocus(true, false)
    else
        SetNuiFocus(true, true)
        if SetCursorLocation then SetCursorLocation(0.5, 0.5) end
    end
    if focusOk == false then
        notify('다른 UI가 열려 있습니다. 먼저 닫아주세요.', 'error')
        return
    end

    shopOpen = true
    currentShopNpc = id
    hidePrompt()
    TriggerEvent('cookie_hud:client:hudVisible', false)
    SendNUIMessage({
        action = 'factionShopOpen',
        npcId = id,
        npcLabel = r.label,
        factionName = r.factionName,
        factionColor = r.factionColor,
        factionEmoji = r.factionEmoji,
        cash = tonumber(r.cash) or 0,
        maxQuantity = 20,
        items = r.items or {},
    })
end

-- Interaction finder: chooses one nearest NPC and drives the lightweight NUI prompt.
CreateThread(function()
    while true do
        local waitMs = 400
        if not shopOpen and not IsPauseMenuActive() and not (CookieAdminPanelIsOpen and CookieAdminPanelIsOpen()) then
            local playerPed = PlayerPedId()
            if playerPed ~= 0 and not IsPedInAnyVehicle(playerPed, false) and not IsEntityDead(playerPed) then
                local pos = GetEntityCoords(playerPed)
                local nearestId, nearest, nearestDist = nil, nil, INTERACT_DISTANCE + 0.001

                for id, n in pairs(positions) do
                    if peds[id] and DoesEntityExist(peds[id]) then
                        local dist = #(pos - vector3(tonumber(n.x), tonumber(n.y), tonumber(n.z)))
                        if dist < nearestDist then
                            nearestId, nearest, nearestDist = id, n, dist
                        end
                    end
                end

                if nearestId then
                    waitMs = 0
                    showPrompt(nearestId, nearest)
                    if IsControlJustReleased(0, 38) then -- E
                        hidePrompt()
                        openShop(nearestId)
                    end
                else
                    hidePrompt()
                end
            else
                hidePrompt()
            end
        else
            hidePrompt()
        end
        Wait(waitMs)
    end
end)

-- Close automatically if the player walks away while the shop is open.
CreateThread(function()
    while true do
        if shopOpen and currentShopNpc then
            local n = positions[currentShopNpc]
            local playerPed = PlayerPedId()
            if not n or playerPed == 0 or IsEntityDead(playerPed) then
                closeShop('상점을 이용할 수 없는 상태입니다.')
            else
                local pos = GetEntityCoords(playerPed)
                local dist = #(pos - vector3(tonumber(n.x), tonumber(n.y), tonumber(n.z)))
                if dist > 4.25 then closeShop('NPC와 거리가 멀어져 상점이 닫혔습니다.') end
            end
            Wait(250)
        else
            Wait(750)
        end
    end
end)

RegisterNUICallback('factionShopClose', function(_, cb)
    closeShop()
    cb({ ok = true })
end)

RegisterNUICallback('factionShopPurchase', function(data, cb)
    if not shopOpen or not currentShopNpc then
        cb({ ok = false, message = '상점이 닫혀 있습니다.' })
        return
    end
    local itemCode = tostring(data and data.itemCode or '')
    local quantity = tonumber(data and data.quantity)
    local result = lib.callback.await('cookie_admin:factionNpcPurchase', false, currentShopNpc, itemCode, quantity)
    cb(result or { ok = false, message = '구매 요청에 실패했습니다.' })
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    closeShop()
    hidePrompt()
    clearPeds()
end)
