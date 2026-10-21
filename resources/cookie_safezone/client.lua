

local zoneDefs = {}
local zones = {}
local insideIds = {}

local insideByType = {}
local dimmedPeds = {}
local effectGen = 0

local function countOf(t) return insideByType[t] or 0 end

local TYPE_HANDLERS

local function undimPed(ped)
    if DoesEntityExist(ped) then

        SetEntityAlpha(ped, 255, false)
        ResetEntityAlpha(ped)
    end
    dimmedPeds[ped] = nil
end

local function undimAll()
    local n = 0
    for ped in pairs(dimmedPeds) do
        undimPed(ped)
        n = n + 1
    end
    dimmedPeds = {}
    if n > 0 then  end
    return n
end

local function inMyActiveZone(coords)
    for id in pairs(insideIds) do
        local def = zoneDefs[id]
        local z = zones[id]
        if def and def.type == 'safezone' and z and z:contains(coords) then return true end
    end
    return false
end

local function updateAlphas()
    local me = PlayerId()
    local seen = {}

    for _, p in ipairs(GetActivePlayers()) do
        if p ~= me then
            local ped = GetPlayerPed(p)
            if ped ~= 0 and DoesEntityExist(ped) and inMyActiveZone(GetEntityCoords(ped)) then
                seen[ped] = true
                if not dimmedPeds[ped] then
                    SetEntityAlpha(ped, Config.AlphaValue, false)
                    dimmedPeds[ped] = true
                end
            end
        end
    end

    for ped in pairs(dimmedPeds) do
        if not seen[ped] then undimPed(ped) end
    end
end

local function startEffectThread()
    effectGen = effectGen + 1
    local myGen = effectGen
    CreateThread(function()
        local nextAlpha = 0

        while countOf('safezone') > 0 and effectGen == myGen do
            local ped = PlayerPedId()

            DisablePlayerFiring(PlayerId(), true)

            DisableControlAction(0, 24, true)
            DisableControlAction(0, 257, true)
            DisableControlAction(0, 140, true)
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)
            DisableControlAction(0, 143, true)
            DisableControlAction(0, 263, true)
            DisableControlAction(0, 264, true)

            SetEntityInvincible(ped, true)
            SetPlayerInvincible(PlayerId(), true)

            local now = GetGameTimer()
            if now >= nextAlpha then
                nextAlpha = now + Config.AlphaInterval
                updateAlphas()
            end
            Wait(0)
        end
    end)
end

local function clearEffects()
    local ped = PlayerPedId()

    SetEntityInvincible(ped, false)
    SetPlayerInvincible(PlayerId(), false)
    undimAll()
end

local boundaries = {}

