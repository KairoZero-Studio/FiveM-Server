-- COOKIE OPEN EVENT V3
-- 이벤트 UI는 서버 응답을 기다리지 않고 즉시 기본 화면을 연다.
-- 실제 순위/관리자 권한 데이터는 서버 NetEvent로 뒤에서 갱신한다.
-- lib.callback.await()를 NUI callback 안에서 pcall로 감싸지 않는다.

local JOB_ORDER = { 'taxi', 'trucker', 'delivery', 'labor', 'mechanic' }

local function jobLabel(jobKey)
    local cfg = Config.CivilJobs and Config.CivilJobs[jobKey]
    return cfg and tostring(cfg.label or jobKey) or tostring(jobKey)
end

local function jobTitle(jobKey)
    local special = {
        taxi = '오픈 택시왕',
        trucker = '오픈 트럭왕',
        delivery = '오픈 배달왕',
        labor = '오픈 건설왕',
        mechanic = '오픈 정비왕',
    }
    return special[jobKey] or ('오픈 ' .. jobLabel(jobKey) .. ' 1위')
end

local function jobRewardTitle(jobKey)
    local special = {
        taxi = '「초대 택시왕」',
        trucker = '「초대 트럭왕」',
        delivery = '「초대 배달왕」',
        labor = '「초대 건설왕」',
        mechanic = '「초대 정비왕」',
    }
    return special[jobKey] or ('「초대 ' .. jobLabel(jobKey) .. '」')
end

local function makeJobShell(jobKey)
    local label = jobLabel(jobKey)
    return {
        id = 'open_job_' .. jobKey,
        metric = 'job',
        jobKey = jobKey,
        title = jobTitle(jobKey),
        description = ('오픈 이벤트 기간 동안 %s 근무시간이 가장 긴 시민이 우승합니다. 다른 직업의 근무시간과는 합산하지 않습니다.'):format(label),
        badge = label .. ' 1위',
        rewards = {
            { kind = '칭호', text = jobRewardTitle(jobKey) },
        },
        ranking = {},
        my = { rank = nil, minute = 0, jobKey = jobKey, jobLabel = label },
    }
end

local function buildEventShell()
    local events, seen = {}, {}

    for _, jobKey in ipairs(JOB_ORDER) do
        if Config.CivilJobs and Config.CivilJobs[jobKey] then
            seen[jobKey] = true
            events[#events + 1] = makeJobShell(jobKey)
        end
    end

    local extras = {}
    for jobKey in pairs(Config.CivilJobs or {}) do
        if not seen[jobKey] then extras[#extras + 1] = tostring(jobKey) end
    end
    table.sort(extras)
    for _, jobKey in ipairs(extras) do
        events[#events + 1] = makeJobShell(jobKey)
    end

    events[#events + 1] = {id='open_fishing_king',metric='activity',activityKey='fishing',activityLabel='낚시',title='오픈 낚시왕',description='오픈 이벤트 기간 동안 실제 낚시를 가장 오래 진행한 시민이 우승합니다.',badge='낚시시간 1위',rewards={{kind='칭호',text='「초대 낚시왕」'}},ranking={},my={rank=nil,seconds=0}}
    events[#events + 1] = {id='open_mining_king',metric='activity',activityKey='mining',activityLabel='광질',title='오픈 광부왕',description='오픈 이벤트 기간 동안 실제 광질을 가장 오래 진행한 시민이 우승합니다.',badge='광질시간 1위',rewards={{kind='칭호',text='「초대 광부왕」'}},ranking={},my={rank=nil,seconds=0}}

    events[#events + 1] = {
        id = 'open_playtime',
        metric = 'rp',
        title = '도시의 개척자',
        description = '오픈 이벤트 기간 동안 쿠키서버에 가장 오래 접속해 RP 시간을 기록한 시민이 우승합니다.',
        badge = '접속시간 1위',
        rewards = {
            { kind = '칭호', text = '「초대 접속왕」' },
        },
        ranking = {},
        my = { rank = nil, minute = 0 },
    }

    return {
        enabled = true,
        startedAt = '서버 데이터 확인 중',
        canManage = false,
        events = events,
    }
end

RegisterNUICallback('requestOpenEvents', function(_, cb)
    -- UI 기본 카드는 JS가 즉시 그린다. 여기서는 요청 접수만 즉시 반환한다.
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:requestOpenEvents')
end)

RegisterNUICallback('toggleOpenEvents', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:toggleOpenEvents', data and data.enabled == true)
end)

RegisterNUICallback('resetOpenEvents', function(_, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:resetOpenEvents')
end)

RegisterNetEvent('cookie_admin:client:openEventData', function(data, message, isError)
    SendNUIMessage({
        action = 'openEventData',
        data = data or buildEventShell(),
        message = message,
        isError = isError == true
    })
end)

-- V14.0.0: ESC에서도 F3와 완전히 같은 이벤트/출석/퀘스트 HUD를 엽니다.
local publicEventHubOpen = false

RegisterNetEvent('cookie_admin:client:openEventHub', function(tab, sourceMode)
    tab = tostring(tab or 'event')
    local hideQuest = tostring(sourceMode or '') == 'esc'

    if CookieAdminPanelIsOpen and CookieAdminPanelIsOpen() then
        SendNUIMessage({ action = 'openEventHub', tab = tab, standalone = false, hideQuest = hideQuest })
        return
    end

    if publicEventHubOpen then
        SendNUIMessage({ action = 'openEventHub', tab = tab, standalone = true, hideQuest = hideQuest })
        return
    end

    local ok, owner = CookieAdminSetNuiFocus(true, false)
    if ok == false then
        TriggerEvent('cookie_admin:client:notify', ('다른 UI(%s)가 열려 있습니다. 먼저 닫아주세요.'):format(tostring(owner or 'unknown')), true)
        return
    end

    publicEventHubOpen = true
    TriggerEvent('cookie_hud:client:hudVisible', false)
    SendNUIMessage({ action = 'openEventHub', tab = tab, standalone = true, hideQuest = hideQuest })
end)

RegisterNUICallback('closeEventHub', function(_, cb)
    cb({ ok = true })
    if not publicEventHubOpen then return end
    publicEventHubOpen = false
    CookieAdminSetNuiFocus(false, false)
    TriggerEvent('cookie_hud:client:hudVisible', true)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() or not publicEventHubOpen then return end
    publicEventHubOpen = false
    CookieAdminSetNuiFocus(false, false)
    TriggerEvent('cookie_hud:client:hudVisible', true)
end)

print('^2[cookie_admin]^7 EVENT HUB DAILY/MONTHLY V14.2.0 ready')
