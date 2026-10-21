local afkPlayers = {}

-- V13.9.1: F3 좌표 관리에서 수정 가능한 잠수존 런타임 설정.
-- config.lua 값은 DB가 비어 있을 때 최초 기본값으로만 사용합니다.
local runtimeConfig = {
    MainPortal = {
        x = Config.MainPortal.x + 0.0, y = Config.MainPortal.y + 0.0,
        z = Config.MainPortal.z + 0.0, h = Config.MainPortal.w + 0.0,
    },
    AfkSpawn = {
        x = Config.AfkSpawn.x + 0.0, y = Config.AfkSpawn.y + 0.0,
        z = Config.AfkSpawn.z + 0.0, h = Config.AfkSpawn.w + 0.0,
    },
    AfkReturnPortal = {
        x = Config.AfkReturnPortal.x + 0.0, y = Config.AfkReturnPortal.y + 0.0,
        z = Config.AfkReturnPortal.z + 0.0, h = 0.0,
    },
    AfkZoneRadius = tonumber(Config.AfkZoneRadius) or 42.0,
}

local function afkSnapshot()
    return {
        MainPortal = {
            x=runtimeConfig.MainPortal.x, y=runtimeConfig.MainPortal.y,
            z=runtimeConfig.MainPortal.z, h=runtimeConfig.MainPortal.h,
        },
        AfkSpawn = {
            x=runtimeConfig.AfkSpawn.x, y=runtimeConfig.AfkSpawn.y,
            z=runtimeConfig.AfkSpawn.z, h=runtimeConfig.AfkSpawn.h,
        },
        AfkReturnPortal = {
            x=runtimeConfig.AfkReturnPortal.x, y=runtimeConfig.AfkReturnPortal.y,
            z=runtimeConfig.AfkReturnPortal.z, h=runtimeConfig.AfkReturnPortal.h,
        },
        AfkZoneRadius = runtimeConfig.AfkZoneRadius,
    }
end

local function ensureAfkConfigTable()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_afkzone_config (
            id TINYINT UNSIGNED NOT NULL PRIMARY KEY,
            main_x DOUBLE NOT NULL,
            main_y DOUBLE NOT NULL,
            main_z DOUBLE NOT NULL,
            main_h DOUBLE NOT NULL DEFAULT 0,
            spawn_x DOUBLE NOT NULL,
            spawn_y DOUBLE NOT NULL,
            spawn_z DOUBLE NOT NULL,
            spawn_h DOUBLE NOT NULL DEFAULT 0,
            exit_x DOUBLE NOT NULL,
            exit_y DOUBLE NOT NULL,
            exit_z DOUBLE NOT NULL,
            exit_h DOUBLE NOT NULL DEFAULT 0,
            zone_radius DOUBLE NOT NULL DEFAULT 42,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        )
    ]])
end