local function boxPerimeter(def)
    local c = def.center
    local rad = math.rad(def.heading or 0.0)
    local cs, sn = math.cos(rad), math.sin(rad)
    local hl, hw = def.size.length * 0.5, def.size.width * 0.5
    local corners = {}
    local locals = { { hl, hw }, { hl, -hw }, { -hl, -hw }, { -hl, hw } }
    for i = 1, 4 do
        local lx, ly = locals[i][1], locals[i][2]
        corners[i] = vec3(c.x + lx * cs - ly * sn, c.y + lx * sn + ly * cs, c.z)
    end

    local perim = 2 * (def.size.length + def.size.width)
    local total = math.min(Config.boundary.maxSegments, math.max(8, math.floor(perim / Config.boundary.segmentLength)))
    local perEdge = math.max(2, math.floor(total / 4))

    local points = {}
    for i = 1, 4 do
        local a, b = corners[i], corners[i % 4 + 1]
        for s = 0, perEdge - 1 do
            local t = s / perEdge
            points[#points + 1] = vec3(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, c.z)
        end
    end
    return points, math.sqrt(hl * hl + hw * hw)
end

local function polyPerimeter(def)
    local points = {}
    local maxReach = 0.0
    for i, pt in ipairs(def.polyPoints or {}) do
        local p = vec3(pt.x, pt.y, pt.z)
        points[i] = p
        local d = #(def.center - p)
        if d > maxReach then maxReach = d end
    end
    return points, maxReach
end

local function spherePerimeter(def)
    local c = def.center

    local exact = Config.boundary.exactVisualTypes
        and Config.boundary.exactVisualTypes[def.type]

    -- 안전지대는 기존 최소 시각 반경을 유지한다.
    -- 차고/옷장/편의점/무장고/출퇴근 등 상호작용 비콘은
    -- 실제 E 판정 반경(def.radius)은 건드리지 않고 표시 원만 작게 그린다.
    local handler = TYPE_HANDLERS and TYPE_HANDLERS[def.type]
    local isBeacon = def.type ~= 'safezone' and handler and handler.marker ~= 'none'

    local r
    if isBeacon then
        local scale = Config.boundary.beaconVisualScale or 1.0
        local minR = Config.boundary.beaconMinVisualRadius or 0.0
        r = math.max((tonumber(def.radius) or 1.0) * scale, minR)
    elseif exact then
        r = def.radius
    else
        r = math.max(def.radius, Config.boundary.minVisualRadius or 0)
    end

    local total = math.min(Config.boundary.maxSegments,
        math.max(Config.boundary.minSegments or 12,
            math.floor((2 * math.pi * r) / Config.boundary.segmentLength)))
    local points = {}
    for i = 0, total - 1 do
        local a = (i / total) * math.pi * 2.0
        points[#points + 1] = vec3(c.x + math.cos(a) * r, c.y + math.sin(a) * r, c.z)
    end
    return points, r
end

local SNAP_RANGE = 120.0
local SNAP_BUDGET = 24

local function trySnap(b, playerCoords)
    local budget = SNAP_BUDGET
    local maxD = Config.boundary.maxSnapDelta or 3.0

    for i = 1, #b.points do
        if not b.snapped[i] then
            local p = b.points[i]
            if #(playerCoords - p) < SNAP_RANGE then

                local found, gz = GetGroundZFor_3dCoord(p.x, p.y, p.z + 1.0, false)
                if found then

                    if math.abs(gz - p.z) <= maxD then
                        b.points[i] = vec3(p.x, p.y, gz)
                    end

                    b.snapped[i] = true
                    b.pending = b.pending - 1
                    if b.pending == 0 then

                    end
                end
                budget = budget - 1
                if budget <= 0 then return end
            end
        end
    end
end

local function fadeFactor(cfg, d)
    if d >= cfg.fadeDistance then return 0.0 end
    if d <= cfg.renderDistance then return 1.0 end
    return (cfg.fadeDistance - d) / (cfg.fadeDistance - cfg.renderDistance)
end

local function drawQuad(ax, ay, az0, az1, bx, by, bz0, bz1, r, g, bl, a)

    DrawPoly(ax, ay, az0, bx, by, bz0, bx, by, bz1, r, g, bl, a)
    DrawPoly(ax, ay, az0, bx, by, bz1, ax, ay, az1, r, g, bl, a)

    DrawPoly(bx, by, bz1, bx, by, bz0, ax, ay, az0, r, g, bl, a)
    DrawPoly(ax, ay, az1, bx, by, bz1, ax, ay, az0, r, g, bl, a)
end

local function drawLightWall(p, q, cfg, fade, col)
    local bands = cfg.wallBands
    local hStep = cfg.wallHeight / bands
    local baseA = cfg.alpha * fade

    local pz = p.z + cfg.groundOffset
    local qz = q.z + cfg.groundOffset

    for i = 0, bands - 1 do

        local t = (i + 0.5) / bands
        local a = math.floor(baseA * (1.0 - t) ^ cfg.fadePower + 0.5)
        if a > 0 then
            local z0, z1 = i * hStep, (i + 1) * hStep
            drawQuad(p.x, p.y, pz + z0, pz + z1, q.x, q.y, qz + z0, qz + z1, col.r, col.g, col.b, a)
        end
    end
end

local function drawWallBoundary(b, playerCoords, col)
    local cfg = Config.boundary
    if cfg.snapToGround and b.pending > 0 then trySnap(b, playerCoords) end

    local n = #b.points
    local drawn = 0

    for i = 1, n do
        local p = b.points[i]
        local q = b.points[i % n + 1]

        local mx, my, mz = (p.x + q.x) * 0.5, (p.y + q.y) * 0.5, (p.z + q.z) * 0.5
        local fade = fadeFactor(cfg, #(playerCoords - vec3(mx, my, mz)))
        if fade > 0 then
            drawLightWall(p, q, cfg, fade, col)
            drawn = drawn + 1
        end
    end
    return drawn
end

local function drawCoronaBoundary(b, playerCoords, col)
    local cc = Config.corona
    if #(playerCoords - b.center) > cc.renderDistance then return 0 end
    local gz = b.coronaGroundZ
    if not gz then
        local ok, g = GetGroundZFor_3dCoord(b.center.x, b.center.y, b.center.z + 2.0, false)
        if ok then b.coronaGroundZ = g; gz = g else gz = b.center.z end
    end
    DrawMarker(cc.markerType, b.center.x, b.center.y, gz + cc.zOffset,
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        cc.scale, cc.scale, cc.scale,
        col.r, col.g, col.b, col.a or 120, false, false, 2, true, nil, nil, false)
    return 1
end

CreateThread(function()
    while true do
        local wait = 500
        if Config.boundary.enabled then
            local coords = GetEntityCoords(PlayerPedId())
            local near = false
            for id, b in pairs(boundaries) do
                local def = zoneDefs[id]
                local h = def and TYPE_HANDLERS[def.type]
                if h then

                    if h.marker ~= 'none' and #(coords - b.center) <= b.cullDist then
                        -- 커스텀 잠수섬 안에서는 겹쳐 있는 보호구역의 노란 벽 경계도 숨깁니다.
                        -- 판정 자체는 유지되며, 차고 같은 corona 비콘은 영향을 받지 않습니다.
                        local hideWallInAfk = (LocalPlayer.state.cookieAfkZone == true and h.marker == 'wall')
                        if not hideWallInAfk then
                            local col = h.color
                            if def.beaconR and def.beaconG and def.beaconB then
                                col = { r = def.beaconR, g = def.beaconG, b = def.beaconB, a = def.beaconA or 130 }
                            end
                            if h.marker == 'corona' then
                                drawCoronaBoundary(b, coords, col)
                            else
                                drawWallBoundary(b, coords, col)
                            end
                            near = true
                        end
                    end
                end
            end
            if near then wait = 0 end
        end
        Wait(wait)
    end
end)

local function showBanner(kind)
    SendNUIMessage({ action = 'banner', kind = kind })
end

TYPE_HANDLERS = {

    mapmark = {
        marker = 'none',
        color = { r = 255, g = 184, b = 0 },
        onEnter = function() end,
        onExit = function() end,
    },

    fishing = {
        marker = 'none',
        color = { r = 80, g = 170, b = 255 },
        onEnter = function() end,
        onExit = function() end,
    },

    mining = {
        marker = 'none',
        color = { r = 214, g = 168, b = 76 },
        onEnter = function() end,
        onExit = function() end,
    },

    afkzone = {
        marker = 'none',
        color = { r = 110, g = 145, b = 255, a = 120 },
        onEnter = function() end,
        onExit = function() end,
    },

    safezone = {
        marker = 'wall',
        color = { r = 255, g = 200, b = 0 },
        onEnter = function(_, count)
            if count ~= 1 then return end
            PlaySoundFrontend(-1, Config.EnterSound.name, Config.EnterSound.set, true)
            showBanner('enter')
            startEffectThread()
        end,
        onExit = function(_, count)
            if count > 0 then return end
            PlaySoundFrontend(-1, Config.ExitSound.name, Config.ExitSound.set, true)
            showBanner('exit')
            clearEffects()

        end,
    },
    garage = {
        marker = 'corona',
        color = { r = 62, g = 194, b = 106, a = 120 },

        onEnter = function(def, count)
            if count ~= 1 then return end

        end,
        onExit = function(def, count)
            if count > 0 then return end

        end,
    },
}

local DISPLAY_ONLY_TYPES = {
    wardrobe      = { label = '옷장',   color = { r = 80,  g = 170, b = 255, a = 120 } },
    charzone      = { label = '커마존', color = { r = 170, g = 90,  b = 230, a = 120 } },
    afk_enter     = { label = '잠수존 입장', color = { r = 90,  g = 170, b = 255, a = 125 } },
    afk_leave     = { label = '잠수존 퇴장', color = { r = 255, g = 190, b = 70,  a = 125 } },

    garage_lspd   = { label = '차고(구)', color = { r = 66,  g = 133, b = 244, a = 120 } },
    garage_lssd   = { label = '차고(구)', color = { r = 194, g = 150, b = 62,  a = 120 } },
    wardrobe_lspd = { label = '옷장(구)', color = { r = 80,  g = 170, b = 255, a = 120 } },
    wardrobe_lssd = { label = '옷장(구)', color = { r = 180, g = 160, b = 90,  a = 120 } },
}
for typeKey, info in pairs(DISPLAY_ONLY_TYPES) do
    TYPE_HANDLERS[typeKey] = {
        marker = 'corona',
        color = info.color,
        onEnter = function(def, count)
            if count ~= 1 then return end

        end,
        onExit = function(def, count)
            if count > 0 then return end

        end,
    }
end

local function onEnterZone(def)
    insideIds[def.id] = true
    insideByType[def.type] = countOf(def.type) + 1
    local n = countOf(def.type)

    local h = TYPE_HANDLERS[def.type]
    if h and h.onEnter then h.onEnter(def, n) end
end

local function onExitZone(def)
    if not insideIds[def.id] then return end
    insideIds[def.id] = nil
    local n = countOf(def.type) - 1
    if n < 0 then n = 0 end
    insideByType[def.type] = n

    local h = TYPE_HANDLERS[def.type]
    if h and h.onExit then h.onExit(def, n) end
end

local function toDef(r)
    local polyPoints = nil
    if type(r.polyPoints) == 'table' then
        polyPoints = {}
        for i, pt in ipairs(r.polyPoints) do
            local x, y, z = tonumber(pt.x or pt[1]), tonumber(pt.y or pt[2]), tonumber(pt.z or pt[3])
            if x and y and z then polyPoints[#polyPoints+1] = vec3(x, y, z) end
        end
    end
    return {
        id = r.id,
        type = r.type,
        shape = r.shape,
        label = r.label,
        center = vec3(r.cx, r.cy, r.cz),
        heading = r.heading or 0.0,
        radius = r.radius,
        size = { length = r.length, width = r.width },
        height = r.height or 40.0,
        polyPoints = polyPoints,
        factionId = r.factionId,
        fishingType = r.fishingType,
        fishingRegion = r.fishingRegion,
        beaconR = r.beaconR, beaconG = r.beaconG, beaconB = r.beaconB, beaconA = r.beaconA,
        teleportX = r.teleportX, teleportY = r.teleportY, teleportZ = r.teleportZ, teleportH = r.teleportH,
    }
end

local function validDef(def)
    if def.shape == 'sphere' then
        if type(def.radius) ~= 'number' then return false, 'sphere인데 radius 없음' end
    elseif def.shape == 'box' then
        if type(def.size.length) ~= 'number' or type(def.size.width) ~= 'number' then
            return false, 'box인데 size_length/size_width 없음'
        end
    elseif def.shape == 'poly' then
        if type(def.polyPoints) ~= 'table' or #def.polyPoints < 3 then
            return false, 'poly인데 points 3개 미만'
        end
    else
        return false, '알 수 없는 shape=' .. tostring(def.shape)
    end
    return true
end

local function registerZone(def)
    local common = {
        onEnter = function() onEnterZone(def) end,
        onExit = function() onExitZone(def) end,
        debug = Config.DebugZones,
    }

    local GARAGE_ZONE = {
        garage = true,

        garage_lspd = true, garage_lssd = true,
    }

    local zone
    if def.shape == 'sphere' then
        common.coords = def.center
        local r = def.radius or 2.0
        if GARAGE_ZONE[def.type] then
            r = math.max(r, Config.garageInteractRadius or 0)
        end
        common.radius = r
        zone = lib.zones.sphere(common)
    elseif def.shape == 'box' then
        common.coords = def.center
        common.size = vec3(def.size.length, def.size.width, def.height)
        common.rotation = def.heading
        zone = lib.zones.box(common)
    else
        common.points = def.polyPoints
        common.thickness = def.height or 40.0
        zone = lib.zones.poly(common)
    end

    zoneDefs[def.id] = def
    zones[def.id] = zone

    -- 낚시 포인트/광산은 판정만 사용하고 월드 경계선/기둥을 절대 만들지 않습니다.
    -- 보호구역 등 marker가 있는 타입만 시각 경계를 구성합니다.
    local handler = TYPE_HANDLERS[def.type]
    -- V13.9.12:
    -- 잠수존은 판정/이탈 방지만 사용하고 월드 경계선은 절대 만들지 않습니다.
    if Config.boundary.enabled and def.type ~= 'afkzone' and handler and handler.marker ~= 'none' then
        local points, maxReach
        if def.shape == 'sphere' then
            points, maxReach = spherePerimeter(def)
        elseif def.shape == 'box' then
            points, maxReach = boxPerimeter(def)
        else
            points, maxReach = polyPerimeter(def)
        end

        local cullDist = maxReach + Config.boundary.fadeDistance
        boundaries[def.id] = {
            points = points,
            center = def.center,
            cullDist = cullDist,
            snapped = {},
            pending = #points,
        }

    end

end

local function registerRow(r)
    if not TYPE_HANDLERS[r.type] then

        return false
    end
    local def = toDef(r)
    local good, why = validDef(def)
    if not good then

        return false
    end
    registerZone(def)
    return true
end

local zonesLoaded = false

local cookieBuildBlips

RegisterNetEvent('cookie_safezone:client:zones', function(rows, factionMap)
    if zonesLoaded then return end
    zonesLoaded = true

    CookieFactions = factionMap or {}

    local ok, skipped = 0, 0
    local byType = {}
    for _, r in ipairs(rows or {}) do
        if registerRow(r) then
            ok = ok + 1
            byType[r.type] = (byType[r.type] or 0) + 1
        else
            skipped = skipped + 1
        end
    end

    local parts = {}
    for t, n in pairs(byType) do parts[#parts + 1] = ('%s=%d'):format(t, n) end

    cookieBuildBlips()
end)


-- 현재 플레이어가 들어가 있는 낚시터 정보를 cookie_fishing에 제공
exports('getFishingZone', function()
    for id in pairs(insideIds) do
        local def = zoneDefs[id]
        if def and def.type == 'fishing' then
            return {
                id = def.id,
                label = def.label,
                kind = (def.fishingType == 'boat') and 'boat' or 'shore',
                fishingType = def.fishingType or 'normal',
                fishingRegion = def.fishingRegion or ((def.fishingType == 'boat') and 'offshore' or 'coast'),
            }
        end
    end
    return nil
end)

-- 현재 플레이어가 들어가 있는 광산 범위를 cookie_mining에 제공
exports('getMiningZone', function()
    for id in pairs(insideIds) do
        local def = zoneDefs[id]
        if def and def.type == 'mining' then
            local pts = nil
            if type(def.polyPoints) == 'table' then
                pts = {}
                for i, pt in ipairs(def.polyPoints) do
                    pts[i] = { x = pt.x + 0.0, y = pt.y + 0.0, z = pt.z + 0.0 }
                end
            end
            return {
                id = def.id, label = def.label, shape = def.shape,
                cx = def.center.x + 0.0, cy = def.center.y + 0.0, cz = def.center.z + 0.0,
                radius = def.radius,
                length = def.size and def.size.length or nil,
                width = def.size and def.size.width or nil,
                height = def.height or 40.0,
                heading = def.heading or 0.0,
                polyPoints = pts,
            }
        end
    end
    return nil
end)

local function cookieAfkZonePayload(def)
    if not def then return nil end
    local pts = nil
    if type(def.polyPoints) == 'table' then
        pts = {}
        for i, pt in ipairs(def.polyPoints) do
            pts[i] = { x=pt.x+0.0, y=pt.y+0.0, z=pt.z+0.0 }
        end
    end
    return {
        id=def.id, label=def.label, shape=def.shape,
        cx=def.center.x+0.0, cy=def.center.y+0.0, cz=def.center.z+0.0,
        radius=def.radius,
        length=def.size and def.size.length or nil,
        width=def.size and def.size.width or nil,
        height=def.height or 40.0,
        heading=def.heading or 0.0,
        polyPoints=pts,
    }
end

exports('getCurrentAfkZone', function()
    for id in pairs(insideIds) do
        local def=zoneDefs[id]
        if def and def.type=='afkzone' then
            return cookieAfkZonePayload(def)
        end
    end
    return nil
end)

exports('getFirstAfkZone', function()
    local picked=nil
    for _,def in pairs(zoneDefs) do
        if def and def.type=='afkzone' and (not picked or tonumber(def.id)<tonumber(picked.id)) then
            picked=def
        end
    end
    return cookieAfkZonePayload(picked)
end)


local MAPMARK_ICONS = {

    { key = '경찰',    sprite = 60,  color = 3  },
    { key = '보안',    sprite = 60,  color = 5  },
    { key = '병원',    sprite = 61,  color = 1  },
    { key = '소방',    sprite = 436, color = 1  },
    { key = '은행',    sprite = 108, color = 2  },
    { key = '정비',    sprite = 446, color = 4  },
    { key = '차고',    sprite = 357, color = 3  },
    { key = '옷',      sprite = 73,  color = 4  },
}

local MAPMARK_DEFAULT = { sprite = 1, color = 0 }

local MAPMARK_MIN_RADIUS = 60.0

local function mapmarkIcon(label)
    local name = tostring(label or '')
    for i = 1, #MAPMARK_ICONS do
        if name:find(MAPMARK_ICONS[i].key, 1, true) then
            return MAPMARK_ICONS[i]
        end
    end
    return MAPMARK_DEFAULT
end

local cookieBlips = {}

cookieBuildBlips = function()

    for i = 1, #cookieBlips do
        if DoesBlipExist(cookieBlips[i]) then RemoveBlip(cookieBlips[i]) end
    end
    cookieBlips = {}

    local function keep(b)
        cookieBlips[#cookieBlips + 1] = b

        pcall(function() exports.cookie_hud:keepBlip(b) end)
    end

    for _, def in pairs(zoneDefs) do

        if def.type == 'mapmark' then

            local cfg = mapmarkIcon(def.label)

            local r = { label = def.label, radius = def.radius }
            local x, y, z = def.center.x + 0.0, def.center.y + 0.0, def.center.z + 0.0

            do
                local radius = tonumber(r.radius) or 0.0
                if radius < MAPMARK_MIN_RADIUS then radius = MAPMARK_MIN_RADIUS end

                local circle = AddBlipForRadius(x, y, z, radius + 0.0)
                SetBlipColour(circle, cfg.color)
                SetBlipAlpha(circle, 80)
                SetBlipAsShortRange(circle, false)
                keep(circle)
            end

            local blip = AddBlipForCoord(x, y, z)
            SetBlipSprite(blip, cfg.sprite)
            SetBlipColour(blip, cfg.color)
            SetBlipScale(blip, 0.75)
            SetBlipAsShortRange(blip, false)
            SetBlipDisplay(blip, 4)

            local name = (type(r.label) == 'string' and r.label ~= '' and r.label) or '표기'
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(name)
            EndTextCommandSetBlipName(blip)

            keep(blip)
        end
    end

end

function cookieRefreshBlips()
    cookieBuildBlips()
end

CreateThread(function()
    while true do
        Wait(4000)
        for i = 1, #cookieBlips do
            local b = cookieBlips[i]
            if DoesBlipExist(b) then
                pcall(function() exports.cookie_hud:keepBlip(b) end)
            end
        end
    end
end)

CreateThread(function()
    local tries = 0
    while not zonesLoaded and tries < 30 do
        TriggerServerEvent('cookie_safezone:server:requestZones')
        tries = tries + 1
        Wait(1000)
    end
    if not zonesLoaded then

    end
end)

local function removeZoneLocal(id)
    local def = zoneDefs[id]
    if not def then return nil end

    if insideIds[id] then onExitZone(def) end

    local z = zones[id]
    if z then z:remove() end

    zones[id] = nil
    zoneDefs[id] = nil
    boundaries[id] = nil
    return def
end

RegisterNetEvent('cookie_safezone:client:zoneRemoved', function(zoneId)
    local id = tonumber(zoneId)
    if not id then return end
    local def = removeZoneLocal(id)
    if def then  end
    cookieRefreshBlips()
end)

RegisterNetEvent('cookie_safezone:client:zoneAdded', function(row)
    if not row or zoneDefs[row.id] then return end
    if registerRow(row) then

    end
    cookieRefreshBlips()
end)

RegisterNetEvent('cookie_safezone:client:zoneUpdated', function(row)
    if not row then return end
    removeZoneLocal(row.id)
    if registerRow(row) then

    end
    cookieRefreshBlips()
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    insideByType = {}
    insideIds = {}
    clearEffects()

end)

local COOKIE_LSPD_GARAGE = 'cookie_lspd'
local COOKIE_PERSONAL_GARAGE = 'cookie_personal'
local cookieVehCat = nil
local function cookieVehLabel(modelName)
    if not cookieVehCat then cookieVehCat = exports.qbx_core:GetVehiclesByName() end
    local v = cookieVehCat[modelName]
    if not v then return modelName end
    return ('%s %s'):format(v.brand or '', v.name or modelName)
end

local function cookieNotify(msg, isError)
    TriggerEvent('cookie_admin:client:notify', msg, isError and true or false)
end

local function cookieAlertBottom(msg, isError)
    TriggerEvent('cookie_admin:client:notifyBottom', msg, isError and true or false)
end

local function cookieIsLeo()
    local ok, pd = pcall(function() return exports.qbx_core:GetPlayerData() end)
    if not ok or type(pd) ~= 'table' or type(pd.job) ~= 'table' then return false end
    return pd.job.type == 'leo' or pd.job.name == 'police'
end

CookieFactions = {}

local function cookieMyJob()
    local ok, pd = pcall(function() return exports.qbx_core:GetPlayerData() end)
    if not ok or type(pd) ~= 'table' or type(pd.job) ~= 'table' then return nil end
    return pd.job.name
end

local function cookieFaction(factionId)
    if not factionId then return nil end
    return CookieFactions[tostring(factionId)] or CookieFactions[factionId]
end

local function cookieInFaction(factionId)
    local f = cookieFaction(factionId)
    if not f then return false end
    return cookieMyJob() == f.jobKey
end

local function cookieFactionName(factionId)
    local f = cookieFaction(factionId)
    return f and f.name or '소속'
end

local function cookieFactionGarage(factionId)
    local f = cookieFaction(factionId)
    return f and f.garageKey or nil
end

local function cookieMyFaction()
    local job = cookieMyJob()
    if not job then return nil end
    for _, f in pairs(CookieFactions) do
        if f.jobKey == job then return f end
    end
    return nil
end

local COOKIE_GARAGE_TYPES = { garage = true, garage_lspd = true }

local function cookieAccessIndex(zoneId)
    local ids = {}
    for id, d in pairs(zoneDefs) do
        if COOKIE_GARAGE_TYPES[d.type] then ids[#ids + 1] = id end
    end
    table.sort(ids)
    for i = 1, #ids do if ids[i] == zoneId then return i end end
    return nil
end

local function cookieTakeOut(vehicleId, garageName, apIndex)
    if cache.vehicle then
        cookieNotify('차량에서 내린 뒤 출고하세요', true)
        return
    end
    local netId = lib.callback.await('qbx_garages:server:spawnVehicle', false, vehicleId, garageName, apIndex)
    if not netId then return end
    local veh = lib.waitFor(function()
        if NetworkDoesEntityExistWithNetworkId(netId) then return NetToVeh(netId) end
    end, '차량 스폰 실패', 10000)
    if not veh or veh == 0 then return end

    local ped = PlayerPedId()
    local t = 0
    while not IsPedInVehicle(ped, veh, false) and t < 12 do SetPedIntoVehicle(ped, veh, -1); Wait(100); t = t + 1 end

    SetEntityInvincible(ped, true)
    SetEntityInvincible(veh, true)
    SetEntityAlpha(veh, 150, false)
    SetEntityAlpha(ped, 150, false)
    cookieNotify('차량을 출고 했습니다!', false)
    CreateThread(function()
        Wait(3500)
        if DoesEntityExist(ped) then ResetEntityAlpha(ped); SetEntityInvincible(ped, false) end
        if DoesEntityExist(veh) then ResetEntityAlpha(veh); SetEntityInvincible(veh, false) end
    end)
end

local cookieMenuOpts = nil

local function cookieShowMenu(title, options, actionLabel, ranks)
    cookieMenuOpts = options
    local list = {}
    for i = 1, #options do
        list[i] = {
            title = options[i].title,
            description = options[i].description,
            image = options[i].image,
            grade = options[i].minGrade,
            rankName = options[i].rankName,
            locked = options[i].locked,
            submenu = options[i].submenu,
        }
    end
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'garageMenu', title = title, options = list,
        actionLabel = actionLabel, ranks = ranks,
    })
end

local function cookieCloseMenu()
    cookieMenuOpts = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'garageMenuClose' })
end

local cookieStoreCtx = nil

local function cookieShowStore(payload)
    cookieStoreCtx = payload or {}
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'storeOpen',
        shopType = cookieStoreCtx.shopType or 'convenience',
        kicker = cookieStoreCtx.kicker or 'COOKIE MART',
        title = cookieStoreCtx.title or '상점',
        subtitle = cookieStoreCtx.subtitle or '',
        items = cookieStoreCtx.items or {},
    })
end

local function cookieCloseStore()
    cookieStoreCtx = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'storeClose' })
