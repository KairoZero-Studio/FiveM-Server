local Queue = {}

local WEBHOOK_GROUPS = {
    trade = 'cookie_log_trade',

    seize = 'cookie_log_police_work',
    wanted = 'cookie_log_police_work',
    escape = 'cookie_log_police_work',
    backup = 'cookie_log_police_work',
    report_close = 'cookie_log_police_work',
    warrant = 'cookie_log_police_work',
    fine = 'cookie_log_police_work',

    kick = 'cookie_log_admin',
    ban = 'cookie_log_admin',
    admin_call = 'cookie_log_admin',
    admin_detention = 'cookie_log_admin',

    police_report = 'cookie_log_police',
    police_detention = 'cookie_log_police',
    police_account = 'cookie_log_police',

    security_report = 'cookie_log_security',
    security_detention = 'cookie_log_security',
    security_account = 'cookie_log_security',
}

local VALID_LOG_CATEGORIES = {
    trade=true,
    seize=true,
    wanted=true,
    escape=true,
    backup=true,
    report_close=true,
    warrant=true,
    fine=true,
    kick=true,
    ban=true,
    admin_call=true,
    admin_detention=true,
    police_report=true,
    security_report=true,
    police_detention=true,
    security_detention=true,
    police_account=true,
    security_account=true,
}

local function isWebhookUrl(value)
    value=tostring(value or '')
    return value:match('^https://discord%.com/api/webhooks/') ~= nil
        or value:match('^https://ptb%.discord%.com/api/webhooks/') ~= nil
        or value:match('^https://canary%.discord%.com/api/webhooks/') ~= nil
end

local function resolveWebhook(category)
    category = tostring(category or ''):lower()

    if not VALID_LOG_CATEGORIES[category] then
        return '', nil
    end

    -- 1. config.lua의 Config.Webhooks[category]에 URL 직접 입력
    if type(Config.Webhooks)=='table' then
        local direct=tostring(Config.Webhooks[category] or '')
        if isWebhookUrl(direct) then
            return direct, 'Config.Webhooks.'..category
        end
    end

    -- 2. 기존 Config.WebhookGroups에 URL을 직접 넣어둔 경우도 지원
    if type(Config.WebhookGroups)=='table' then
        local configured=tostring(Config.WebhookGroups[category] or '')
        if isWebhookUrl(configured) then
            return configured, 'Config.WebhookGroups.'..category
        end
    end

    -- 3. server.cfg 개별 webhook
    local exactName = 'cookie_log_' .. category
    local exact = GetConvar(exactName, '')
    if exact and exact ~= '' then
        return exact, exactName
    end

    -- 4. Config.WebhookGroups 값이 convar 이름인 경우
    if type(Config.WebhookGroups)=='table' then
        local configured=tostring(Config.WebhookGroups[category] or '')
        if configured~='' and not isWebhookUrl(configured) then
            local grouped=GetConvar(configured,'')
            if grouped and grouped~='' then
                return grouped, configured
            end
        end
    end

    -- 5. 기본 그룹 convar fallback
    local groupName = WEBHOOK_GROUPS[category]
    if groupName then
        local grouped = GetConvar(groupName, '')
        if grouped and grouped ~= '' then
            return grouped, groupName
        end
    end

    return '', exactName
end


