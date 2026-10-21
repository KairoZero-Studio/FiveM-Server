local function getPlayer(src)
    local ok, p = pcall(function()
        return exports.qbx_core:GetPlayer(src)
    end)
    return ok and p or nil
end

local function getNickname(src)
    if GetResourceState('cookie_core') == 'started' then
        local ok, name = pcall(function()
            return exports.cookie_core:getNickname(src)
        end)
        if ok and name and name ~= '' then
            return tostring(name)
        end
    end

    local p = getPlayer(src)
    local ci = p and p.PlayerData and p.PlayerData.charinfo
    if ci then
        local full = ((ci.firstname or '') .. ' ' .. (ci.lastname or ''))
            :gsub('^%s+', '')
            :gsub('%s+$', '')
        if full ~= '' then return full end
    end

    return GetPlayerName(src) or ('시민 #' .. tostring(src))
end

local function getFactionActivity(src)
    if GetResourceState('cookie_admin') ~= 'started' then
        return nil, nil
    end

    local ok, member = pcall(function()
        return exports.cookie_admin:getFactionMember(src)
    end)

    if not ok or type(member) ~= 'table' then
        return nil, nil
    end

    local duty = member.duty == true
    if not duty then return nil, nil end

    local ftype = tostring(member.type or ''):lower()
    if Config.FactionTypeLabels[ftype] then
        return Config.FactionTypeLabels[ftype], Config.ActivityPriority[ftype .. '_duty'] or 70
    end

    local name = tostring(member.name or member.factionName or '팩션')
    local rank = tostring(member.rankName or member.rank_name or '')
    if rank ~= '' then
        return ('🏢 %s · %s 근무 중'):format(name, rank), Config.ActivityPriority.faction_duty or 60
    end

    return ('🏢 %s · 근무 중'):format(name), Config.ActivityPriority.faction_duty or 60
end

local function getJobActivity(src)
    local p = getPlayer(src)
    if not p or not p.PlayerData then return nil, nil end

    local job = p.PlayerData.job
    if not job then return nil, nil end

    local label = job.label or job.name
    if not label or label == '' then return nil, nil end

    if job.onduty == false then
        return ('💼 %s'):format(label), Config.ActivityPriority.job or 30
    end

    return ('💼 %s · 근무 중'):format(label), Config.ActivityPriority.job or 30
end

RegisterNetEvent('cookie_discordrpc:server:requestContext', function()
    local src = source

    local factionText, factionPriority = getFactionActivity(src)
    local jobText, jobPriority = getJobActivity(src)

    TriggerClientEvent('cookie_discordrpc:client:context', src, {
        nickname = getNickname(src),
        players = #GetPlayers(),
        max = GetConvarInt('sv_maxclients', 48),
        factionActivity = factionText,
        factionPriority = factionPriority,
        jobActivity = jobText,
        jobPriority = jobPriority,
    })
end)

print('^2[cookie_discordrpc]^7 Rich Presence server loaded')