end

RegisterNUICallback('storeBuy', function(data, cb)
    cb('ok')
    local ctx = cookieStoreCtx
    if not ctx then return end

    local qty = math.floor(tonumber(data and data.quantity) or 1)
    if qty < 1 then qty = 1 elseif qty > 20 then qty = 20 end

    if ctx.shopType == 'jobshop' then
        local itemName = tostring(data and data.itemName or '')
        if itemName == '' then return end
        TriggerServerEvent('cookie_safezone:server:buyJobShopItem', {
            itemName = itemName,
            quantity = qty,
            factionId = ctx.factionId,
            label = ctx.title,
        })
    else
        local rowId = math.floor(tonumber(data and data.rowId) or 0)
        if rowId <= 0 then return end
        TriggerServerEvent('cookie_safezone:server:buyConvenienceFood', rowId, qty)
    end
end)

RegisterNUICallback('storeClose', function(_, cb)
    cb('ok')
    cookieCloseStore()
end)

RegisterNUICallback('garagePick', function(data, cb)
    cb('ok')
    local opts = cookieMenuOpts
    local i = tonumber(data and data.index)
    local opt = opts and i and opts[i]
    if not opt then return end

    if opt.locked then
        cookieNotify(('%s 이상만 출고할 수 있습니다'):format(opt.rankName or '상위 계급'), true)
        return
    end

    -- 한정/일반 차고처럼 다음 화면으로 이동하는 항목은
    -- NUI focus를 끄지 않는다. 중간에 HUD/화면이 꺼지는 현상 방지.
    if opt.submenu then
        SendNUIMessage({
            action = 'garageMenuLoading',
            title = opt.title or '차고',
            message = '차량 목록을 불러오는 중...'
        })
        if opt.onSelect then
            -- lib.callback.await()가 내부에서 yield하므로 pcall로 감싸면
            -- FiveM/Lua 런타임에 따라 'yield across C-call boundary'류 오류가 발생할 수 있다.
            -- 하위메뉴는 별도 thread에서 직접 실행한다.
            CreateThread(function()
                opt.onSelect()
            end)
        end
        return
    end

    cookieMenuOpts = nil
    SetNuiFocus(false, false)

    if opt.onSelect then
        CreateThread(function() opt.onSelect() end)
    end
end)