local function clean(value, maxLen)
    local s = tostring(value or ''):gsub('[%z\1-\31]', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if maxLen and #s > maxLen then s = s:sub(1, maxLen) end
    return s
end

local function playerData(src)
    src = tonumber(src)
    if not src or src <= 0 or not GetPlayerName(src) then return nil end

    local p = exports.qbx_core:GetPlayer(src)
    local pd = p and p.PlayerData or nil

    local gobun, nick
    pcall(function() gobun = exports.cookie_core:getGobun(src) end)
    pcall(function() nick = exports.cookie_core:getNickname(src) end)

    nick = clean(nick, 80)
    if nick == '' then nick = clean(GetPlayerName(src), 80) end

    local faction
    if GetResourceState('cookie_admin') == 'started' then
        pcall(function()
            local m = exports.cookie_admin:getFactionMember(src)
            if m then
                faction = {
                    id = tonumber(m.id),
                    name = clean(m.name or m.factionName or m.key, 80),
                    type = clean(m.type, 24):lower(),
                    rank = clean(m.rankName, 60),
                    duty = m.duty == true,
                }
            end
        end)
    end

    local license, discord
    if Config.IncludeIdentifiers then
        license = GetPlayerIdentifierByType(src, 'license2') or GetPlayerIdentifierByType(src, 'license')
        discord = GetPlayerIdentifierByType(src, 'discord')
    end

    return {
        src = src,
        gobun = tonumber(gobun),
        name = nick,
        citizenid = pd and clean(pd.citizenid, 64) or '',
        faction = faction,
        license = license,
        discord = discord,
    }
end

local function playerFields(label, src)
    local p = playerData(src)
    if not p then return {} end

    local out = {{
        name = clean(label or '시민', 60),
        value = ('**%s / %s** · SID `%d`'):format(
            tostring(p.gobun or '-'), p.name, p.src
        ),
        inline = false,
    }}

    if p.faction and p.faction.name ~= '' then
        out[#out+1] = {
            name = '소속',
            value = ('%s%s%s'):format(
                p.faction.name,
                p.faction.rank ~= '' and (' · ' .. p.faction.rank) or '',
                p.faction.duty and ' · 근무중' or ''
            ),
            inline = true,
        }
    end

    if Config.IncludeIdentifiers then
        if p.license then
            out[#out+1] = {name='License', value='`'..clean(p.license,100)..'`', inline=false}
        end
        if p.discord then
            out[#out+1] = {name='Discord', value='`'..clean(p.discord,100)..'`', inline=true}
        end
    end

    return out
end

local function normalizeFields(fields)
    local out = {}
    if type(fields) ~= 'table' then return out end

    for _, row in ipairs(fields) do
        if type(row) == 'table' and #out < 25 then
            local name = clean(row.name or '-', 256)
            local value = clean(row.value or '-', 1024)
            if name ~= '' and value ~= '' then
                out[#out+1] = {
                    name = name,
                    value = value,
                    inline = row.inline == true
                }
            end
        end
    end

    return out
end

local function Log(category, title, description, fields, options)
    if not Config.Enabled then return false end

    category = clean(category, 40):lower()
    if not VALID_LOG_CATEGORIES[category] then
        return false
    end

    local webhook, webhookSource = resolveWebhook(category)
    webhook = clean(webhook, 600)
    title = clean(title, 256)
    description = clean(description, 4096)
    fields = normalizeFields(fields)
    options = type(options) == 'table' and options or {}

    local actor = tonumber(options.actorSrc or options.actor)
    local target = tonumber(options.targetSrc or options.target)

    local all = {}

    if actor then
        for _, f in ipairs(playerFields(options.actorLabel or '처리자', actor)) do
            all[#all+1] = f
        end
    end

    if target then
        for _, f in ipairs(playerFields(options.targetLabel or '대상', target)) do
            if #all >= 25 then break end
            all[#all+1] = f
        end
    end

    for _, f in ipairs(fields) do
        if #all >= 25 then break end
        all[#all+1] = f
    end

    if Config.StoreDatabase then
        CreateThread(function()
            pcall(function()
                MySQL.insert.await([[
                    INSERT INTO cookie_system_log_v2
                      (category,title,description,actor_source,target_source,event_key,detail_json)
                    VALUES (?,?,?,?,?,?,?)
                ]], {
                    category, title, description, actor, target,
                    clean(options.eventKey, 80), json.encode(all)
                })
            end)
        end)
    end

    if Config.ConsoleMirror then
        print(('[COOKIE LOG][%s] %s%s'):format(
            category:upper(),
            title,
            description ~= '' and (' · ' .. description) or ''
        ))
    end

    -- 웹훅이 비어 있어도 DB 기록까지는 정상 처리.
    if webhook == '' then return true end

    if #Queue >= (Config.MaxQueue or 1000) then
        table.remove(Queue, 1)
    end

    Queue[#Queue+1] = {
        url = webhook,
        retry = 0,
        debugHttp = options.debugHttp == true,
        category = category,
        webhookSource = webhookSource,
        body = {
            username = Config.BotName or 'COOKIE LOG',
            avatar_url = clean(Config.AvatarURL, 600) ~= '' and Config.AvatarURL or nil,
            allowed_mentions = {parse={}},
            embeds = {{
                title = title,
                description = description ~= '' and description or nil,
                color = (Config.Colors and Config.Colors[category]) or 0xD39B47,
                fields = all,
                timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
                footer = {text='COOKIE SERVER'},
            }},
        },
    }

    return true
end

exports('Log', Log)
exports('PlayerData', playerData)

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_system_log_v2 (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
            category VARCHAR(40) NOT NULL,
            title VARCHAR(256) NOT NULL,
            description TEXT NULL,
            actor_source INT NULL,
            target_source INT NULL,
            event_key VARCHAR(80) NULL,
            detail_json LONGTEXT NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_cookie_system_log_v2_cat(category,created_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    print('^2[cookie_logs]^7 Discord Logs V2 ready')
end)

CreateThread(function()
    while true do
        if #Queue == 0 then
            Wait(250)
        else
            local item = table.remove(Queue, 1)

            PerformHttpRequest(item.url, function(status)
                status = tonumber(status) or 0

                if status == 429 and item.retry < 3 then
                    item.retry = item.retry + 1
                    SetTimeout(1800 * item.retry, function()
                        Queue[#Queue+1] = item
                    end)
                elseif status < 200 or status >= 300 then
                    print(('[cookie_logs] %s Discord HTTP ERROR %s · source=%s'):format(
                        tostring(item.category or '?'),
                        tostring(status),
                        tostring(item.webhookSource or '?')
                    ))
                elseif item.debugHttp then
                    print(('[cookie_logs] %s Discord HTTP OK %s · source=%s'):format(
                        tostring(item.category or '?'),
                        tostring(status),
                        tostring(item.webhookSource or '?')
                    ))
                end
            end, 'POST', json.encode(item.body), {
                ['Content-Type'] = 'application/json'
            })

            Wait(Config.SendIntervalMs or 650)
        end
    end
end)

local function sendAdminCall(src, reason)
    src = tonumber(src)
    reason = clean(reason, 500)

    if not src or not GetPlayerName(src) or #reason < 2 then
        return false
    end

    Log('admin_call', '관리자 콜', reason, {}, {
        actorSrc = src,
        actorLabel = '신고자',
        eventKey = 'admin_call'
    })

    if GetResourceState('cookie_admin') == 'started' then
        for _, raw in ipairs(GetPlayers()) do
            local sid = tonumber(raw)
            if sid then
                local ok, duty = pcall(function()
                    return exports.cookie_admin:isAdminDuty(sid, 1)
                end)

                if ok and duty == true then
                    local p = playerData(src)
                    TriggerClientEvent(
                        'cookie_admin:client:notify',
                        sid,
                        ('관리자 콜 · %s / %s · %s'):format(
                            tostring(p and p.gobun or '-'),
                            tostring(p and p.name or GetPlayerName(src)),
                            reason
                        ),
                        false
                    )
                end
            end
        end

        TriggerClientEvent(
            'cookie_admin:client:notify',
            src,
            '관리자에게 콜을 전송했습니다.',
            false
        )
    end

    return true
end

RegisterNetEvent('cookie_logs:server:adminCall', function(reason)
    sendAdminCall(source, reason)
end)

RegisterCommand('admincall', function(src, args)
    if src == 0 then return end
    if not sendAdminCall(src, table.concat(args or {}, ' ')) then
        TriggerClientEvent('cookie_admin:client:notify', src, '사용법: /admincall 문의내용', true)
    end
end, false)

RegisterCommand('관리자콜', function(src, args)
    if src == 0 then return end
    if not sendAdminCall(src, table.concat(args or {}, ' ')) then
        TriggerClientEvent('cookie_admin:client:notify', src, '사용법: /관리자콜 문의내용', true)
    end
end, false)

RegisterCommand('cookielogstatus', function(src)
    if src ~= 0 then return end

    print('----- COOKIE LOG V2.1 WEBHOOK STATUS -----')

    local keys={}
    for key in pairs(VALID_LOG_CATEGORIES) do keys[#keys+1]=key end
    table.sort(keys)

    for _,key in ipairs(keys) do
        local url,sourceName=resolveWebhook(key)
        local configured=url and url~=''
        print(('%-22s %-11s via %s'):format(
            key,
            configured and 'CONFIGURED' or 'EMPTY',
            tostring(sourceName or '-')
        ))
    end
end, true)

RegisterCommand('cookielogtest', function(src, args)
    if src ~= 0 then return end

    local key = clean(args and args[1] or 'trade', 40)
    if not VALID_LOG_CATEGORIES[key] then
        print('[cookie_logs] unknown category: ' .. key)
        return
    end

    local webhook,sourceName=resolveWebhook(key)
    if not webhook or webhook=='' then
        print(('[cookie_logs] %s WEBHOOK EMPTY · config.lua의 Config.Webhooks.%s 또는 server.cfg의 cookie_log_%s 를 설정하세요.'):format(
            key,
            key,
            key
        ))
        return
    end

    print(('[cookie_logs] %s test queued · source=%s'):format(
        key,tostring(sourceName or '-')
    ))

    Log(key, 'COOKIE LOG V2.1 테스트', '웹훅 연결 테스트입니다.', {
        {name='카테고리',value=key,inline=true},
        {name='상태',value='정상',inline=true},
    }, {
        eventKey='manual_test',
        debugHttp=true
    })
end, true)
