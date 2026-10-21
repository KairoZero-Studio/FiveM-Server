-- COOKIE CHAT TITLE TEMPLATE V1.1
-- FiveM chat escapes/reformats message args. Image data URI must live in the
-- registered HTML template itself, not inside args.

local registered = {}

local function registerBaseTemplates()
    local html = '<div class="ck-wrap {0}">'
        .. '<span class="ck-chip ck-chip--gobun">{1}</span>'
        .. '<span class="ck-chip ck-chip--label {2}" style="background:{10};color:{11}">{3}</span>'
        .. '<span class="ck-nick">{4}</span>'
        .. '<span class="ck-body">{5}</span>'
        .. '</div>'

    TriggerEvent('chat:addTemplate', 'cookie_msg', html)
    TriggerEvent('chat:addTemplate', 'cookie_whisper',
        '<div class="ck-wrap ck-wrap--whisper">'
        .. '<span class="ck-whisper-tag">[귓속말 {0}]</span>'
        .. '<span class="ck-whisper-who">{1} | {2}</span>'
        .. '<span class="ck-body">{3}</span></div>')
end

local function validTemplateData(row)
    if type(row) ~= 'table' then return false end
    local id = tonumber(row.id)
    local image = tostring(row.image or '')
    if not id or image == '' then return false end

    -- Do not hard-code prefix lengths. The previous version checked each
    -- prefix one character short, so EVERY valid uploaded image was rejected
    -- and the chat silently fell back to the no-title template.
    local prefixes = {
        'data:image/webp;base64,',
        'data:image/png;base64,',
        'data:image/jpeg;base64,',
        'data:image/gif;base64,',
    }

    local valid = false
    for _, prefix in ipairs(prefixes) do
        if image:sub(1, #prefix) == prefix then
            valid = true
            break
        end
    end

    if not valid then return false end
    return true, id, image
end

local function registerTemplate(row)
    local ok, id, image = validTemplateData(row)
    if not ok then return end

    local templateId = ('cookie_msg_title_%d'):format(id)

    -- The image URI is inserted into the template source itself.
    -- Only ordinary text values remain as {0}..{5} args.
    local html = '<div class="ck-wrap {0}">'
        .. '<img class="ck-chat-title" src="' .. image .. '">'
        .. '<span class="ck-chip ck-chip--gobun">{1}</span>'
        .. '<span class="ck-nick">{4}</span>'
        .. '<span class="ck-body">{5}</span>'
        .. '</div>'

    TriggerEvent('chat:addTemplate', templateId, html)
    registered[id] = true
end

RegisterNetEvent('cookie_chat:client:registerTitleTemplate', function(row)
    registerTemplate(row)
end)

RegisterNetEvent('cookie_chat:client:registerTitleTemplates', function(rows)
    if type(rows) ~= 'table' then return end
    for _, row in ipairs(rows) do
        registerTemplate(row)
    end
end)

local function requestTemplates()
    TriggerServerEvent('cookie_chat:server:requestTitleTemplates')
end

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() and resource ~= 'chat' then return end
    CreateThread(function()
        Wait(700)
        registerBaseTemplates()
        requestTemplates()
    end)
end)


-- COOKIE CHAT TITLE V1.6
-- V1.3에서 원본 메시지는 서버에서 cancel 되었지만
-- client chat:addMessage에 inline `template`을 넣는 방식이 렌더링되지 않아
-- 메시지가 사라지는 문제가 있었습니다.
--
-- V1.4는 반드시:
-- 1) chat:addTemplate 등록
-- 2) 신규 템플릿이면 100ms 대기
-- 3) chat:addMessage + templateId 출력
-- 순서로 처리합니다.

RegisterNetEvent('cookie_chat:client:addImageTitleMessage', function(data)
    if type(data) ~= 'table' then return end

    local ok, id, image = validTemplateData({
        id = data.titleId,
        image = data.image,
    })

    if not ok then
        -- 이미지가 깨져도 채팅 내용 자체는 절대 사라지지 않게 기본 COOKIE 템플릿으로 출력
        TriggerEvent('chat:addMessage', {
            templateId = 'cookie_msg',
            color = false,
            args = {
                tostring(data.wrapClass or ''),
                tostring(data.gobun or '-'),
                tostring(data.labelClass or ''),
                tostring(data.label or ''),
                tostring(data.nick or ''),
                tostring(data.body or ''),
                '', '#FFE08A', '#251B0B', '',
                tostring(data.labelBg or '#FFB800'),
                tostring(data.labelText or '#1A1A1A')
            }
        })
        return
    end

    CreateThread(function()
        local wasRegistered = registered[id] == true

        if not wasRegistered then
            registerTemplate({ id = id, image = image })
            Wait(100)
        end

        TriggerEvent('chat:addMessage', {
            templateId = ('cookie_msg_title_%d'):format(id),
            color = false,
            args = {
                tostring(data.wrapClass or ''),
                tostring(data.gobun or '-'),
                tostring(data.labelClass or ''),
                tostring(data.label or ''),
                tostring(data.nick or ''),
                tostring(data.body or ''),
                '', '#FFE08A', '#251B0B', '',
                tostring(data.labelBg or '#FFB800'),
                tostring(data.labelText or '#1A1A1A')
            }
        })
    end)
end)

CreateThread(function()
    Wait(300)
    registerBaseTemplates()
end)
