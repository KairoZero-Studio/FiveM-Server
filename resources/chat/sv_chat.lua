RegisterServerEvent('chat:init')
RegisterServerEvent('chat:addTemplate')
RegisterServerEvent('chat:addMessage')
RegisterServerEvent('chat:addSuggestion')
RegisterServerEvent('chat:removeSuggestion')
RegisterServerEvent('_chat:messageEntered')
RegisterServerEvent('chat:clear')
RegisterServerEvent('__cfx_internal:commandFallback')

RegisterNetEvent('playerJoining')

exports('addMessage', function(target, message)
    if not message then
        message = target
        target = -1
    end

    if not target or not message then return end

    TriggerClientEvent('chat:addMessage', target, message)
end)

local hooks = {}
local hookIdx = 1

exports('registerMessageHook', function(hook)
    local resource = GetInvokingResource()
    hooks[hookIdx + 1] = {
        fn = hook,
        resource = resource
    }

    hookIdx = hookIdx + 1
end)

local modes = {}

local function getMatchingPlayers(seObject)
    local players = GetPlayers()
    local retval = {}

    for _, v in ipairs(players) do
        if IsPlayerAceAllowed(v, seObject) then
            retval[#retval + 1] = v
        end
    end

    return retval
end

local function modeAllowedForPlayer(modeData, player)
    if not modeData then return false end

    if modeData.seObject and not IsPlayerAceAllowed(player, modeData.seObject) then
        return false
    end

    if type(modeData.canUse) == 'function' then
        local ok, allowed = pcall(modeData.canUse, tonumber(player) or player)
        if not ok or allowed ~= true then
            return false
        end
    end

    return true
end

local function modeClientObject(modeData)
    return {
        name = modeData.name,
        displayName = modeData.displayName,
        color = modeData.color or '#fff',
        isChannel = modeData.isChannel,
        isGlobal = modeData.isGlobal,
    }
end

exports('registerMode', function(modeData)
    if not modeData.name or not modeData.displayName or not modeData.cb then
        return false
    end

    local resource = GetInvokingResource()

    modes[modeData.name] = modeData
    modes[modeData.name].resource = resource

    local clObj = modeClientObject(modeData)

    -- V13.9.5: 채널마다 플레이어별 접근 권한을 지원합니다.
    -- 권한 없는 채널은 NUI에 아예 전달하지 않아 TAB 순환에서도 자동 제외됩니다.
    for _, v in ipairs(GetPlayers()) do
        if modeAllowedForPlayer(modeData, v) then
            TriggerClientEvent('chat:addMode', v, clObj)
        else
            TriggerClientEvent('chat:removeMode', v, modeData.name)
        end
    end

    return true
end)

exports('refreshModeForPlayer', function(player, modeName)
    player = tonumber(player)
    local modeData = modes[tostring(modeName or '')]
    if not player or not modeData then return false end

    if modeAllowedForPlayer(modeData, player) then
        TriggerClientEvent('chat:addMode', player, modeClientObject(modeData))
        return true
    end

    TriggerClientEvent('chat:removeMode', player, modeData.name)
    return false
end)

local function unregisterHooks(resource)
    local toRemove = {}

    for k, v in pairs(hooks) do
        if v.resource == resource then
            table.insert(toRemove, k)
        end
    end

    for _, v in ipairs(toRemove) do
        hooks[v] = nil
    end

    toRemove = {}

    for k, v in pairs(modes) do
        if v.resource == resource then
            table.insert(toRemove, k)
        end
    end

    for _, v in ipairs(toRemove) do
        TriggerClientEvent('chat:removeMode', -1, {
            name = v
        })

        modes[v] = nil
    end
end

local function routeMessage(source, author, message, mode, fromConsole)
    if source >= 1 then
        author = GetPlayerName(source)
    end

    local outMessage = {
        color = { 255, 255, 255 },
        multiline = true,
        args = { message },
        mode = mode
    }

    if author ~= "" then
        outMessage.args = { author, message }
    end

    if mode and modes[mode] then
        local modeData = modes[mode]

        if not modeAllowedForPlayer(modeData, source) then
            return
        end
    end

    local messageCanceled = false
    local routingTarget = -1

    local hookRef = {
        updateMessage = function(t)

            for k, v in pairs(t) do
                if k == 'template' then
                    outMessage['template'] = v:gsub('%{%}', outMessage['template'] or '@default')
                elseif k == 'params' then
                    if not outMessage.params then
                        outMessage.params = {}
                    end

                    for pk, pv in pairs(v) do
                        outMessage.params[pk] = pv
                    end
                else
                    outMessage[k] = v
                end
            end
        end,

        cancel = function()
            messageCanceled = true
        end,

        setSeObject = function(object)
            routingTarget = getMatchingPlayers(object)
        end,

        setRouting = function(target)
            routingTarget = target
        end
    }

    for _, hook in pairs(hooks) do
        if hook.fn then
            hook.fn(source, outMessage, hookRef)
        end
    end

    if modes[mode] then
        local m = modes[mode]

        m.cb(source, outMessage, hookRef)
    end

    if messageCanceled then
        return
    end

    TriggerEvent('chatMessage', source, #outMessage.args > 1 and outMessage.args[1] or '', outMessage.args[#outMessage.args])

    if not WasEventCanceled() then
        if type(routingTarget) ~= 'table' then
            TriggerClientEvent('chat:addMessage', routingTarget, outMessage)
        else
            for _, id in ipairs(routingTarget) do
                TriggerClientEvent('chat:addMessage', id, outMessage)
            end
        end
    end

    if not fromConsole then

    end
end

AddEventHandler('_chat:messageEntered', function(author, color, message, mode)
    if not message or not author then
        return
    end

    local source = source

    routeMessage(source, author, message, mode)
end)

AddEventHandler('__cfx_internal:commandFallback', function(command)
    local name = GetPlayerName(source)

    routeMessage(source, name, '/' .. command, nil, true)

    CancelEvent()
end)

AddEventHandler('playerJoining', function()
    if GetConvarInt('chat_showJoins', 1) == 0 then
        return
    end

    TriggerClientEvent('chatMessage', -1, '', { 255, 255, 255 }, '^2* ' .. GetPlayerName(source) .. ' joined.')
end)

AddEventHandler('playerDropped', function(reason)
    if GetConvarInt('chat_showQuits', 1) == 0 then
        return
    end

    TriggerClientEvent('chatMessage', -1, '', { 255, 255, 255 }, '^2* ' .. GetPlayerName(source) ..' left (' .. reason .. ')')
end)

RegisterCommand('say', function(source, args, rawCommand)
    routeMessage(source, (source == 0) and 'console' or GetPlayerName(source), rawCommand:sub(5), nil, true)
end)

local function refreshCommands(player)
    if GetRegisteredCommands then
        local registeredCommands = GetRegisteredCommands()

        local suggestions = {}

        for _, command in ipairs(registeredCommands) do
            if IsPlayerAceAllowed(player, ('command.%s'):format(command.name)) then
                table.insert(suggestions, {
                    name = '/' .. command.name,
                    help = ''
                })
            end
        end

        TriggerClientEvent('chat:addSuggestions', player, suggestions)
    end
end

AddEventHandler('chat:init', function()
    local source = source
    refreshCommands(source)

    for _, modeData in pairs(modes) do
        if modeAllowedForPlayer(modeData, source) then
            TriggerClientEvent('chat:addMode', source, modeClientObject(modeData))
        else
            TriggerClientEvent('chat:removeMode', source, modeData.name)
        end
    end
end)

AddEventHandler('onServerResourceStart', function(resName)
    Wait(500)

    for _, player in ipairs(GetPlayers()) do
        refreshCommands(player)
    end
end)

AddEventHandler('onResourceStop', function(resName)
    unregisterHooks(resName)
end)

local function systemBroadcast(text)
    if type(text) ~= 'string' or text == '' then return end
    TriggerClientEvent('chat:addMessage', -1, { templateId = 'cookie_system', args = { text } })
end
AddEventHandler('cookie_chat:system', function(text) systemBroadcast(text) end)
exports('systemBroadcast', systemBroadcast)

print('^2[chat]^7 COOKIE CHAT PER-PLAYER MODE ACCESS V13.9.5 ready')
