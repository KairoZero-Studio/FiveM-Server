-- COOKIE F3 > 시스템 관리 > 월간 쿠지
local kujiAdminData = nil
local kujiBeaconPlacement = false
local kujiPlacementText = false

local function hidePlacementText()
    if kujiPlacementText then
        lib.hideTextUI()
        kujiPlacementText = false
    end
end

local function getGroundAtPlayer()
    -- 쿠키서버의 기존 비콘 좌표 방식과 동일하게 플레이어 엔티티 좌표를 그대로 저장한다.
    -- 실제 DrawMarker에서 Z - 1.0을 적용한다.
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    return vector3(c.x, c.y, c.z)
end

local function stopKujiBeaconPlacement()
    kujiBeaconPlacement = false
    hidePlacementText()
end

local function startKujiBeaconPlacement()
    if kujiBeaconPlacement then return end
    kujiBeaconPlacement = true

    if CookieAdminClosePanel then
        CookieAdminClosePanel()
    else
        CookieAdminSetNuiFocus(false, false)
        SendNUIMessage({ action = 'close' })
    end

    CreateThread(function()
        while kujiBeaconPlacement do
            Wait(0)

            local c = getGroundAtPlayer()
            local col = (kujiAdminData and kujiAdminData.beaconColor) or { r=255, g=190, b=45, a=130 }
            -- 실제 쿠지 비콘과 완전히 동일한 미리보기
            DrawMarker(1,
                c.x, c.y, c.z - 1.0,
                0.0,0.0,0.0, 0.0,0.0,0.0,
                1.60,1.60,0.80,
                tonumber(col.r) or 255,
                tonumber(col.g) or 184,
                tonumber(col.b) or 0,
                tonumber(col.a) or 110,
                false,false,0,false,nil,nil,false)

            if not kujiPlacementText then
                lib.showTextUI('[E] 이 위치에 쿠지 비콘 설치  |  [BACKSPACE] 취소', {
                    position = 'left-center',
                    icon = 'location-dot'
                })
                kujiPlacementText = true
            end

            if IsControlJustReleased(0, 38) then -- E
                local pos = { x=c.x, y=c.y, z=c.z }
                stopKujiBeaconPlacement()
                -- 서버 저장 응답을 기다리지 않고 같은 클라이언트에서 즉시 표시
                TriggerEvent('cookie_kuji:client:forceBeacon', pos, col, (kujiAdminData and kujiAdminData.title) or 'COOKIE 월간 쿠지')
                TriggerServerEvent('cookie_admin:server:setKujiBeacon', pos)
                lib.notify({ title='COOKIE 관리자', description='쿠지 비콘을 이 위치에 설치했습니다.', type='success' })
                break
            end

            if IsControlJustReleased(0, 177) then -- BACKSPACE
                stopKujiBeaconPlacement()
                lib.notify({ title='COOKIE 관리자', description='쿠지 비콘 설치를 취소했습니다.', type='inform' })
                break
            end
        end
    end)
end

RegisterNUICallback('requestKujiSystem', function(_, cb)
    TriggerServerEvent('cookie_admin:server:requestKujiSystem')
    cb('ok')
end)

RegisterNUICallback('saveKujiSystem', function(data, cb)
    TriggerServerEvent('cookie_admin:server:saveKujiSystem', data or {})
    cb('ok')
end)

RegisterNUICallback('resetKujiStock', function(_, cb)
    TriggerServerEvent('cookie_admin:server:resetKujiStock')
    cb('ok')
end)

RegisterNUICallback('startKujiMonth', function(data, cb)
    TriggerServerEvent('cookie_admin:server:startKujiMonth', data or {})
    cb('ok')
end)

RegisterNUICallback('kujiUseCurrentPos', function(_, cb)
    local c = getGroundAtPlayer()
    SendNUIMessage({ action='kujiCurrentPos', data={x=c.x,y=c.y,z=c.z} })
    cb('ok')
end)

-- F3에서 버튼을 누르면 실제 월드에서 직접 위치를 보며 설치한다.
RegisterNUICallback('kujiPlaceBeacon', function(_, cb)
    cb('ok')
    startKujiBeaconPlacement()
end)

RegisterNetEvent('cookie_admin:client:kujiSystemData', function(data)
    kujiAdminData = data or {}
    SendNUIMessage({ action='kujiSystemData', data=kujiAdminData })
end)

RegisterNetEvent('cookie_admin:client:kujiSystemSaved', function(success, message)
    SendNUIMessage({ action='kujiSystemSaved', data={ success = success == true, message = tostring(message or '') } })
end)

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() then
        stopKujiBeaconPlacement()
    end
end)
