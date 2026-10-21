local Locations = {}
local Current = nil
local DispatchBlips = {}
local PoliceActive = {}
local ActiveBoundaries = {}

local function notify(message, isError)
    TriggerEvent('cookie_admin:client:notify', message, isError == true)
end

local function drawText3D(coords, text)
    local onScreen, x, y = World3dToScreen2d(coords.x, coords.y, coords.z)
    if not onScreen then return end

    SetTextScale(0.30, 0.30)
    SetTextFont(0)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 225)
    SetTextCentre(true)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

local function byId(id)
    id = tonumber(id)
    for _, loc in ipairs(Locations) do
        if tonumber(loc.id) == id then return loc end
    end
end

local function isFirearmReady()
    if not Config.RequireFirearm then return true end
    return IsPedArmed(PlayerPedId(), 4)
end

local AllowedMeleeHashes = {}

CreateThread(function()
    for _, weaponName in ipairs((Config.EmptyHouse and Config.EmptyHouse.allowedMeleeWeapons) or {}) do
        AllowedMeleeHashes[joaat(weaponName)] = true
    end
end)

local function isMeleeReady()
    local ped = PlayerPedId()
    local weapon = GetSelectedPedWeapon(ped)
    if not weapon or weapon == 0 or weapon == `WEAPON_UNARMED` then return false end
    return AllowedMeleeHashes[weapon] == true
end

local function hasFirearmEquipped()
    local ped = PlayerPedId()
    local weapon = GetSelectedPedWeapon(ped)
    if not weapon or weapon == 0 or weapon == `WEAPON_UNARMED` then return false end

    -- 허용 근접무기가 아닌 무장을 빈집에서는 모두 차단.
    return AllowedMeleeHashes[weapon] ~= true
end

