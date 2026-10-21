

local outTo = 0

local function line(s)
    if outTo == 0 then

    else

        local plain = s:gsub('%^%d', '')
        TriggerClientEvent('chat:addMessage', outTo, {
            templateId = 'cookie_system',
            args = { plain }
        })

    end
end

local function canRun(src)
    if src == 0 then return true end
    if IsPlayerAceAllowed(src, 'cookie.chat.admin') then return true end
    TriggerClientEvent('chat:addMessage', src, {
        templateId = 'cookie_system',
        args = { '이 명령은 관리자만 사용할 수 있습니다.' }
    })
    return false
end

RegisterCommand('facveh', function(src)
    if not canRun(src) then return end
    outTo = src

    CreateThread(function()

        local factions = MySQL.query.await(
            'SELECT id, name, job_name, faction_type, garage_key FROM cookie_faction', {})
        if not factions or #factions == 0 then
            return line('^1팩션이 하나도 없습니다^7')
        end

        for _, f in ipairs(factions) do
            line(('팩션 #%d %s (job=%s, type=%s, garage_key=%s)'):format(
                f.id, f.name, tostring(f.job_name), tostring(f.faction_type),
                tostring(f.garage_key or '^1없음^7')))

            local shop = MySQL.query.await(
                'SELECT model, label, price, min_grade, active FROM cookie_faction_shop WHERE faction_id = ?',
                { f.id })
            line(('  ① 카탈로그(구매 가능 목록): %d대'):format(shop and #shop or 0))
            for _, s in ipairs(shop or {}) do
                line(('     - %s (%s) 가격=%s 최소계급=%s 활성=%s'):format(
                    s.model, tostring(s.label), tostring(s.price), tostring(s.min_grade), tostring(s.active)))
            end

            local owned = MySQL.query.await(
                'SELECT id, model, min_grade FROM cookie_faction_vehicle WHERE faction_id = ?', { f.id })
            line(('  ② 보유 기록(구매 완료): %d대'):format(owned and #owned or 0))
            for _, v in ipairs(owned or {}) do
                line(('     - %s (출고 최소계급 %s)'):format(v.model, tostring(v.min_grade)))
            end

            if f.garage_key and f.garage_key ~= '' then
                local pv = MySQL.query.await([[
                    SELECT id, citizenid, vehicle, plate, state, garage
                    FROM player_vehicles WHERE garage = ?
                ]], { f.garage_key })
                line(('  ③ 실차(player_vehicles, garage=%s): %d대'):format(f.garage_key, pv and #pv or 0))

                local badState, badModel = 0, 0
                for _, v in ipairs(pv or {}) do

                    local st = tonumber(v.state) or -1
                    if st ~= 1 then badState = badState + 1 end

                    local known = false
                    local okC = pcall(function()
                        local info = exports.qbx_core:GetVehiclesByName()[v.vehicle]
                        known = info ~= nil and info.category ~= nil
                    end)
                    if not okC or not known then badModel = badModel + 1 end

                    line(('     - %s  번호판=%s  상태=%s(%s)  주인=%s  카탈로그=%s'):format(
                        v.vehicle, tostring(v.plate), tostring(v.state),
                        st == 1 and '차고에 있음' or '^1밖에 나가 있음^7',
                        tostring(v.citizenid),
                        known and '있음' or '^1없음^7'))
                end

                if (owned and #owned > 0) and (not pv or #pv == 0) then
                    line('  ^1▶ 원인: 구매 기록은 있는데 실차가 없습니다.^7')
                    line('     ^3해결: 콘솔에 facfix^7')
                end
                if badState > 0 then
                    line(('  ^1▶ 원인: %d대가 state<>1 입니다(밖에 나가 있는 것으로 취급).^7'):format(badState))
                    line('     ^3해결: 콘솔에 facpark  (전부 차고 상태로 되돌립니다)^7')
                end
                if badModel > 0 then
                    line(('  ^1▶ 원인: %d대가 qbx 차량 카탈로그(vehicles.lua)에 없는 모델입니다.^7'):format(badModel))
                    line('     ^3이러면 qbx_garages 조회가 통째로 실패해서 차고가 비어 보입니다.^7')
                end
                if pv and #pv > 0 and badState == 0 and badModel == 0 then
                    line('  ^2▶ 실차/상태/모델 모두 정상입니다. 그러면 접근 권한(직업) 문제입니다 → myjob <id>^7')
                end
            else
                line('  ^1③ garage_key 가 비어 있습니다 → 차고에 절대 안 붙습니다^7')
            end
        end

    end)
end, true)

RegisterCommand('facfix', function(src)
    if not canRun(src) then return end
    outTo = src

    CreateThread(function()
        local orphans = MySQL.query.await([[
            SELECT v.id, v.faction_id, v.model, f.garage_key, f.name
            FROM cookie_faction_vehicle v
            JOIN cookie_faction f ON f.id = v.faction_id
            LEFT JOIN player_vehicles pv
                   ON pv.garage = f.garage_key AND pv.vehicle = v.model
            WHERE f.garage_key IS NOT NULL AND f.garage_key <> '' AND pv.id IS NULL
        ]], {})

        if not orphans or #orphans == 0 then
            return line('^2복구할 것이 없습니다 (보유 기록 = 실차)^7')
        end

        line(('복구 대상 %d대'):format(#orphans))

        local fixed, failed = 0, 0
        for _, o in ipairs(orphans) do

            local ownerCid = ('FACTION_%d'):format(o.faction_id)
            CookieEnsureFactionOwner(ownerCid)

            local ok, vid = pcall(function()
                return exports.qbx_vehicles:CreatePlayerVehicle({
                    model = o.model,
                    citizenid = ownerCid,
                    garage = o.garage_key,
                })
            end)

            if ok and vid then
                fixed = fixed + 1
                line(('  ^2복구^7 %s → %s (vid=%s)'):format(o.model, o.garage_key, tostring(vid)))
            else
                failed = failed + 1
                line(('  ^1실패^7 %s : %s'):format(o.model, tostring(vid)))
            end
        end

        line(('완료: 복구 %d대 / 실패 %d대'):format(fixed, failed))
        line('^3차고에 다시 가서 E를 눌러보세요.^7')
    end)
end, true)

RegisterCommand('facpark', function(src)
    if not canRun(src) then return end
    outTo = src

    CreateThread(function()
        local n = MySQL.update.await([[
            UPDATE player_vehicles pv
            JOIN cookie_faction f ON f.garage_key = pv.garage
            SET pv.state = 1
            WHERE pv.state <> 1
        ]], {})
        line(('^2%d대를 차고 상태로 되돌렸습니다.^7'):format(n or 0))
        line('^3차고에 다시 가서 E를 눌러보세요.^7')
    end)
end, true)

RegisterCommand('myjob', function(src, args)
    if not canRun(src) then return end
    outTo = src

    local target = tonumber(args[1]) or (src ~= 0 and src or nil)
    if not target then
        return line('사용법: myjob <serverId>')
    end

    CreateThread(function()
        local p = exports.qbx_core:GetPlayer(target)
        if not p then return line('^1해당 id의 플레이어가 없습니다^7') end
        local j = p.PlayerData.job or {}
        line(('src=%d  직업키=%s  라벨=%s  등급=%s  온듀티=%s'):format(
            target, tostring(j.name), tostring(j.label),
            tostring(j.grade and j.grade.level), tostring(j.onduty)))

        local held, n = {}, 0
        for name, grade in pairs(p.PlayerData.jobs or {}) do
            n = n + 1
            held[#held + 1] = ('%s(%s)'):format(name, tostring(grade))
        end
        line(('보유 직업 %d/1: %s%s'):format(
            n, (n > 0 and table.concat(held, ', ') or '없음'),
            (n >= 1 and j.name == 'unemployed') and '  ^1← 정원이 찼는데 무직이다. jobfix 필요^7' or ''))

        local fac = MySQL.single.await([[
            SELECT f.name, m.grade, m.duty, m.status
            FROM cookie_faction_member m
            JOIN cookie_faction f ON f.id = m.faction_id
            WHERE m.citizenid = ?
        ]], { p.PlayerData.citizenid })
        if fac then
            line(('팩션: %s  계급=%s  근무=%s  상태=%s'):format(
                fac.name, tostring(fac.grade), tostring(fac.duty), tostring(fac.status)))
        else
            line('^1팩션 멤버가 아닙니다^7')
        end
    end)
end, true)

RegisterCommand('jobfix', function(src, args)
    if not canRun(src) then return end
    outTo = src

    local target = tonumber(args[1]) or (src ~= 0 and src or nil)
    if not target then return line('사용법: jobfix <serverId>') end

    CreateThread(function()
        local p = exports.qbx_core:GetPlayer(target)
        if not p then return line('^1해당 id의 플레이어가 없습니다^7') end

        local cid = p.PlayerData.citizenid
        local before = {}
        for name in pairs(p.PlayerData.jobs or {}) do before[#before + 1] = name end

        if #before == 0 then
            return line('보유 직업이 없습니다. 정원은 비어 있습니다 (문제 없음)')
        end

        line(('보유 직업 제거: %s'):format(table.concat(before, ', ')))
        CookieClearAllJobs(cid, nil)

        local after = 0
        local p2 = exports.qbx_core:GetPlayer(target)
        for _ in pairs(p2 and p2.PlayerData.jobs or {}) do after = after + 1 end

        line(('완료. 보유 직업 %d개 남음 → 이제 취업할 수 있습니다'):format(after))
        CookieRefreshNameTag(target)
        CookiePushJobDisplay(target)
    end)
end, true)
