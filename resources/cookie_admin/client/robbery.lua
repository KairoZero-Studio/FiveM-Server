RegisterNUICallback('requestRobberyAdmin', function(_, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:requestRobberyAdmin')
end)

RegisterNUICallback('captureRobberyCoords', function(_, cb)
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    cb({
        ok = true,
        x = c.x,
        y = c.y,
        z = c.z,
        heading = GetEntityHeading(ped)
    })
end)

RegisterNUICallback('saveRobberyLocation', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:saveRobberyLocation', data or {})
end)

RegisterNUICallback('deleteRobberyLocation', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:deleteRobberyLocation', data and data.id)
end)

RegisterNetEvent('cookie_admin:client:robberyAdminData', function(data)
    SendNUIMessage({
        action = 'robberyAdminData',
        data = data or {}
    })
end)

RegisterNetEvent('cookie_admin:client:robberyAdminSaved', function(ok, message)
    SendNUIMessage({
        action = 'robberyAdminSaved',
        ok = ok == true,
        message = message or ''
    })
end)


-- COOKIE RP V1.6 - 월드 다각형 꼭짓점 편집
local boundaryCaptureActive = false
local boundaryCapturePoints = {}
local boundaryCaptureOriginal = {}

local function copyBoundaryPoints(points)
    local out = {}
    if type(points) ~= 'table' then return out end
    for _, p in ipairs(points) do
        local x, y, z = tonumber(p.x), tonumber(p.y), tonumber(p.z)
        if x and y and z then
            out[#out + 1] = { x=x, y=y, z=z }
        end
    end
    return out
end

local function drawCaptureWall(a, b, alpha)
    local ax, ay, az = tonumber(a.x), tonumber(a.y), tonumber(a.z)
    local bx, by, bz = tonumber(b.x), tonumber(b.y), tonumber(b.z)
    if not ax or not ay or not az or not bx or not by or not bz then return end

    local h = 1.35
    local a0, b0 = az + 0.03, bz + 0.03
    local a1, b1 = a0 + h, b0 + h

    DrawPoly(ax,ay,a0,bx,by,b0,bx,by,b1,255,30,30,alpha)
    DrawPoly(ax,ay,a0,bx,by,b1,ax,ay,a1,255,30,30,alpha)
    DrawPoly(bx,by,b0,ax,ay,a0,ax,ay,a1,255,30,30,alpha)
    DrawPoly(bx,by,b0,ax,ay,a1,bx,by,b1,255,30,30,alpha)
    DrawLine(ax,ay,a1,bx,by,b1,255,75,75,230)
end

local function finishBoundaryCapture(cancelled)
    if not boundaryCaptureActive then return end

    boundaryCaptureActive = false
    if lib and lib.hideTextUI then
        pcall(lib.hideTextUI)
    end

    local points = cancelled and boundaryCaptureOriginal or boundaryCapturePoints

    CookieAdminSetNuiFocus(true, false)
    SendNUIMessage({
        action = 'robberyBoundaryCaptureFinish',
        cancelled = cancelled == true,
        points = points,
    })

    boundaryCapturePoints = {}
    boundaryCaptureOriginal = {}
end

RegisterNUICallback('startRobberyBoundaryCapture', function(data, cb)
    if boundaryCaptureActive then
        cb({ ok=false, message='이미 범위 편집 중입니다.' })
        return
    end

    boundaryCaptureOriginal = copyBoundaryPoints(data and data.points)
    boundaryCapturePoints = copyBoundaryPoints(data and data.points)
    boundaryCaptureActive = true

    cb({ ok=true })

    SendNUIMessage({ action='robberyBoundaryCaptureStart' })
    CookieAdminSetNuiFocus(false, false)

    if lib and lib.showTextUI then
        pcall(lib.showTextUI,
            '[E] 꼭짓점 추가  [BACKSPACE] 마지막 삭제  [ENTER] 완료  [X] 취소',
            { position='top-center' }
        )
    end
end)

CreateThread(function()
    while true do
        if not boundaryCaptureActive then
            Wait(500)
        else
            Wait(0)

            -- 다른 E 상호작용/공격이 같이 실행되지 않도록 편집 중 차단.
            DisableControlAction(0, 38, true)  -- E
            DisableControlAction(0, 177, true) -- BACKSPACE
            DisableControlAction(0, 191, true) -- ENTER
            DisableControlAction(0, 73, true)  -- X
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)

            local ped = PlayerPedId()
            local c = GetEntityCoords(ped)
            local current = { x=c.x, y=c.y, z=c.z }

            -- 이미 지정한 벽 미리보기
            if #boundaryCapturePoints >= 2 then
                for i = 1, #boundaryCapturePoints - 1 do
                    drawCaptureWall(boundaryCapturePoints[i], boundaryCapturePoints[i + 1], 72)
                end
            end

            -- 마지막 점에서 현재 위치까지 미리보기
            if #boundaryCapturePoints >= 1 then
                drawCaptureWall(boundaryCapturePoints[#boundaryCapturePoints], current, 48)
            end

            -- 3개 이상이면 마지막 -> 첫 점 닫힘 미리보기
            if #boundaryCapturePoints >= 3 then
                drawCaptureWall(
                    boundaryCapturePoints[#boundaryCapturePoints],
                    boundaryCapturePoints[1],
                    38
                )
            end

            for _, p in ipairs(boundaryCapturePoints) do
                DrawMarker(
                    28,
                    p.x, p.y, p.z + 0.12,
                    0.0,0.0,0.0,0.0,0.0,0.0,
                    0.14,0.14,0.14,
                    255,70,70,230,
                    false,false,2,false,nil,nil,false
                )
            end

            if IsDisabledControlJustPressed(0, 38) then
                if #boundaryCapturePoints < 32 then
                    boundaryCapturePoints[#boundaryCapturePoints + 1] = {
                        x = math.floor(c.x * 1000 + 0.5) / 1000,
                        y = math.floor(c.y * 1000 + 0.5) / 1000,
                        z = math.floor(c.z * 1000 + 0.5) / 1000,
                    }
                    TriggerEvent(
                        'cookie_admin:client:notify',
                        ('꼭짓점 %d 추가'):format(#boundaryCapturePoints),
                        false
                    )
                else
                    TriggerEvent('cookie_admin:client:notify', '꼭짓점은 최대 32개입니다.', true)
                end
            end

            if IsDisabledControlJustPressed(0, 177) then
                if #boundaryCapturePoints > 0 then
                    table.remove(boundaryCapturePoints)
                    TriggerEvent('cookie_admin:client:notify', '마지막 꼭짓점을 삭제했습니다.', false)
                end
            end

            if IsDisabledControlJustPressed(0, 191) then
                if #boundaryCapturePoints < 3 then
                    TriggerEvent('cookie_admin:client:notify', '꼭짓점이 최소 3개 필요합니다.', true)
                else
                    finishBoundaryCapture(false)
                end
            end

            if IsDisabledControlJustPressed(0, 73) then
                finishBoundaryCapture(true)
            end
        end
    end
end)
