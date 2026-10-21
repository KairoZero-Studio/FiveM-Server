

local Z = Config.Zombie
local active = false
local peds = {}
local invincUntil = 0
local diedSent = false
local models = {}
local npcPed = nil
local curTextUi = nil
local spectating = false
local specTargets = {}
local specIdx = 0

local function zTextUi(msg)
    if msg == curTextUi then return end
    curTextUi = msg
    if msg then pcall(function() exports.ox_lib:showTextUI(msg, { position = 'top-center' }) end)
    else pcall(function() exports.ox_lib:hideTextUI() end) end
end

CreateThread(function()
    local list = Z.Models or { Z.Model or 'a_m_m_tramp_01' }
    for _, name in ipairs(list) do
        local m = GetHashKey(name)
        if IsModelValid(m) then
            RequestModel(m)
            local t = GetGameTimer() + 12000
            while not HasModelLoaded(m) and GetGameTimer() < t do Wait(50) end
            if HasModelLoaded(m) then models[#models + 1] = m end
        end
    end
    if #models == 0 then
        local m = GetHashKey(Z.Model or 'a_m_m_tramp_01'); RequestModel(m)
        local t = GetGameTimer() + 8000; while not HasModelLoaded(m) and GetGameTimer() < t do Wait(50) end
        if HasModelLoaded(m) then models[1] = m end
    end
    RequestAnimSet('move_m@drunk@verydrunk')

end)

local function ensureNpc()
    if npcPed and DoesEntityExist(npcPed) then return end
    local nm = GetHashKey(Z.StartNpc.model)
    if not IsModelValid(nm) then return end
    RequestModel(nm)
    local t = GetGameTimer() + 8000
    while not HasModelLoaded(nm) and GetGameTimer() < t do Wait(50) end
    if not HasModelLoaded(nm) then return end
    local c = Z.StartNpc.coord
    npcPed = CreatePed(4, nm, c.x, c.y, c.z - 1.0, c.w or 0.0, false, false)
    SetEntityInvincible(npcPed, true)
    FreezeEntityPosition(npcPed, true)
    SetBlockingOfNonTemporaryEvents(npcPed, true)
    if Z.StartNpc.scenario then TaskStartScenarioInPlace(npcPed, Z.StartNpc.scenario, 0, true) end
    SetModelAsNoLongerNeeded(nm)
end

CreateThread(function()
    ensureNpc()
end)

local function spawnOne(px, py, pz)
    if #models == 0 then return end
    local modelHash = models[math.random(1, #models)]
    local ang = math.random() * 6.2831853
    local r = math.random(math.floor(Z.SpawnRadius.min), math.floor(Z.SpawnRadius.max)) + 0.0
    local x, y = px + math.cos(ang) * r, py + math.sin(ang) * r
    local gz = pz
    local ok, gzz = GetGroundZFor_3dCoord(x, y, pz + 60.0, false)
    if ok then gz = gzz end
    local ped = CreatePed(4, modelHash, x, y, gz, math.random(0, 359) + 0.0, true, true)
    if not ped or ped == 0 then return end
    SetPedRelationshipGroupHash(ped, GetHashKey('ZOMBIE_HUNT'))
    SetPedArmour(ped, Z.Armour or 40)
    SetPedAccuracy(ped, Z.Accuracy or 18)
    SetPedSeeingRange(ped, 200.0); SetPedHearingRange(ped, 200.0)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 46, true); SetPedCombatAttributes(ped, 5, true)
    SetPedCombatRange(ped, 2)
    SetPedDiesInWater(ped, false)
    DisablePedPainAudio(ped, true)
    SetAmbientVoiceName(ped, 'ALIENS')
    if HasAnimSetLoaded('move_m@drunk@verydrunk') then SetPedMovementClipset(ped, 'move_m@drunk@verydrunk', 1.0) end
    TaskCombatPed(ped, PlayerPedId(), 0, 16)
    peds[#peds + 1] = ped
end

local function cleanupZombies()
    for _, p in ipairs(peds) do if DoesEntityExist(p) then DeleteEntity(p) end end
    peds = {}
end

local function startArena()
    CreateThread(function()
        while active do
            local ped = PlayerPedId()
            if not spectating then
                local pc = GetEntityCoords(ped)
                SetEntityInvincible(ped, GetGameTimer() < invincUntil)

                if not diedSent and GetGameTimer() >= invincUntil and IsEntityDead(ped) then
                    diedSent = true
                    spectating = true
                    local c = GetEntityCoords(ped)
                    NetworkResurrectLocalPlayer(c.x, c.y, c.z, GetEntityHeading(ped), false, false)
                    SetEntityHealth(ped, GetEntityMaxHealth(ped))
                    SetEntityVisible(ped, false, false)
                    SetEntityInvincible(ped, true)
                    FreezeEntityPosition(ped, true)
                    cleanupZombies()
                    TriggerServerEvent('cookie_zombie:server:died')
                else

                    local n = 0
                    while #peds < (Z.MaxZombies or 40) and n < (Z.SpawnPerTick or 4) do spawnOne(pc.x, pc.y, pc.z); n = n + 1 end

                    for i = #peds, 1, -1 do
                        local zp = peds[i]
                        if not DoesEntityExist(zp) then table.remove(peds, i)
                        elseif IsPedDeadOrDying(zp, true) then
                            if GetPedSourceOfDeath(zp) == ped then
                                TriggerServerEvent('cookie_zombie:server:kill', NetworkGetNetworkIdFromEntity(zp))
                            end
                            local deadPed = zp
                            table.remove(peds, i)
                            CreateThread(function()
                                Wait(1500)
                                if DoesEntityExist(deadPed) then DeleteEntity(deadPed) end
                            end)
                        elseif #(GetEntityCoords(zp) - pc) > (Z.DespawnDist or 220.0) then
                            DeleteEntity(zp); table.remove(peds, i)
                        end
                    end
                end
            end
            Wait(300)
        end
    end)
end

local function applySpectate()
    if #specTargets == 0 then
        NetworkSetInSpectatorMode(false, PlayerPedId())
        zTextUi('관전 중 · 남은 파티원 없음')
        return
    end
    if specIdx < 1 or specIdx > #specTargets then specIdx = 1 end
    local sid = specTargets[specIdx]
    local pid = GetPlayerFromServerId(sid)
    if pid ~= -1 then
        local tped = GetPlayerPed(pid)
        if tped and DoesEntityExist(tped) then
            NetworkSetInSpectatorMode(true, tped)
        end
    end
    zTextUi(('☠ 사망 · 관전 중 (%d/%d) · [PageUp] 다음'):format(specIdx, #specTargets))
end

CreateThread(function()
    while true do
        local w = 600
        if not active then
            ensureNpc()
            local c = Z.StartNpc.coord
            local d = #(GetEntityCoords(PlayerPedId()) - vector3(c.x, c.y, c.z))
            if d < 2.6 then
                w = 0
                zTextUi('[E] 좀비존 시작')
                if IsControlJustPressed(0, 38) then
                    local ans = lib.alertDialog({
                        header = '좀비존',
                        content = '좀비존을 시작하시겠습니까?\n\n주변 대기 인원이 **함께** 입장하며, 인원이 많을수록 목표 좀비 수가 늘어납니다.',
                        centered = true, cancel = true,
                        labels = { confirm = '입장', cancel = '취소' },
                    })
                    if ans == 'confirm' then TriggerServerEvent('cookie_zombie:server:start') end
                end
            else
                zTextUi(nil)
            end
        end
        Wait(w)
    end
end)

RegisterNetEvent('cookie_zombie:client:enter', function(d)
    active = true; diedSent = false
    invincUntil = GetGameTimer() + (Z.InvincSeconds or 10) * 1000
    local sp = d.spawn or Z.PlayCoord
    local ped = PlayerPedId()
    RequestCollisionAtCoord(sp.x, sp.y, sp.z)
    SetEntityCoords(ped, sp.x + math.random(-3, 3) + 0.0, sp.y + math.random(-3, 3) + 0.0, sp.z, false, false, false, false)
    SetEntityHeading(ped, sp.w or 0.0)
    AddRelationshipGroup('ZOMBIE_HUNT')
    SetRelationshipBetweenGroups(5, GetHashKey('ZOMBIE_HUNT'), GetHashKey('PLAYER'))
    SetRelationshipBetweenGroups(5, GetHashKey('PLAYER'), GetHashKey('ZOMBIE_HUNT'))
    TriggerEvent('cookie_admin:client:notify',
        ('좀비존 입장 · 인원 %d · 목표 %d마리 · %d초 무적'):format(d.count or 1, d.target or 100, Z.InvincSeconds or 10), false)
    zTextUi(('🧟 처치 0 / %d'):format(d.target or 100))
    startArena()
end)

RegisterNetEvent('cookie_zombie:client:progress', function(d)
    if not active then return end
    zTextUi(('🧟 처치 %d / %d'):format(d.kills or 0, d.target or 100))
end)

RegisterNetEvent('cookie_zombie:client:spectate', function(d)
    local me = GetPlayerServerId(PlayerId())
    local t = {}; for _, s in ipairs(d.alive or {}) do if s ~= me then t[#t + 1] = s end end
    specTargets = t; specIdx = 1
    TriggerEvent('cookie_admin:client:notify', '사망 — 관전 모드 (PageUp: 다음 파티원)', true)
    applySpectate()
end)

RegisterNetEvent('cookie_zombie:client:aliveList', function(d)
    if not spectating then return end
    local me = GetPlayerServerId(PlayerId())
    local t = {}; for _, s in ipairs(d.alive or {}) do if s ~= me then t[#t + 1] = s end end
    specTargets = t
    if specIdx > #specTargets then specIdx = 1 end
    applySpectate()
end)

RegisterNetEvent('cookie_zombie:client:missionEnd', function(d)
    if d.result == 'win' then
        TriggerEvent('cookie_admin:client:notify', ('★ 좀비존 클리어! (%d/%d) 보상 +%s원'):format(d.kills or 0, d.target or 0, d.reward or 0), false)
    else
        TriggerEvent('cookie_admin:client:notify', ('미션 실패 · 처치 %d/%d'):format(d.kills or 0, d.target or 0), true)
    end
end)

RegisterCommand('cookie_zombie_spec_next', function()
    if spectating and #specTargets > 0 then
        specIdx = (specIdx % #specTargets) + 1
        applySpectate()
    end
end, false)
RegisterKeyMapping('cookie_zombie_spec_next', '좀비존 관전 다음', 'keyboard', 'PAGEUP')

RegisterNetEvent('cookie_zombie:client:exit', function(d)
    active = false
    local ped = PlayerPedId()
    NetworkSetInSpectatorMode(false, ped)
    SetEntityVisible(ped, true, false)
    FreezeEntityPosition(ped, false)
    SetEntityInvincible(ped, false)
    if GetEntityHealth(ped) <= 0 then SetEntityHealth(ped, GetEntityMaxHealth(ped)) end
    spectating = false; specTargets = {}; specIdx = 0
    cleanupZombies()
    zTextUi(nil)
    local bk = d.back or Z.PlayCoord
    RequestCollisionAtCoord(bk.x, bk.y, bk.z)
    SetEntityCoords(ped, bk.x, bk.y, bk.z, false, false, false, false)
    SetEntityHeading(ped, bk.w or 0.0)
    diedSent = false
    ensureNpc()
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    local ped = PlayerPedId()
    NetworkSetInSpectatorMode(false, ped)
    SetEntityVisible(ped, true, false)
    FreezeEntityPosition(ped, false)
    SetEntityInvincible(ped, false)
    cleanupZombies()
    pcall(function() exports.ox_lib:hideTextUI() end)
    if npcPed and DoesEntityExist(npcPed) then DeleteEntity(npcPed) end
end)