RegisterNUICallback('garageClose', function(_, cb)
    cb('ok')
    cookieMenuOpts = nil
    SetNuiFocus(false, false)
end)

local function cookieOpenGarage(garageName, apIndex, label, filterMode)
    local list = lib.callback.await('qbx_garages:server:getGarageVehicles', false, garageName)

    -- 차량이 없어도 차고 UI는 항상 연다.
    if type(list) ~= 'table' then list = {} end

    if filterMode == 'limited' or filterMode == 'normal' then
        local limited = lib.callback.await('cookie_safezone:server:limitedModels', false) or {}
        local filtered = {}
        for _, v in ipairs(list) do
            local isLimited = limited[tostring(v.modelName or ''):lower()] == true
            if (filterMode == 'limited' and isLimited) or (filterMode == 'normal' and not isLimited) then
                filtered[#filtered + 1] = v
            end
        end
        list = filtered
    end

    if #list == 0 then
        cookieShowMenu(label or '차고', {}, '출고하기')
        return
    end

    table.sort(list, function(a, b) return a.modelName < b.modelName end)
    local options = {}
    for i = 1, #list do
        local v = list[i]
        options[#options + 1] = {
            model = v.modelName,
            title = cookieVehLabel(v.modelName),
            onSelect = function() cookieTakeOut(v.id, garageName, apIndex) end,
        }
    end

    local models = {}
    for i = 1, #options do models[i] = options[i].model end

    local res = lib.callback.await('cookie_safezone:server:vehCards', false, models)
    local myGrade = (type(res) == 'table' and res.myGrade) or -1
    local cards = (type(res) == 'table' and res.cards) or {}

    for i = 1, #options do
        local c = cards[options[i].model]
        if c then
            if c.label and c.label ~= '' then options[i].title = c.label end
            options[i].image = c.image
            options[i].minGrade = c.minGrade or 0
            options[i].rankName = c.rankName

            options[i].locked = (c.minGrade ~= nil) and (myGrade < c.minGrade)
        end
    end

    table.sort(options, function(a, b)
        local ga, gb = a.minGrade or 0, b.minGrade or 0
        if ga ~= gb then return ga < gb end
        return (a.title or '') < (b.title or '')
    end)

    cookieShowMenu(label or '차고', options, '출고하기',
        (type(res) == 'table' and res.ranks) or nil)
end

local function cookieParkCurrent()
    local veh = cache.vehicle
    if not veh then return end
    if GetPedInVehicleSeat(veh, -1) ~= PlayerPedId() then
        cookieNotify('운전석에서만 반납할 수 있습니다', true)
        return
    end
    local net = NetworkGetNetworkIdFromEntity(veh)

    local target, label
    if lib.callback.await('qbx_garages:server:isParkable', false, COOKIE_PERSONAL_GARAGE, net) then
        target, label = COOKIE_PERSONAL_GARAGE, '개인 차고'
    else
        local myJob = cookieMyJob()
        for _, f in pairs(CookieFactions) do
            if f.jobKey == myJob and f.garageKey then
                if lib.callback.await('qbx_garages:server:isParkable', false, f.garageKey, net) then
                    target, label = f.garageKey, (f.name .. ' 차고')
                    break
                end
            end
        end
    end
    if not target then
        cookieNotify('반납할 수 없는 차량입니다', true)
        return
    end
    for i = -1, 5 do
        local p = GetPedInVehicleSeat(veh, i)
        if p and p ~= 0 then TaskLeaveVehicle(p, veh, 0) end
    end
    SetVehicleDoorsLocked(veh, 2)
    Wait(1200)
    lib.callback.await('qbx_garages:server:parkVehicle', false, NetworkGetNetworkIdFromEntity(veh), lib.getVehicleProperties(veh), target)
    cookieNotify(('%s에 차량을 입고 했습니다'):format(label), false)
end


local pendingGeneralGarageAp = nil

local function cookieRenderGeneralGarage(catalog, apIndex)
    if type(catalog) ~= 'table' then catalog = {} end
    local options = {}

    for _, v in ipairs(catalog) do
        local model = tostring(v.model or ''):lower()
        local price = math.max(0, math.floor(tonumber(v.price) or 0))
        local desc = ''
        if v.spec and v.spec ~= '' then desc = tostring(v.spec) .. '\n' end
        desc = desc .. ('가격 %,d원'):format(price)

        options[#options + 1] = {
            model = model,
            title = v.display_name or model,
            description = desc,
            image = v.image,
            onSelect = function()
                local res = lib.callback.await('cookie_safezone:server:buyGeneralVehicle', false, model)
                if type(res) == 'table' and res.ok then
                    cookieNotify(res.message or '차량 구매 완료', false)
                    Wait(250)
                    pendingGeneralGarageAp = apIndex
                    SendNUIMessage({
                        action = 'garageMenuLoading',
                        title = '일반 차고',
                        message = '차량 목록을 새로고침하는 중...'
                    })
                    TriggerServerEvent('cookie_admin:server:requestPublicGarageCatalog')
                else
                    cookieNotify((type(res) == 'table' and res.message) or '차량 구매에 실패했습니다', true)
                end
            end,
        }
    end

    if #options == 0 then
        options[#options + 1] = {
            title = '등록된 일반 차량이 없습니다',
            description = 'F3 > 전시 관리 > 시민차량에서 차량을 등록해주세요.',
            locked = true,
            rankName = '차량 없음',
        }
    end

    cookieShowMenu('일반 차고', options, '구매')
end

RegisterNetEvent('cookie_safezone:client:generalGarageCatalog', function(catalog)
    local apIndex = pendingGeneralGarageAp
    pendingGeneralGarageAp = nil
    if not apIndex then
        cookieNotify('일반 차고 요청 정보가 만료되었습니다', true)
        cookieCloseMenu()
        return
    end
    cookieRenderGeneralGarage(catalog, apIndex)
end)

local function cookieOpenGeneralGarage(apIndex)
    pendingGeneralGarageAp = apIndex
    SendNUIMessage({
        action = 'garageMenuLoading',
        title = '일반 차고',
        message = '차량 목록을 불러오는 중...'
    })
    TriggerServerEvent('cookie_admin:server:requestPublicGarageCatalog')

    -- 서버 응답이 영원히 안 오더라도 화면이 무한 로딩으로 남지 않게 안전장치.
    CreateThread(function()
        local expected = apIndex
        Wait(5000)
        if pendingGeneralGarageAp == expected then
            pendingGeneralGarageAp = nil
            cookieNotify('cookie_admin에서 일반차고 목록 응답이 없습니다. 서버 콘솔을 확인하세요.', true)
            cookieCloseMenu()
        end
    end)
end

local function cookieGarageInteract(def)
    if GetResourceState('cookie_garage') ~= 'started' then
        TriggerEvent('cookie_admin:client:notify', 'cookie_garage가 실행 중이 아닙니다', true)
        return
    end
    TriggerEvent('cookie_garage:client:interact', def.id)
end

local function cookieMakeGarageHandler(color)
    return {
        marker = 'wall',
        color = color,
        onEnter = function(def, count)
            if count ~= 1 then return end
            CreateThread(function()
                while insideIds[def.id] do
                    local ped = PlayerPedId()
                    local wc = GetOffsetFromEntityInWorldCoords(ped, 0.6, 0.0, 0.55)
                    local onScreen, sx, sy = World3dToScreen2d(wc.x, wc.y, wc.z)
                    if onScreen then
                        local badgeText
                        if cache.vehicle then
                            badgeText = '차량 입고'
                        elseif def.garageKind == 'limited' then
                            badgeText = '한정 차고 열기'
                        elseif def.garageKind == 'faction' then
                            badgeText = cookieFactionName(def.factionId) .. ' 차고 열기'
                        else
                            badgeText = '일반 차고 열기'
                        end
                        SendNUIMessage({ action = 'garageBadge', show = true, x = sx, y = sy, text = badgeText })
                    else
                        SendNUIMessage({ action = 'garageBadge', show = false })
                    end
                    if IsControlJustReleased(0, 38) then
                        cookieGarageInteract(def)
                        Wait(350)
                    end
                    Wait(0)
                end
                SendNUIMessage({ action = 'garageBadge', show = false })
            end)
        end,
        onExit = function(def, count)
            if count > 0 then return end
            SendNUIMessage({ action = 'garageBadge', show = false })
        end,
    }
end

TYPE_HANDLERS['garage'] = cookieMakeGarageHandler({ r = 66, g = 133, b = 244, a = 130 })

TYPE_HANDLERS['garage_lspd'] = TYPE_HANDLERS['garage']

local function cookieMakeInteractHandler(color, badgeText, openEvent)
    return {
        marker = 'wall',
        color = color,
        onEnter = function(def, count)
            if count ~= 1 then return end
            CreateThread(function()
                while insideIds[def.id] do
                    local ped = PlayerPedId()
                    local wc = GetOffsetFromEntityInWorldCoords(ped, 0.6, 0.0, 0.55)
                    local onScreen, sx, sy = World3dToScreen2d(wc.x, wc.y, wc.z)
                    if onScreen then
                        SendNUIMessage({ action = 'garageBadge', show = true, x = sx, y = sy, text = badgeText })
                    else
                        SendNUIMessage({ action = 'garageBadge', show = false })
                    end
                    if IsControlJustReleased(0, 38) then
                        if def.factionId then
                            if cookieInFaction(def.factionId) then
                                TriggerEvent(openEvent)
                            else
                                cookieNotify(('%s 소속만 이용할 수 있습니다'):format(cookieFactionName(def.factionId)), true)
                            end
                        else
                            -- factionId 없음 = 공용. 누구나 이용 가능.
                            TriggerEvent(openEvent)
                        end
                        Wait(350)
                    end
                    Wait(0)
                end
                SendNUIMessage({ action = 'garageBadge', show = false })
            end)
        end,
        onExit = function(_, count)
            if count > 0 then return end
            SendNUIMessage({ action = 'garageBadge', show = false })
        end,
    }
end

RegisterNetEvent('cookie_safezone:client:afkEnterInteract', function()
    TriggerEvent('cookie_afkzone:client:manualEnter')
end)

RegisterNetEvent('cookie_safezone:client:afkLeaveInteract', function()
    TriggerEvent('cookie_afkzone:client:manualLeave')
end)

TYPE_HANDLERS['afk_enter'] = cookieMakeInteractHandler(
    { r = 90, g = 170, b = 255, a = 130 },
    '잠수존 이동', 'cookie_safezone:client:afkEnterInteract')

TYPE_HANDLERS['afk_leave'] = cookieMakeInteractHandler(
    { r = 255, g = 190, b = 70, a = 130 },
    '메인광장 이동', 'cookie_safezone:client:afkLeaveInteract')

TYPE_HANDLERS['duty'] = cookieMakeInteractHandler(
    { r = 46, g = 190, b = 120, a = 130 },
    '뱃지 착용', 'cookie_admin:client:openDuty')

TYPE_HANDLERS['armory'] = cookieMakeInteractHandler(
    { r = 200, g = 70, b = 70, a = 130 },
    '무장고 열기', 'cookie_admin:client:openArmory')

-- V13.9.0 옷장: 의상/소품 + 머리 변경을 한 곳에서 제공한다.
local wardrobeBusy = false

local function openWardrobeClothes()
    if wardrobeBusy then return end
    if GetResourceState('illenium-appearance') ~= 'started' then
        cookieNotify('의상 시스템(illenium-appearance)이 실행 중이 아닙니다', true)
        return
    end

    wardrobeBusy = true
    local conf = {
        ped = false,
        headBlend = false,
        faceFeatures = false,
        headOverlays = false,
        components = true,
        componentConfig = {
            masks = true, upperBody = true, lowerBody = true, bags = true, shoes = true,
            scarfAndChains = true, bodyArmor = true, shirts = true, decals = true, jackets = true,
        },
        props = true,
        propConfig = {
            hats = true, glasses = true, ear = true, watches = true, bracelets = true,
        },
        tattoos = false,
        enableExit = true,
        automaticFade = false,
    }

    local ok = pcall(function()
        exports['illenium-appearance']:startPlayerCustomization(function(appearance)
            if appearance then
                TriggerServerEvent('illenium-appearance:server:saveAppearance', appearance)
                cookieNotify('옷을 갈아입었습니다', false)
            end
            wardrobeBusy = false
        end, conf)
    end)

    if not ok then
        wardrobeBusy = false
        cookieNotify('옷장을 열지 못했습니다', true)
    end
end

local function openWardrobeHair()
    if wardrobeBusy then return end
    if GetResourceState('illenium-appearance') ~= 'started' then
        cookieNotify('의상 시스템(illenium-appearance)이 실행 중이 아닙니다', true)
        return
    end

    wardrobeBusy = true

    -- V13.9.1:
    -- 숫자를 직접 입력하던 임시 머리 UI를 제거하고,
    -- 의상 변경 때 사용하는 illenium-appearance 커스터마이징 화면을 그대로 사용합니다.
    -- headOverlays=true 상태에서 머리 스타일/색상/하이라이트/텍스처를
    -- 실제 캐릭터를 보면서 변경할 수 있습니다.
    local conf = {
        ped = false,
        headBlend = false,
        faceFeatures = false,
        headOverlays = true,
        components = false,
        props = false,
        tattoos = false,
        enableExit = true,
        automaticFade = false,
    }

    local ok = pcall(function()
        exports['illenium-appearance']:startPlayerCustomization(function(appearance)
            if appearance then
                TriggerServerEvent('illenium-appearance:server:saveAppearance', appearance)
                cookieNotify('머리 스타일을 변경했습니다', false)
            end
            wardrobeBusy = false
        end, conf)
    end)

    if not ok then
        wardrobeBusy = false
        cookieNotify('머리 변경 화면을 열지 못했습니다', true)
    end
end

RegisterNetEvent('cookie_safezone:client:openWardrobe', function()
    lib.registerContext({
        id = 'cookie_wardrobe_main',
        title = '옷장',
        options = {
            {
                title = '의상 / 소품 변경',
                description = '옷, 모자, 안경, 액세서리를 변경합니다.',
                icon = 'shirt',
                onSelect = openWardrobeClothes,
            },
            {
                title = '머리 변경',
                description = '머리 스타일, 색상, 하이라이트를 변경합니다.',
                icon = 'scissors',
                onSelect = openWardrobeHair,
            },
        }
    })
    lib.showContext('cookie_wardrobe_main')
end)

TYPE_HANDLERS['wardrobe'] = cookieMakeInteractHandler(
    { r = 80, g = 170, b = 255, a = 130 },
    '옷장 / 머리 변경', 'cookie_safezone:client:openWardrobe')

-- 편의점: 물건 사진 + 한국 이름 + 가격이 보이는 전용 UI.
RegisterNetEvent('cookie_safezone:client:openConvenience', function()
    TriggerServerEvent('cookie_safezone:server:requestConvenienceCatalog')
end)

RegisterNetEvent('cookie_safezone:client:openConvenienceCatalog', function(rows)
    rows = rows or {}
    if #rows == 0 then
        cookieNotify('현재 편의점에 등록된 상품이 없습니다', true)
        return
    end

    local items = {}
    for _, row in ipairs(rows) do
        items[#items + 1] = {
            rowId = tonumber(row.id) or 0,
            itemName = tostring(row.item_name or ''),
            label = tostring(row.label or row.item_name or '상품'),
            price = math.max(0, math.floor(tonumber(row.price) or 0)),
            image = tostring(row.image or ((row.item_name or 'unknown') .. '.png')),
        }
    end

    cookieShowStore({
        shopType = 'convenience',
        kicker = 'COOKIE MART',
        title = '편의점',
        subtitle = '간단하게 고르고 바로 구매하세요',
        items = items,
    })
end)

RegisterNetEvent('cookie_safezone:client:openJobShopCatalog', function(data)
    data = type(data) == 'table' and data or {}
    local rows = data.rows or {}
    if #rows == 0 then
        cookieNotify('현재 판매 가능한 직업 물품이 없습니다', true)
        return
    end

    local items = {}
    for _, row in ipairs(rows) do
        items[#items + 1] = {
            itemName = tostring(row.item_name or ''),
            label = tostring(row.label or row.item_name or '상품'),
            price = math.max(0, math.floor(tonumber(row.price) or 0)),
            image = tostring(row.image or ((row.item_name or 'unknown') .. '.png')),
        }
    end

    cookieShowStore({
        shopType = 'jobshop',
        kicker = 'COOKIE JOB SHOP',
        title = tostring(data.title or '직업 물품 상점'),
        subtitle = tostring(data.subtitle or '직업/팩션 판매 물품'),
        factionId = tonumber(data.factionId),
        items = items,
    })
end)

TYPE_HANDLERS['convenience'] = cookieMakeInteractHandler(
    { r = 72, g = 190, b = 110, a = 130 },
    '편의점 이용', 'cookie_safezone:client:openConvenience')

TYPE_HANDLERS['jobshop'] = {
    marker = 'wall',
    color = { r = 100, g = 155, b = 255, a = 135 },
    onEnter = function(def, count)
        if count ~= 1 then return end
        CreateThread(function()
            while insideIds[def.id] do
                local ped = PlayerPedId()
                local wc = GetOffsetFromEntityInWorldCoords(ped, 0.6, 0.0, 0.55)
                local onScreen, sx, sy = World3dToScreen2d(wc.x, wc.y, wc.z)
                if onScreen then
                    SendNUIMessage({ action = 'garageBadge', show = true, x = sx, y = sy, text = '직업 물품 상점' })
                else
                    SendNUIMessage({ action = 'garageBadge', show = false })
                end

                if IsControlJustReleased(0, 38) then
                    TriggerServerEvent('cookie_safezone:server:requestJobShopCatalog', {
                        factionId = def.factionId,
                        label = def.label,
                    })
                    Wait(350)
                end
                Wait(0)
            end
            SendNUIMessage({ action = 'garageBadge', show = false })
        end)
    end,
    onExit = function(_, count)
        if count > 0 then return end
        SendNUIMessage({ action = 'garageBadge', show = false })
    end,
}

TYPE_HANDLERS['tuningshop'] = cookieMakeInteractHandler(
    { r = 215, g = 168, b = 90, a = 135 },
    '튜닝샵 이용', 'cookie_tuningshop:client:open')

RegisterNetEvent('cookie_safezone:client:openKuji', function()
    if GetResourceState('cookie_kuji') ~= 'started' then
        cookieNotify('cookie_kuji가 실행 중이 아닙니다', true)
        return
    end
    TriggerServerEvent('cookie_kuji:server:requestOpen')
end)

TYPE_HANDLERS['kuji'] = cookieMakeInteractHandler(
    { r = 255, g = 190, b = 45, a = 130 },
    '월간 쿠지 이용', 'cookie_safezone:client:openKuji')

-- 뉴비 발급 비콘: 진행도/교육 없이 누른 기능만 즉시 발급한다.
RegisterNetEvent('cookie_safezone:client:issueNewbieJumin', function()
    TriggerServerEvent('cookie_safezone:server:issueNewbieJumin')
end)

RegisterNetEvent('cookie_safezone:client:issueNewbiePhone', function()
    TriggerServerEvent('cookie_safezone:server:issueNewbiePhone')
end)

RegisterNetEvent('cookie_safezone:client:issueNewbieLicense', function()
    TriggerServerEvent('cookie_safezone:server:issueNewbieLicense')
end)

TYPE_HANDLERS['newbie_jumin'] = cookieMakeInteractHandler(
    { r = 255, g = 170, b = 55, a = 130 },
    '주민번호 발급', 'cookie_safezone:client:issueNewbieJumin')

TYPE_HANDLERS['newbie_phone'] = cookieMakeInteractHandler(
    { r = 80, g = 190, b = 125, a = 130 },
    '전화번호 발급', 'cookie_safezone:client:issueNewbiePhone')

TYPE_HANDLERS['newbie_license'] = cookieMakeInteractHandler(
    { r = 70, g = 145, b = 235, a = 130 },
    '운전면허 발급', 'cookie_safezone:client:issueNewbieLicense')

RegisterNetEvent('cookie_safezone:client:openNewbieVerify', function()
    if GetResourceState('cookie_newbie') ~= 'started' then
        cookieNotify('뉴비 인증 시스템이 실행 중이 아닙니다', true)
        return
    end
    TriggerEvent('cookie_newbie:client:open')
end)

TYPE_HANDLERS['newbie_verify'] = cookieMakeInteractHandler(
    { r = 255, g = 190, b = 45, a = 145 },
    '뉴비 인증', 'cookie_safezone:client:openNewbieVerify')

local teleportBusy = false

local function cookieUseTeleport(def)
    if teleportBusy then return end

    local x, y, z = tonumber(def.teleportX), tonumber(def.teleportY), tonumber(def.teleportZ)
    if not x or not y or not z then
        cookieNotify('이 텔레포트 비콘은 목적지 좌표가 설정되지 않았습니다', true)
        return
    end

    teleportBusy = true
    local ped = PlayerPedId()

    DoScreenFadeOut(300)
    local fadeUntil = GetGameTimer() + 1000
    while not IsScreenFadedOut() and GetGameTimer() < fadeUntil do Wait(0) end

    FreezeEntityPosition(ped, true)
    RequestCollisionAtCoord(x, y, z)
    SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
    SetEntityHeading(ped, tonumber(def.teleportH) or 0.0)
    RequestCollisionAtCoord(x, y, z)

    local collisionUntil = GetGameTimer() + 3000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < collisionUntil do
        RequestCollisionAtCoord(x, y, z)
        Wait(50)
    end

    FreezeEntityPosition(ped, false)
    DoScreenFadeIn(300)
    teleportBusy = false
end

TYPE_HANDLERS['teleport'] = {
    marker = 'wall',
    color = { r = 165, g = 105, b = 235, a = 130 },
    onEnter = function(def, count)
        if count ~= 1 then return end
        CreateThread(function()
            while insideIds[def.id] do
                local ped = PlayerPedId()
                local wc = GetOffsetFromEntityInWorldCoords(ped, 0.6, 0.0, 0.55)
                local onScreen, sx, sy = World3dToScreen2d(wc.x, wc.y, wc.z)
                if onScreen then
                    SendNUIMessage({ action = 'garageBadge', show = true, x = sx, y = sy, text = '이동하기' })
                else
                    SendNUIMessage({ action = 'garageBadge', show = false })
                end

                if IsControlJustReleased(0, 38) then
                    cookieUseTeleport(def)
                    Wait(500)
                end
                Wait(0)
            end
            SendNUIMessage({ action = 'garageBadge', show = false })
        end)
    end,
    onExit = function(_, count)
        if count > 0 then return end
        SendNUIMessage({ action = 'garageBadge', show = false })
    end,
}


TYPE_HANDLERS['duty_lspd']   = TYPE_HANDLERS['duty']
TYPE_HANDLERS['armory_lspd'] = TYPE_HANDLERS['armory']

-- ATM: 공용 비콘. 현금 <-> 계좌 이동만 제공한다.
-- V4: callback.await를 완전히 제거하고 NetEvent 요청/응답으로 처리한다.
-- 잔액이 0원이거나 서버 응답이 늦어도 UI 자체는 항상 즉시 열린다.
local atmBusy = false
local atmRequestSerial = 0

local function atmFormatMoney(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local rev = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
    return rev:gsub('^,', '')
end

local function atmLocalBalances()
    local cash, bank = 0, 0
    local ok, pd = pcall(function()
        return exports.qbx_core:GetPlayerData()
    end)
    if ok and type(pd) == 'table' and type(pd.money) == 'table' then
        cash = math.max(0, math.floor(tonumber(pd.money.cash) or 0))
        bank = math.max(0, math.floor(tonumber(pd.money.bank) or 0))
    end
    return { cash = cash, bank = bank }
end

local cookieShowAtmMenu

local function atmTransfer(direction)
    if atmBusy then
        cookieNotify('ATM 거래 처리 중입니다. 잠시 후 다시 시도하세요.', true)
        return
    end

    local isDeposit = direction == 'deposit'
    local input = lib.inputDialog(isDeposit and 'ATM · 입금' or 'ATM · 출금', {
        {
            type = 'number',
            label = isDeposit and '입금할 금액' or '출금할 금액',
            description = isDeposit and '현금 → 계좌' or '계좌 → 현금',
            icon = 'won-sign',
            min = 1,
            max = 2000000000,
            required = true,
        }
    })
    if not input then return end

    local amount = math.floor(tonumber(input[1]) or 0)
    if amount < 1 then
        cookieNotify('1원 이상 입력하세요', true)
        return
    end

    atmBusy = true
    atmRequestSerial = atmRequestSerial + 1
    local serial = atmRequestSerial
    TriggerServerEvent('cookie_safezone:server:atmTransfer', direction, amount)

    -- 어떤 이유로 서버 응답 이벤트가 사라져도 ATM이 영원히 잠기지 않도록 안전 해제.
    SetTimeout(8000, function()
        if atmBusy and serial == atmRequestSerial then
            atmBusy = false
            cookieNotify('ATM 응답이 지연되고 있습니다. 다시 시도해주세요.', true)
            TriggerServerEvent('cookie_safezone:server:requestAtmBalance')
        end
    end)
end

cookieShowAtmMenu = function(bal)
    bal = type(bal) == 'table' and bal or atmLocalBalances()
    bal.cash = math.max(0, math.floor(tonumber(bal.cash) or 0))
    bal.bank = math.max(0, math.floor(tonumber(bal.bank) or 0))

    lib.registerContext({
        id = 'cookie_atm_menu',
        title = 'ATM',
        options = {
            {
                title = ('현금  %s원'):format(atmFormatMoney(bal.cash)),
                description = '현재 보유 현금',
                icon = 'money-bill-wave',
                disabled = true,
            },
            {
                title = ('계좌  %s원'):format(atmFormatMoney(bal.bank)),
                description = '현재 계좌 잔액',
                icon = 'building-columns',
                disabled = true,
            },
            {
                title = '입금',
                description = '현금을 계좌로 이동합니다',
                icon = 'arrow-right-to-bracket',
                onSelect = function() atmTransfer('deposit') end,
            },
            {
                title = '출금',
                description = '계좌에서 현금으로 이동합니다',
                icon = 'arrow-right-from-bracket',
                onSelect = function() atmTransfer('withdraw') end,
            },
        },
    })
    lib.showContext('cookie_atm_menu')
end

RegisterNetEvent('cookie_safezone:client:atmBalance', function(bal)
    -- 잔액 동기화 응답. 메뉴가 이미 열려 있어도 새 값으로 다시 그린다.
    cookieShowAtmMenu(bal)
end)

RegisterNetEvent('cookie_safezone:client:atmTransferResult', function(result)
    atmBusy = false
    atmRequestSerial = atmRequestSerial + 1
    result = type(result) == 'table' and result or {}
    cookieNotify(result.message or (result.ok and '거래가 완료되었습니다' or '거래에 실패했습니다'), not result.ok)
    cookieShowAtmMenu({
        cash = math.max(0, math.floor(tonumber(result.cash) or 0)),
        bank = math.max(0, math.floor(tonumber(result.bank) or 0)),
    })
end)

local function cookieOpenAtm()
    -- 0원 / 0원이어도 즉시 UI 표시 후 서버의 실제 잔액으로 갱신한다.
    cookieShowAtmMenu(atmLocalBalances())
    TriggerServerEvent('cookie_safezone:server:requestAtmBalance')
end

RegisterNetEvent('cookie_safezone:client:openAtm', cookieOpenAtm)

TYPE_HANDLERS['atm'] = cookieMakeInteractHandler(
    { r = 80, g = 185, b = 120, a = 130 },
    'ATM 이용', 'cookie_safezone:client:openAtm')

print('^2[cookie_safezone]^7 WARDROBE HAIR V13.9.0 ready')

print('^2[cookie_safezone]^7 AFKZONE SHAPE + PORTAL V13.9.2 ready')

print('^2[cookie_safezone]^7 AFK BOUNDARY HIDDEN V13.9.12 ready')