RegisterNetEvent('cookie_robbery:client:setLocations', function(rows)
    Locations = type(rows) == 'table' and rows or {}

    print(('[cookie_robbery] client locations received: %d'):format(#Locations))
end)

RegisterNetEvent('cookie_robbery:client:crewStarted', function(data)
    Current = data or {}
    Current.phase = 'threat'

    -- 서버가 시작을 승인한 뒤 시작자에게만 위협 진행바 표시.
    if tonumber(Current.starter) == GetPlayerServerId(PlayerId()) then
        CreateThread(function()
            local isEmptyHouse = Current.type == 'emptyhouse'
            local isBank = Current.type == 'bank'
            local ok = lib.progressCircle({
                duration = math.max(1, tonumber(Current.threatSeconds) or 8) * 1000,
                position = 'bottom',
                label = isEmptyHouse
                    and '빈집 진입 지점을 파손하는 중...'
                    or (isBank and '대형 RP 진입 절차를 진행하는 중...' or '소형 RP 시작 절차를 진행하는 중...'),
                useWhileDead = false,
                canCancel = true,
                disable = {
                    car = true,
                    move = false,
                    combat = false,
                }
            })

            if ok and Current and Current.phase == 'threat' then
                TriggerServerEvent('cookie_robbery:server:threatFinished', Current.id)
            end
        end)
    end
end)

RegisterNetEvent('cookie_robbery:client:phase', function(data)
    if not data then return end
    Current = Current or {}
    for k, v in pairs(data) do Current[k] = v end
end)

RegisterNetEvent('cookie_robbery:client:status', function(message, warning)
    notify(message or '', warning == true)
end)

RegisterNetEvent('cookie_robbery:client:lootStarted', function(data)
    if not Current or tonumber(Current.id) ~= tonumber(data and data.id) then return end
    if tonumber(data.looter) ~= GetPlayerServerId(PlayerId()) then
        notify(('%s님이 금고/계산대를 털고 있습니다. 엄호하세요.'):format(data.looterName or '공범'), false)
        return
    end

    CreateThread(function()
        local ok = lib.progressCircle({
            duration = math.max(1, tonumber(data.seconds) or 30) * 1000,
            position = 'bottom',
            label = '현금과 물품을 챙기는 중...',
            useWhileDead = false,
            canCancel = true,
            disable = {
                car = true,
                move = true,
                combat = true,
            },
            anim = {
                dict = 'anim@heists@ornate_bank@grab_cash',
                clip = 'grab',
            }
        })

        if ok then
            TriggerServerEvent('cookie_robbery:server:lootFinished', Current.id)
        else
            TriggerServerEvent('cookie_robbery:server:lootCancelled', Current.id)
        end
    end)
end)


RegisterNetEvent('cookie_robbery:client:bankLootStarted', function(data)
    if not Current or Current.type ~= 'bank' or tonumber(Current.id) ~= tonumber(data and data.id) then
        return
    end

    if tonumber(data.looter) ~= GetPlayerServerId(PlayerId()) then
        notify(('%s님이 %s을(를) 확보 중입니다. 엄호하세요.'):format(
            data.looterName or '공범',
            data.label or '대형 RP 전리품'
        ), false)
        return
    end

    CreateThread(function()
        local ok = lib.progressCircle({
            duration = math.max(1, tonumber(data.seconds) or 10) * 1000,
            position = 'bottom',
            label = ('%s 확보 중...'):format(data.label or data.itemLabel or '대형 RP 전리품'),
            useWhileDead = false,
            canCancel = true,
            disable = {
                car = true,
                move = true,
                combat = true,
            },
            anim = {
                dict = 'anim@heists@ornate_bank@grab_cash',
                clip = 'grab',
            }
        })

        if ok and Current and Current.phase == 'bank_loot' then
            TriggerServerEvent(
                'cookie_robbery:server:finishBankLootPoint',
                Current.id,
                data.pointId
            )
        else
            TriggerServerEvent('cookie_robbery:server:cancelBankLootPoint', Current and Current.id)
        end
    end)
end)

RegisterNetEvent('cookie_robbery:client:bankLootProgress', function(data)
    if not Current or Current.type ~= 'bank' or tonumber(Current.id) ~= tonumber(data and data.id) then
        return
    end

    Current.bankLootTotal = tonumber(data.total) or Current.bankLootTotal or 0
    Current.requiredLootAmount = tonumber(data.required) or Current.requiredLootAmount or 0
    Current.bankLootedPoints = Current.bankLootedPoints or {}
    Current.bankLootedPoints[tonumber(data.pointId)] = true

    notify(
        ('%s x%d 확보 · 대형 RP 전리품 %d / %d'):format(
            data.itemLabel or '전리품',
            tonumber(data.amount) or 0,
            Current.bankLootTotal or 0,
            Current.requiredLootAmount or 0
        ),
        false
    )
end)

RegisterNetEvent('cookie_robbery:client:ended', function(data)
    if Current and tonumber(Current.id) == tonumber(data and data.id) then
        Current = nil
    end
    notify((data and data.message) or '강도가 종료되었습니다.', not (data and data.success))
end)

RegisterNetEvent('cookie_robbery:client:dispatch', function(data)
    if not data or not data.coords then return end

    local id = tonumber(data.robberyId)
    if id then
        PoliceActive[id] = data
    end

    -- 경찰은 '연락'만 받는다. 수락/거절/신고 접수 기능은 존재하지 않는다.
    notify(('🚨 %s\n%s'):format(
        data.label or '강도 연락',
        data.text or '통무방으로 이동 후 현장 대응 바랍니다.'
    ), true)

    local c = data.coords
    local blip = AddBlipForCoord(c.x + 0.0, c.y + 0.0, c.z + 0.0)
    SetBlipSprite(blip, Config.DispatchBlipSprite)
    SetBlipColour(blip, Config.DispatchBlipColor)
    SetBlipScale(blip, Config.DispatchBlipScale)
    SetBlipAsShortRange(blip, false)

    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(('강도 신고 - %s'):format(data.label or '편의점'))
    EndTextCommandSetBlipName(blip)

    DispatchBlips[tonumber(data.robberyId)] = blip

    CreateThread(function()
        Wait((tonumber(data.seconds) or Config.DispatchBlipSeconds) * 1000)
        local id = tonumber(data.robberyId)
        if DispatchBlips[id] and DoesBlipExist(DispatchBlips[id]) then
            RemoveBlip(DispatchBlips[id])
        end
        DispatchBlips[id] = nil
    end)
end)

RegisterNetEvent('cookie_robbery:client:dispatchEnd', function(id)
    id = tonumber(id)
    if id and DispatchBlips[id] and DoesBlipExist(DispatchBlips[id]) then
        RemoveBlip(DispatchBlips[id])
    end
    if id then
        DispatchBlips[id] = nil
        PoliceActive[id] = nil
    end
end)



RegisterNetEvent('cookie_robbery:client:boundaryStart', function(data)
    if not data then return end
    local id = tonumber(data.robberyId)
    if not id then return end
    ActiveBoundaries[id] = {
        x = tonumber(data.x) or 0.0,
        y = tonumber(data.y) or 0.0,
        z = tonumber(data.z) or 0.0,
        radius = math.max(5.0, tonumber(data.radius) or 45.0),
        boundaryMode = tostring(data.boundaryMode or 'circle'),
        boundaryPoints = type(data.boundaryPoints) == 'table' and data.boundaryPoints or {},
        label = tostring(data.label or '소형 RP'),
    }
end)

RegisterNetEvent('cookie_robbery:client:boundaryEnd', function(id)
    ActiveBoundaries[tonumber(id)] = nil
end)

-- COOKIE RP V1.6 범위 렌더링: 원형/다각형 + 반투명 빨간 벽.
local function boundaryVisual()
    local c=Config.BoundaryVisual or {}
    return {
        style=tostring(c.style or 'wall'),
        wallHeight=math.max(0.06,tonumber(c.wallHeight) or 0.22),
        groundOffset=math.max(0.0,math.min(0.15,tonumber(c.groundOffset) or 0.015)),
        idleAlpha=math.max(10,math.min(220,math.floor(tonumber(c.idleAlpha) or 62))),
        activeAlpha=math.max(20,math.min(230,math.floor(tonumber(c.activeAlpha) or 125))),
        lineAlpha=math.max(50,math.min(255,math.floor(tonumber(c.lineAlpha) or 235))),
        showVertices=c.showVertices ~= false,
    }
end

local function groundZAt(x,y,zHint)
    local startZ=(tonumber(zHint) or 0.0)+4.0
    local ok,gz=GetGroundZFor_3dCoord(x+0.0,y+0.0,startZ,false)
    if ok then return gz end
    return tonumber(zHint) or 0.0
end

local function drawWallSegment(a,b,alpha,height)
    local ax,ay,az=tonumber(a.x),tonumber(a.y),tonumber(a.z)
    local bx,by,bz=tonumber(b.x),tonumber(b.y),tonumber(b.z)
    if not ax or not ay or not az or not bx or not by or not bz then return end

    local v=boundaryVisual()
    local off=v.groundOffset or 0.015
    local ag=groundZAt(ax,ay,az)
    local bg=groundZAt(bx,by,bz)
    local a0,b0=ag+off,bg+off
    local a1,b1=a0+height,b0+height

    DrawPoly(ax,ay,a0,bx,by,b0,bx,by,b1,255,32,32,alpha)
    DrawPoly(ax,ay,a0,bx,by,b1,ax,ay,a1,255,32,32,alpha)
    DrawPoly(bx,by,b0,ax,ay,a0,ax,ay,a1,255,32,32,alpha)
    DrawPoly(bx,by,b0,ax,ay,a1,bx,by,b1,255,32,32,alpha)

    local edgeAlpha=math.min(255,alpha+110)
    DrawLine(ax,ay,a0,bx,by,b0,255,52,52,edgeAlpha)
    DrawLine(ax,ay,a1,bx,by,b1,255,82,82,edgeAlpha)
end

local function drawLineSegment(a,b,alpha)
    DrawLine(
        tonumber(a.x) or 0.0,tonumber(a.y) or 0.0,(tonumber(a.z) or 0.0)+0.08,
        tonumber(b.x) or 0.0,tonumber(b.y) or 0.0,(tonumber(b.z) or 0.0)+0.08,
        255,35,35,alpha
    )
end

local function circlePoints(zone)
    local segments=math.max(24,math.floor((Config.ConvenienceBoundary and Config.ConvenienceBoundary.segments) or 72))
    local radius=math.max(5.0,tonumber(zone.radius or zone.combatRadius) or 45.0)
    local z=tonumber(zone.z) or 0.0
    local points={}
    for i=0,segments-1 do
        local a=(i/segments)*math.pi*2.0
        points[#points+1]={x=zone.x+math.cos(a)*radius,y=zone.y+math.sin(a)*radius,z=z}
    end
    return points
end

local function validPolygon(points)
    return type(points)=='table' and #points>=3
end

local function drawBoundaryShape(zone,active)
    local v=boundaryVisual()
    local polygon=tostring(zone.boundaryMode or 'circle')=='polygon' and validPolygon(zone.boundaryPoints)
    local points=polygon and zone.boundaryPoints or circlePoints(zone)
    local alpha=active and v.activeAlpha or v.idleAlpha

    for i=1,#points do
        local a=points[i]
        local b=points[(i % #points)+1]
        if v.style=='line' then
            drawLineSegment(a,b,v.lineAlpha)
        else
            drawWallSegment(a,b,alpha,v.wallHeight)
        end
    end

    if polygon and v.showVertices then
        for _,p in ipairs(points) do
            local px,py,pz=tonumber(p.x) or 0.0,tonumber(p.y) or 0.0,tonumber(p.z) or 0.0
            local pg=groundZAt(px,py,pz)
            DrawMarker(28,
                px,py,pg+0.035,
                0.0,0.0,0.0,0.0,0.0,0.0,
                0.11,0.11,0.11,255,70,70,active and 230 or 175,
                false,false,2,false,nil,nil,false)
        end
    end
end

CreateThread(function()
    while true do
        local sleep=700
        local myPos=GetEntityCoords(PlayerPedId())
        local drawDistance=(Config.ConvenienceBoundary and Config.ConvenienceBoundary.drawDistance) or 180.0

        if Config.AlwaysShowConfiguredBoundaries ~= false then
            for _,loc in ipairs(Locations) do
                local center=vec3(loc.x,loc.y,loc.z)
                if #(myPos-center)<=drawDistance then
                    sleep=0
                    if not ActiveBoundaries[tonumber(loc.id)] then
                        drawBoundaryShape({
                            x=loc.x,y=loc.y,z=loc.z,
                            radius=loc.combatRadius or 45.0,
                            boundaryMode=loc.boundaryMode or 'circle',
                            boundaryPoints=loc.boundaryPoints or {},
                        },false)
                    end
                end
            end
        end

        for _,zone in pairs(ActiveBoundaries) do
            local center=vec3(zone.x,zone.y,zone.z)
            if #(myPos-center)<=drawDistance then
                sleep=0
                drawBoundaryShape(zone,true)
            end
        end
        Wait(sleep)
    end
end)

local function openPoliceResultMenu(loc, alert)
    local id = tonumber(loc.id)
    if not id then return end

    local ctxId = ('cookie_robbery_police_result_%s'):format(id)

    local isBank = loc.type == 'bank'

    lib.registerContext({
        id = ctxId,
        title = ('%s · 교전 결과'):format(alert and alert.label or loc.label or '강도'),
        options = {
            {
                title = '경찰 측 승리',
                description = isBank
                    and '대형 RP팀 제압 완료. 확보 중인 전리품도 모두 무효 처리합니다.'
                    or '강도팀 제압 완료. 강도를 실패 처리합니다.',
                icon = 'shield-halved',
                onSelect = function()
                    TriggerServerEvent('cookie_robbery:server:policeResult', id, 'police_win')
                end
            },
            {
                title = '경찰 측 패배',
                description = isBank
                    and '요구 전리품 확보 후 경찰 패배를 확정하면 대형 RP가 최종 성공합니다.'
                    or '경찰 측 패배를 확정하고 강도팀의 금고 털기를 허용합니다.',
                icon = 'skull-crossbones',
                onSelect = function()
                    TriggerServerEvent('cookie_robbery:server:policeResult', id, 'police_lose')
                end
            }
        }
    })

    lib.showContext(ctxId)
end

CreateThread(function()
    Wait(1500)
    TriggerServerEvent('cookie_robbery:server:requestLocations')

    while true do
        local sleep = 850
        local ped = PlayerPedId()
        local pos = GetEntityCoords(ped)

        for _, loc in ipairs(Locations) do
            local c = vec3(loc.x + 0.0, loc.y + 0.0, loc.z + 0.0)
            local d = #(pos - c)

            if d < 18.0 then
                sleep = 0

                -- 점원 NPC 대신 실제 쿠키서버식 비콘으로 상호작용.
                DrawMarker(
                    1,
                    loc.x + 0.0, loc.y + 0.0, loc.z - 1.02,
                    0.0, 0.0, 0.0,
                    0.0, 0.0, 0.0,
                    0.75, 0.75, 0.22,
                    255, 202, 74, 135,
                    false, false, 2, false, nil, nil, false
                )

                local policeAlert = PoliceActive[tonumber(loc.id)]
                local interactDistance = tonumber(loc.interactDistance) or 2.5

                if d <= interactDistance then
                    -- 신고 연락을 받은 경찰/보안국은 수락 UI 없이 현장 비콘에서 결과만 기록.
                    if policeAlert then
                        drawText3D(
                            c + vec3(0.0, 0.0, 0.35),
                            loc.type == 'emptyhouse'
                                and '[~y~E~s~] 빈집 침입 비콘 · 경찰 대응 결과 기록'
                                or (loc.type == 'bank'
                                    and '[~y~E~s~] 대형 RP 결과 비콘 · 경찰 교전 결과 기록'
                                    or '[~y~E~s~] 소형 RP 비콘 · 경찰 교전 결과 기록')
                        )

                        if IsControlJustReleased(0, Config.InteractControl) then
                            openPoliceResultMenu(loc, policeAlert)
                            Wait(500)
                        end

                    elseif Current and tonumber(Current.id) == tonumber(loc.id) then
                        if Current.phase == 'combat' then
                            drawText3D(
                                c + vec3(0.0, 0.0, 0.35),
                                Current.type == 'emptyhouse'
                                    and '~y~빈집 침입 비콘~s~ · 경찰 대응 진행 중'
                                    or (Current.type == 'bank'
                                        and '~r~대형 RP 최종 전멸전~s~ · 경찰 결과 확정 대기'
                                        or '~y~소형 RP 비콘~s~ · 전멸전 진행 중')
                            )
                        elseif Current.phase == 'bank_loot' then
                            drawText3D(
                                c + vec3(0.0, 0.0, 0.35),
                                ('~y~대형 RP~s~ · 전리품 %d / %d 확보 중'):format(
                                    tonumber(Current.bankLootTotal) or 0,
                                    tonumber(Current.requiredLootAmount) or 0
                                )
                            )
                        elseif Current.phase == 'loot' then
                            drawText3D(
                                c + vec3(0.0, 0.0, 0.35),
                                Current.type == 'emptyhouse'
                                    and '[~y~E~s~] 빈집 침입 비콘 · 집 내부 물품 털기'
                                    or '[~y~E~s~] 소형 RP 비콘 · 전리품 회수'
                            )
                            if IsControlJustReleased(0, Config.InteractControl) then
                                TriggerServerEvent('cookie_robbery:server:beginLoot', loc.id)
                                Wait(500)
                            end
                        end

                    elseif not Current then
                        if loc.type == 'emptyhouse' then
                            if hasFirearmEquipped() then
                                drawText3D(
                                    c + vec3(0.0, 0.0, 0.35),
                                    '~r~빈집 침입 비콘~s~ · 총기는 사용할 수 없습니다'
                                )
                            elseif isMeleeReady() then
                                drawText3D(
                                    c + vec3(0.0, 0.0, 0.35),
                                    '[~y~E~s~] 빈집 침입 비콘 · ' .. tostring(loc.label or '빈집') .. ' 털기'
                                )
                            else
                                drawText3D(
                                    c + vec3(0.0, 0.0, 0.35),
                                    '~y~빈집 침입 비콘~s~ · 근접무기를 꺼내야 합니다'
                                )
                            end
                        elseif loc.type == 'bank' then
                            if isFirearmReady() then
                                drawText3D(
                                    c + vec3(0.0, 0.0, 0.35),
                                    '[~y~E~s~] 대형 RP 비콘 · ' .. tostring(loc.label or '은행') .. ' 대형 강도 시작'
                                )
                            else
                                drawText3D(
                                    c + vec3(0.0, 0.0, 0.35),
                                    '~y~대형 RP 비콘~s~ · 총기를 꺼내야 시작할 수 있습니다'
                                )
                            end
                        else
                            if isFirearmReady() then
                                drawText3D(
                                    c + vec3(0.0, 0.0, 0.35),
                                    '[~y~E~s~] 소형 RP 비콘 · ' .. tostring(loc.label or '소형 RP') .. ' 시작'
                                )
                            else
                                drawText3D(
                                    c + vec3(0.0, 0.0, 0.35),
                                    '~y~소형 RP 비콘~s~ · 총기를 꺼내야 시작할 수 있습니다'
                                )
                            end
                        end

                        if IsControlJustReleased(0, Config.InteractControl) then
                            if loc.type == 'emptyhouse' then
                                if hasFirearmEquipped() then
                                    notify('빈집 강도는 총기를 사용할 수 없습니다. 근접무기만 사용하세요.', true)
                                elseif not isMeleeReady() then
                                    notify('근접무기를 든 상태에서 빈집 침입 비콘을 사용하세요.', true)
                                else
                                    TriggerServerEvent('cookie_robbery:server:beginThreat', loc.id)
                                    Wait(500)
                                end
                            elseif loc.type == 'bank' then
                                if not isFirearmReady() then
                                    notify('총기를 꺼낸 상태에서 대형 RP 비콘을 사용하세요.', true)
                                else
                                    TriggerServerEvent('cookie_robbery:server:beginThreat', loc.id)
                                    Wait(500)
                                end
                            else
                                if not isFirearmReady() then
                                    notify('총기를 꺼낸 상태에서 소형 RP 비콘을 사용하세요.', true)
                                else
                                    TriggerServerEvent('cookie_robbery:server:beginThreat', loc.id)
                                    Wait(500)
                                end
                            end
                        end
                    end
                end
            end
        end


        -- 은행 강도팀에게만 전리품 비콘을 보여준다.
        if Current and Current.type == 'bank' and Current.phase == 'bank_loot' then
            Current.bankLootedPoints = Current.bankLootedPoints or {}

            for _, point in ipairs(Current.bankLootPoints or {}) do
                local pointId = tonumber(point.id)
                if pointId and not Current.bankLootedPoints[pointId] then
                    local pc = vec3(
                        tonumber(point.x) or 0.0,
                        tonumber(point.y) or 0.0,
                        tonumber(point.z) or 0.0
                    )
                    local pd = #(pos - pc)

                    if pd < 20.0 then
                        sleep = 0
                        DrawMarker(
                            1,
                            pc.x, pc.y, pc.z - 1.02,
                            0.0, 0.0, 0.0,
                            0.0, 0.0, 0.0,
                            0.62, 0.62, 0.18,
                            255, 195, 48, 155,
                            false, false, 2, false, nil, nil, false
                        )

                        if pd <= 2.2 then
                            drawText3D(
                                pc + vec3(0.0, 0.0, 0.34),
                                ('[~y~E~s~] %s · %s 확보'):format(
                                    tostring(point.label or '대형 RP 전리품'),
                                    tostring(point.itemLabel or point.item or '전리품')
                                )
                            )

                            if IsControlJustReleased(0, Config.InteractControl) then
                                TriggerServerEvent(
                                    'cookie_robbery:server:beginBankLootPoint',
                                    Current.id,
                                    pointId
                                )
                                Wait(500)
                            end
                        end
                    end
                end
            end
        end

        Wait(sleep)
    end
end)

CreateThread(function()
    while true do
        if Current then
            if IsEntityDead(PlayerPedId()) then
                Wait(800)
            else
                SetTextFont(0)
                SetTextScale(0.33, 0.33)
                SetTextColour(255, 255, 255, 230)
                SetTextOutline()
                BeginTextCommandDisplayText('STRING')

                local text
                if Current.phase == 'threat' then
                    if Current.type == 'bank' then
                        text = '~y~대형 RP 준비~s~ · 보안 진입 절차 진행 중'
                    elseif Current.type == 'emptyhouse' then
                        text = '~y~빈집 침입~s~ · 진입 지점을 파손하세요'
                    else
                        text = '~y~소형 RP 준비~s~ · 시작 절차 진행'
                    end
                elseif Current.phase == 'bank_loot' then
                    text = ('~y~대형 RP 전리품 확보~s~ · %d / %d'):format(
                        tonumber(Current.bankLootTotal) or 0,
                        tonumber(Current.requiredLootAmount) or 0
                    )
                elseif Current.phase == 'combat' then
                    text = Current.type == 'bank'
                        and '~r~대형 RP 최종 전멸전~s~ · 승리해야 전리품이 확정됩니다'
                        or '~r~전멸전~s~ · 강도팀이 살아남아야 합니다'
                elseif Current.phase == 'loot' then
                    text = '~y~금고 해제~s~ · E로 전리품 회수'
                else
                    text = '강도 진행 중'
                end

                AddTextComponentSubstringPlayerName(text)
                EndTextCommandDisplayText(0.015, 0.70)
                Wait(0)
            end
        else
            Wait(500)
        end
    end
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, blip in pairs(DispatchBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    PoliceActive = {}
    ActiveBoundaries = {}
end)
