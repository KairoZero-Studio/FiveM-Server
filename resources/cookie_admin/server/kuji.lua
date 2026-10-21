local function allowed(src)
    -- F3 시스템 관리와 동일한 기준:
    -- 활성 관리자(is_active=1) + 유효 LV5 이상.
    -- TINYINT가 oxmysql에서 boolean true로 반환되는 환경도 있어서
    -- is_active를 Lua에서 tonumber()로 판정하지 않고 SQL WHERE에서 확인한다.
    local license = GetPlayerIdentifierByType(src, 'license2')
        or GetPlayerIdentifierByType(src, 'license')

    if not license then
        return false, '관리자 라이선스를 확인할 수 없습니다.'
    end

    local row = MySQL.single.await([[
        SELECT admin_level, (pw_hash IS NOT NULL) AS has_pw
        FROM cookie_admin
        WHERE license = ? AND is_active = 1
        LIMIT 1
    ]], { license })

    if not row then
        return false, '활성화된 관리자 계정이 아닙니다.'
    end

    local level = tonumber(row.admin_level) or 0
    local hasPw = row.has_pw == true
        or row.has_pw == 1
        or row.has_pw == '1'

    -- 기존 F3 시스템 관리와 동일하게 LV5 이상은 관리자 비밀번호가 있어야 유효 LV5.
    local effectiveLevel = level
    if level >= 5 and not hasPw then
        effectiveLevel = 4
    end

    if effectiveLevel < 5 then
        return false, '시스템 관리 권한(LV5 + 관리자 비밀번호)이 필요합니다.'
    end

    return true
end

local function notify(src,msg,bad)
    TriggerClientEvent('cookie_admin:client:notify',src,tostring(msg or ''),bad==true)
end

local function resourceReady(src)
    if GetResourceState('cookie_kuji') ~= 'started' then
        notify(src,'cookie_kuji 리소스가 실행 중이 아닙니다.',true)
        return false, 'cookie_kuji 리소스가 실행 중이 아닙니다.'
    end
    return true
end

RegisterNetEvent('cookie_admin:server:requestKujiSystem',function()
    local src=source

    local auth, authErr = allowed(src)
    if not auth then
        TriggerClientEvent('cookie_admin:client:kujiSystemData', src, { loadError = authErr or '권한이 없습니다.' })
        return
    end

    local ready, readyErr = resourceReady(src)
    if not ready then
        TriggerClientEvent('cookie_admin:client:kujiSystemData', src, { loadError = readyErr or 'cookie_kuji가 준비되지 않았습니다.' })
        return
    end

    local ok,data=pcall(function() return exports.cookie_kuji:GetAdminData() end)
    if not ok then
        print(('^1[cookie_admin][kuji]^7 GetAdminData failed: %s'):format(tostring(data)))
        notify(src,'쿠지 설정을 불러오지 못했습니다. 서버 콘솔을 확인하세요.',true)
        TriggerClientEvent('cookie_admin:client:kujiSystemData', src, { loadError = '쿠지 DB/설정 로딩 오류가 발생했습니다.' })
        return
    end

    TriggerClientEvent('cookie_admin:client:kujiSystemData',src,data or { loadError = '쿠지 설정 데이터가 비어 있습니다.' })
end)

RegisterNetEvent('cookie_admin:server:saveKujiSystem',function(data)
    local src=source
    local auth = select(1, allowed(src))
    if not auth or not select(1, resourceReady(src)) then
        TriggerClientEvent('cookie_admin:client:kujiSystemSaved', src, false, '권한 또는 쿠지 리소스를 확인하세요.')
        return
    end
    local ok,success,msg=pcall(function() return exports.cookie_kuji:SaveAdminData(data or {}) end)
    if not ok then
        print(('^1[cookie_admin][kuji]^7 SaveAdminData failed: %s'):format(tostring(success)))
        notify(src,'쿠지 저장 중 오류가 발생했습니다.',true)
        TriggerClientEvent('cookie_admin:client:kujiSystemSaved', src, false, '쿠지 저장 중 서버 오류가 발생했습니다.')
        return
    end
    notify(src,msg or (success and '저장했습니다.' or '저장 실패'),not success)
    TriggerClientEvent('cookie_admin:client:kujiSystemSaved', src, success == true, msg or '')
end)

RegisterNetEvent('cookie_admin:server:resetKujiStock',function()
    local src=source
    local auth = select(1, allowed(src)); if not auth or not select(1, resourceReady(src)) then return end
    local ok,success,msg=pcall(function() return exports.cookie_kuji:ResetStock() end)
    if not ok then return notify(src,'재고 초기화 중 오류가 발생했습니다.',true) end
    notify(src,msg or '',not success)
    if success then TriggerClientEvent('cookie_admin:client:kujiSystemData',src,exports.cookie_kuji:GetAdminData()) end
end)

RegisterNetEvent('cookie_admin:server:startKujiMonth',function(data)
    local src=source
    local auth = select(1, allowed(src)); if not auth or not select(1, resourceReady(src)) then return end
    local ok,success,msg=pcall(function() return exports.cookie_kuji:StartMonth(data or {}) end)
    if not ok then return notify(src,'새 월 시작 중 오류가 발생했습니다.',true) end
    notify(src,msg or '',not success)
    if success then TriggerClientEvent('cookie_admin:client:kujiSystemData',src,exports.cookie_kuji:GetAdminData()) end
end)


-- 게임 월드에서 관리자 직접 비콘 설치
RegisterNetEvent('cookie_admin:server:setKujiBeacon', function(coords)
    local src = source
    local auth = select(1, allowed(src)); if not auth or not select(1, resourceReady(src)) then return end
    local ok, success, msg = pcall(function()
        return exports.cookie_kuji:SetBeacon(coords or {})
    end)
    if not ok then
        return notify(src, '쿠지 비콘 설치 중 오류가 발생했습니다.', true)
    end
    notify(src, msg or (success and '쿠지 비콘을 설치했습니다.' or '비콘 설치 실패'), not success)
    if success then
        TriggerClientEvent('cookie_admin:client:kujiSystemData', src, exports.cookie_kuji:GetAdminData())
    end
end)
