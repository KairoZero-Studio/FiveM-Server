

local function licenseOf(src)
    return GetPlayerIdentifierByType(src, 'license2') or GetPlayerIdentifierByType(src, 'license')
end

function CookieRefreshNameTag(src)
    if not src or src <= 0 then return end

    local license = licenseOf(src)
    if not license then return end

    local u
    pcall(function()
        u = MySQL.single.await(
            'SELECT nickname, gobun FROM cookie_user WHERE license = ? LIMIT 1', { license })
    end)

    local emoji, org, orgDuty, orgColor
    if CookieFactionMemberOf then
        local m = CookieFactionMemberOf(src)
        if m then
            local row = MySQL.single.await(
                "SELECT duty FROM cookie_faction_member WHERE citizenid = ? AND status = 'active' LIMIT 1",
                { m.citizenid })
            local onDuty = (row and (row.duty == 1 or row.duty == true)) or false
            local baseName = (m.tagName and m.tagName ~= '' and m.tagName)
                or (m.name and (m.name:gsub('^쿠키%s*', '')))
                or m.name
            local rankName = (m.rankName and m.rankName ~= '' and m.rankName ~= '-') and m.rankName or nil

            -- DB JOIN이 순간적으로 비거나 예전 데이터가 남아 있어도 현재 Qbox 계급/리더 계급까지 보조 확인한다.
            if not rankName then
                local qp = exports.qbx_core:GetPlayer(src)
                local qjob = qp and qp.PlayerData and qp.PlayerData.job or nil
                if qjob and tostring(qjob.name or '') == tostring(m.jobName or '') and qjob.grade then
                    rankName = qjob.grade.name or qjob.grade.label
                end
            end
            if not rankName and m.isLeader then
                local lr = MySQL.single.await([[
                    SELECT rank_name FROM cookie_faction_rank
                    WHERE faction_id=? AND is_leader=1 ORDER BY grade DESC LIMIT 1
                ]], { m.id })
                rankName = lr and lr.rank_name or nil
            end
            if not rankName then
                local rr = MySQL.single.await([[
                    SELECT rank_name FROM cookie_faction_rank
                    WHERE faction_id=? AND grade=? LIMIT 1
                ]], { m.id, tonumber(m.grade) or 0 })
                rankName = rr and rr.rank_name or nil
            end
            if not rankName then rankName = ('G%s'):format(tostring(m.grade or 0)) end

            -- 네임태그는 팩션명 + 현재 계급을 항상 함께 표시한다.
            org = ('%s %s'):format(baseName, rankName)

            if CookieFactionIsGovType and CookieFactionIsGovType(m.type) then
                orgDuty = onDuty and '출근' or '퇴근'
            else
                -- 사설/범죄 등 비정부 팩션은 출근 시스템이 없으므로 상시 표기한다.
                orgDuty = nil
            end

            emoji = (m.emoji and m.emoji ~= '' and m.emoji)
                or (Config.FactionDefaultEmoji and Config.FactionDefaultEmoji[m.type])
                or nil
            orgColor = CookieNormalizeFactionColor and CookieNormalizeFactionColor(m.color) or (m.color or '#FFB800')
        end
    end

    if not org and CookieCivilJobOf then
        local ok, def, _, onDuty = pcall(CookieCivilJobOf, src)
        if ok and def then
            -- 레벨은 F3 > 내정보 > 직업 레벨에서만 표시.
            -- 머리 위 네임태그에는 직업명만 출력한다.
            org = def.tagName or def.label
            orgDuty = onDuty and '근무중' or '퇴근'
            emoji = (def.emoji and def.emoji ~= '' and def.emoji) or nil
        end
    end

    if not org then
        org = '백수'
        orgDuty = nil
        emoji = nil
    end

    local nickname = (u and u.nickname and u.nickname ~= '' and u.nickname) or '무명'
    local gobun = (u and u.gobun) or nil

    local lover
    if CookieCouplePartnerOf then
        local ok, partnerName = pcall(CookieCouplePartnerOf, src)
        if ok and partnerName and partnerName ~= '' then
            lover = ('%s님 연인'):format(partnerName)
        end
    end

    local badge
    if CookieAdminTeamAuth and CookieGetAdminState and CookieGetAdminState(src) == 'duty' then
        local ok, admin = pcall(CookieAdminTeamAuth, src, 'general')
        if ok and admin then
            local lv = tonumber(admin.admin_level) or 0
            if admin.admin_name and admin.admin_name ~= '' then
                nickname = admin.admin_name
            end
            if lv == 1 then
                emoji, org, orgDuty, orgColor = '🐣', '뉴비가이드', '출근', '#55B8FF'
                badge = nil
            elseif lv == 2 then
                emoji, org, orgDuty, orgColor = '⭐', '스태프', '출근', '#7EDB8F'
                badge = nil
            else
                badge = '관리자'
                emoji, org, orgDuty, lover, orgColor = nil, nil, nil, nil, nil
            end
        end
    end

    Player(src).state:set('cookieTag', {
        name = nickname,
        gobun = gobun,
        emoji = emoji,
        org = org,
        orgDuty = orgDuty,
        orgColor = orgColor,
        badge = badge,
        lover = lover,
        jobless = (org == '백수') or nil,
    }, true)
end

RegisterNetEvent('cookie_admin:server:requestNameTag', function()
    CookieRefreshNameTag(source)
end)

AddEventHandler('cookie_admin:server:nameTagDirty', function(src)
    CookieRefreshNameTag(src)
end)

CreateThread(function()
    while true do
        Wait(60000)
        for _, pid in ipairs(GetPlayers()) do
            local src = tonumber(pid)
            if src then
                pcall(CookieRefreshNameTag, src)
                pcall(CookiePushJobDisplay, src)
            end
        end
    end
end)



AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    CreateThread(function()
        Wait(1200)
        for _, pid in ipairs(GetPlayers()) do
            local src = tonumber(pid)
            if src then pcall(CookieRefreshNameTag, src) end
        end
    end)
end)