local function persistAfkConfig()
    ensureAfkConfigTable()
    MySQL.query.await([[
        INSERT INTO cookie_afkzone_config
            (id, main_x, main_y, main_z, main_h,
             spawn_x, spawn_y, spawn_z, spawn_h,
             exit_x, exit_y, exit_z, exit_h, zone_radius)
        VALUES
            (1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            main_x=VALUES(main_x), main_y=VALUES(main_y), main_z=VALUES(main_z), main_h=VALUES(main_h),
            spawn_x=VALUES(spawn_x), spawn_y=VALUES(spawn_y), spawn_z=VALUES(spawn_z), spawn_h=VALUES(spawn_h),
            exit_x=VALUES(exit_x), exit_y=VALUES(exit_y), exit_z=VALUES(exit_z), exit_h=VALUES(exit_h),
            zone_radius=VALUES(zone_radius)
    ]], {
        runtimeConfig.MainPortal.x, runtimeConfig.MainPortal.y, runtimeConfig.MainPortal.z, runtimeConfig.MainPortal.h,
        runtimeConfig.AfkSpawn.x, runtimeConfig.AfkSpawn.y, runtimeConfig.AfkSpawn.z, runtimeConfig.AfkSpawn.h,
        runtimeConfig.AfkReturnPortal.x, runtimeConfig.AfkReturnPortal.y, runtimeConfig.AfkReturnPortal.z, runtimeConfig.AfkReturnPortal.h,
        runtimeConfig.AfkZoneRadius,
    })
end

local function pushAfkConfig(target)
    TriggerClientEvent('cookie_afkzone:client:configSync', target or -1, afkSnapshot())
end

local function loadAfkConfig()
    ensureAfkConfigTable()
    local row = MySQL.single.await('SELECT * FROM cookie_afkzone_config WHERE id=1 LIMIT 1')
    if not row then
        persistAfkConfig()
        pushAfkConfig(-1)
        return
    end

    runtimeConfig.MainPortal = {
        x=tonumber(row.main_x) or runtimeConfig.MainPortal.x,
        y=tonumber(row.main_y) or runtimeConfig.MainPortal.y,
        z=tonumber(row.main_z) or runtimeConfig.MainPortal.z,
        h=tonumber(row.main_h) or runtimeConfig.MainPortal.h,
    }
    runtimeConfig.AfkSpawn = {
        x=tonumber(row.spawn_x) or runtimeConfig.AfkSpawn.x,
        y=tonumber(row.spawn_y) or runtimeConfig.AfkSpawn.y,
        z=tonumber(row.spawn_z) or runtimeConfig.AfkSpawn.z,
        h=tonumber(row.spawn_h) or runtimeConfig.AfkSpawn.h,
    }
    runtimeConfig.AfkReturnPortal = {
        x=tonumber(row.exit_x) or runtimeConfig.AfkReturnPortal.x,
        y=tonumber(row.exit_y) or runtimeConfig.AfkReturnPortal.y,
        z=tonumber(row.exit_z) or runtimeConfig.AfkReturnPortal.z,
        h=tonumber(row.exit_h) or runtimeConfig.AfkReturnPortal.h,
    }
    runtimeConfig.AfkZoneRadius = math.max(5.0, math.min(1000.0, tonumber(row.zone_radius) or runtimeConfig.AfkZoneRadius))
    pushAfkConfig(-1)
end

CreateThread(function()
    Wait(500)
    local ok, err = pcall(loadAfkConfig)
    if not ok then
        print(('^1[cookie_afkzone]^7 좌표 설정 DB 로드 실패: %s'):format(tostring(err)))
    end
end)

RegisterNetEvent('cookie_afkzone:server:requestConfig', function()
    pushAfkConfig(source)
end)

exports('GetAdminConfig', function()
    return afkSnapshot()
end)

exports('SetAdminCoord', function(kind, point)
    kind = tostring(kind or '')
    point = type(point) == 'table' and point or {}

    local x, y, z = tonumber(point.x), tonumber(point.y), tonumber(point.z)
    local h = tonumber(point.h) or 0.0
    if not x or not y or not z then
        return false, '좌표 값이 올바르지 않습니다'
    end

    local target
    if kind == 'main' then
        target = runtimeConfig.MainPortal
    elseif kind == 'spawn' then
        target = runtimeConfig.AfkSpawn
    elseif kind == 'return' then
        target = runtimeConfig.AfkReturnPortal
    else
        return false, '알 수 없는 잠수존 좌표 종류입니다'
    end

    target.x, target.y, target.z, target.h = x, y, z, h % 360.0

    local ok, err = pcall(persistAfkConfig)
    if not ok then return false, ('DB 저장 실패: %s'):format(tostring(err)) end

    pushAfkConfig(-1)
    return true, afkSnapshot()
end)

exports('SetAdminRadius', function(radius)
    radius = tonumber(radius)
    if not radius then return false, '반경 값이 올바르지 않습니다' end
    runtimeConfig.AfkZoneRadius = math.max(5.0, math.min(1000.0, radius))

    local ok, err = pcall(persistAfkConfig)
    if not ok then return false, ('DB 저장 실패: %s'):format(tostring(err)) end

    pushAfkConfig(-1)
    return true, afkSnapshot()
end)


local function notify(src, message, isError)
    TriggerClientEvent('cookie_afkzone:client:notify', src, tostring(message or ''), isError == true)
end

local function qbxPlayer(src)
    local ok, p = pcall(function() return exports.qbx_core:GetPlayer(src) end)
    return ok and p or nil
end

local function safezoneByType(zoneType)
    if GetResourceState('cookie_safezone') ~= 'started' then return nil end
    local ok, zone = pcall(function()
        return exports.cookie_safezone:GetZoneByType(zoneType)
    end)
    return ok and type(zone)=='table' and zone or nil
end

local function nearSafezoneType(src, zoneType, margin)
    if GetResourceState('cookie_safezone') ~= 'started' then return false end
    local ok, inside = pcall(function()
        return exports.cookie_safezone:PlayerNearType(src, zoneType, margin or 2.5)
    end)
    return ok and inside == true
end

local function afkDestination()
    -- V13.9.13:
    -- 잠수존 입장/20분 자동이동 목적지는 '잠수존 범위 중심'이 아니라
    -- F3 비콘 관리에서 설정한 '잠수존 퇴장' 비콘 위치를 사용합니다.
    -- 커스텀 섬의 실제 바닥 높이/안전 위치를 그대로 목적지로 쓰기 위함입니다.
    local z = safezoneByType('afk_leave')
    if not z then return nil end
    return {
        x=tonumber(z.cx) or 0.0,
        y=tonumber(z.cy) or 0.0,
        z=tonumber(z.cz) or 0.0,
        h=tonumber(z.heading) or 0.0,
    }
end

local function mainReturnDestination()
    local z = safezoneByType('afk_enter')
    if z then
        return {
            x=tonumber(z.cx) or runtimeConfig.MainPortal.x,
            y=tonumber(z.cy) or runtimeConfig.MainPortal.y,
            z=tonumber(z.cz) or runtimeConfig.MainPortal.z,
            h=tonumber(z.heading) or runtimeConfig.MainPortal.h,
        }
    end
    return {
        x=runtimeConfig.MainPortal.x, y=runtimeConfig.MainPortal.y,
        z=runtimeConfig.MainPortal.z, h=runtimeConfig.MainPortal.h,
    }
end

local function failEnter(src, message)
    notify(src, message, true)
    TriggerClientEvent('cookie_afkzone:client:transferReset', src)
end

local function captureNeeds(src)
    local p = qbxPlayer(src)
    if not p then return 100, 100 end
    local meta = p.PlayerData and p.PlayerData.metadata or {}
    return math.max(0, tonumber(meta.hunger) or 100), math.max(0, tonumber(meta.thirst) or 100)
end

local function setAfkState(src, value)
    local ply = Player(src)
    if not ply or not ply.state then return end
    ply.state:set('cookieAfkZone', value == true, true)
    -- 휴대전화 긴급콜/기존 AFK 연동에서 사용하는 공통 상태.
    ply.state:set('cookieAfk', value == true, true)
end

local function enterAfk(src, reason, wasDead)
    if afkPlayers[src] then
        TriggerClientEvent('cookie_afkzone:client:transferReset', src)
        return
    end
    if Player(src).state.cookieDetained == true then
        return failEnter(src, '구금 중에는 잠수존으로 이동할 수 없습니다.')
    end

    reason = tostring(reason or 'manual')
    local target = afkDestination()
    if not target then
        return failEnter(src, '잠수존 퇴장 비콘이 없습니다. F3 → 관리자 → 비콘 관리에서 "잠수존 퇴장" 비콘을 먼저 만들어 주세요.')
    end

    if reason ~= 'idle' and not nearSafezoneType(src, 'afk_enter', 3.0) then
        return failEnter(src, 'F3에서 만든 잠수존 입장 위치에서 이용하세요.')
    end

    local hunger, thirst = captureNeeds(src)
    afkPlayers[src] = {
        hunger = hunger,
        thirst = thirst,
        enteredAt = os.time(),
        reason = reason,
    }

    if wasDead == true then
        pcall(function() exports.qbx_medical:Revive(src) end)
    end

    SetPlayerRoutingBucket(src, tonumber(Config.RoutingBucket) or 7777)
    setAfkState(src, true)

    SetTimeout(wasDead == true and 650 or 150, function()
        if GetPlayerName(src) == nil or not afkPlayers[src] then return end
        TriggerClientEvent('cookie_afkzone:client:teleport', src, {
            mode = 'enter',
            x = target.x, y = target.y, z = target.z, h = target.h,
            revive = wasDead == true,
            reason = reason,
        })
    end)
end

RegisterNetEvent('cookie_afkzone:server:enter', function(reason, wasDead)
    enterAfk(source, reason, wasDead == true)
end)

RegisterNetEvent('cookie_afkzone:server:leave', function()
    local src = source
    if GetPlayerName(src) == nil then return end

    -- V14.2.3 EXIT STATE RECOVERY
    -- 예전에는 afkPlayers[src]가 없으면 즉시 return해서,
    -- 리소스 재시작/StateBag 지연 등으로 메모리 추적값이 사라진 유저가
    -- 잠수존에서 영구적으로 못 나가는 문제가 있었다.
    local ply = Player(src)
    local stateAfk = false
    if ply and ply.state then
        stateAfk = ply.state.cookieAfkZone == true or ply.state.cookieAfk == true
    end

    local tracked = afkPlayers[src] ~= nil
    local bucket = GetPlayerRoutingBucket(src)
    local afkBucket = tonumber(Config.RoutingBucket) or 7777
    local inAfkBucket = bucket == afkBucket
    local nearExit = nearSafezoneType(src, 'afk_leave', 4.0)

    -- 정상적인 AFK 상태, AFK 라우팅 버킷, 또는 실제 퇴장 비콘 근처 중
    -- 하나라도 확인되면 복구 가능한 정상 퇴장으로 처리한다.
    if not tracked and not stateAfk and not inAfkBucket and not nearExit then
        notify(src, '현재 잠수존 퇴장 위치가 아닙니다.', true)
        TriggerClientEvent('cookie_afkzone:client:transferReset', src)
        return
    end

    afkPlayers[src] = nil
    setAfkState(src, false)
    SetPlayerRoutingBucket(src, 0)

    local target = mainReturnDestination()
    TriggerClientEvent('cookie_afkzone:client:teleport', src, {
        mode = 'leave',
        x = target.x, y = target.y, z = target.z, h = target.h,
        revive = false,
    })
end)

CreateThread(function()
    while true do
        Wait(math.max(1000, tonumber(Config.NeedsKeepIntervalMs) or 2000))
        for src, data in pairs(afkPlayers) do
            if GetPlayerName(src) == nil then
                afkPlayers[src] = nil
            else
                local p = qbxPlayer(src)
                if p and p.Functions then
                    local meta = p.PlayerData and p.PlayerData.metadata or {}
                    local hunger = tonumber(meta.hunger) or data.hunger or 100
                    local thirst = tonumber(meta.thirst) or data.thirst or 100

                    -- 입장 당시 수치 아래로는 내려가지 않게 유지.
                    -- AFK 중 다른 효과로 올라간 수치는 그대로 보존한다.
                    if hunger > (data.hunger or 0) then data.hunger = hunger end
                    if thirst > (data.thirst or 0) then data.thirst = thirst end
                    if hunger < (data.hunger or 0) then p.Functions.SetMetaData('hunger', data.hunger) end
                    if thirst < (data.thirst or 0) then p.Functions.SetMetaData('thirst', data.thirst) end
                end
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    afkPlayers[source] = nil
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for src in pairs(afkPlayers) do
        if GetPlayerName(src) ~= nil then
            setAfkState(src, false)
            SetPlayerRoutingBucket(src, 0)
        end
    end
end)

print('^2[cookie_afkzone]^7 V14.2.3 EXIT STATE RECOVERY ready · idle 20m')
