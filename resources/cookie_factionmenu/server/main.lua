print('^2[COOKIE FACTION F5]^7 V2.1 MDT loaded')

local function isGovType(factionType)
    if GetResourceState('cookie_admin') ~= 'started' then return false end
    local ok, result = pcall(function()
        return exports.cookie_admin:isGovernmentFactionType(factionType)
    end)
    return ok and result == true
end

local function getMembership(src)
    if GetResourceState('cookie_admin') ~= 'started' then return nil end
    local ok, member = pcall(function()
        return exports.cookie_admin:getFactionOf(src)
    end)
    if not ok then return nil end
    return member
end

local function profileFor(src)
    local member = getMembership(src)
    if not member then
        return { allowed = false, reason = '팩션 소속이 아닙니다.' }
    end

    local active = MySQL.scalar.await('SELECT id FROM cookie_faction WHERE id=? AND is_active=1', {tonumber(member.id) or -1})
    if not active then return {allowed=false,reason='F3에서 생성된 활성 팩션이 아닙니다.'} end

    local gov = isGovType(member.type)
    local duty = member.duty == true
    local canUse = true
    local disabledReason = nil

    if Config.RequireDutyForGovernmentActions and gov and not duty then
        canUse = false
        disabledReason = '출근 상태에서만 업무 기능을 사용할 수 있습니다.'
    end

    local player = exports.qbx_core:GetPlayer(src)
    local pd = player and player.PlayerData or {}
    local ci = pd.charinfo or {}

    local gobun = nil
    local okGobun, g = pcall(function() return exports.cookie_core:getGobun(src) end)
    if okGobun then gobun = g end

    return {
        allowed = true,
        canUse = canUse,
        disabledReason = disabledReason,
        faction = {
            id = member.id,
            name = member.name or '팩션',
            type = member.type or '',
            typeLabel = (tostring(member.type or '') == 'tow') and '렉카' or ((Config.IsDaisoFaction and Config.IsDaisoFaction(member)) and '다이소' or ((Config.IsPharmacyFaction and Config.IsPharmacyFaction(member)) and '약국' or (Config.TypeLabels[member.type] or member.type or '팩션'))),
            color = member.color or '#FFB800',
            rank = member.rankName or '-',
            grade = tonumber(member.grade) or 0,
            duty = duty,
            isLeader = member.isLeader == true,
            isOfficer = member.isOfficer == true,
        },
        officer = {
            citizenid = pd.citizenid or '',
            gobun = gobun,
            name = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', ''),
        }
    }
end

lib.callback.register('cookie_factionmenu:getProfile', function(source)
    return profileFor(source)
end)
