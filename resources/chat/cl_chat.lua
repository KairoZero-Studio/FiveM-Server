local isRDR = not TerraingridActivate and true or false

local chatInputActive = false
local chatInputActivating = false
local chatLoaded = false
local currentResourceName = GetCurrentResourceName()

local function managedUiOwner()
  if GetResourceState('cookie_core') ~= 'started' then return nil end
  local ok, owner = pcall(function()
    return exports.cookie_core:GetOwner()
  end)
  if ok then return owner end
  return nil
end

local function setChatNuiFocus(on)
  local owner = managedUiOwner()
  -- ESC/F3/PHONE/SELECT 등 COOKIE UI가 포커스를 가진 동안
  -- chat이 SetNuiFocus(false,false)로 커서를 지우지 못하게 한다.
  if owner and owner ~= currentResourceName then
    return false
  end
  SetNuiFocus(on == true, on == true)
  return true
end

local function UsePreSecurityBehavior()

  return GetConvar('sysresource_chat_disableOriginSecurityChecks', 'true') == 'true'
end

RegisterNetEvent('chatMessage')
RegisterNetEvent('chat:addTemplate')
RegisterNetEvent('chat:addMessage')
RegisterNetEvent('chat:addSuggestion')
RegisterNetEvent('chat:addSuggestions')
RegisterNetEvent('chat:addMode')
RegisterNetEvent('chat:removeMode')
RegisterNetEvent('chat:removeSuggestion')
RegisterNetEvent('chat:clear')

RegisterNetEvent('__cfx_internal:serverPrint')

RegisterNetEvent('_chat:messageEntered')

AddEventHandler('chatMessage', function(author, color, text)
  local args = { text }
  if author ~= "" then
    table.insert(args, 1, author)
  end
  SendNUIMessage({
    type = 'ON_MESSAGE',
    message = {
      color = color,
      multiline = true,
      args = args
    }
  })
end)

AddEventHandler('__cfx_internal:serverPrint', function(msg)

  SendNUIMessage({
    type = 'ON_MESSAGE',
    message = {
      templateId = 'print',
      multiline = true,
      args = { msg },
      mode = '_global'
    }
  })
end)

local addMessage = function(message)
  if type(message) == 'string' then
    message = {
      args = { message }
    }
  end

  SendNUIMessage({
    type = 'ON_MESSAGE',
    message = message
  })
end

exports('addMessage', addMessage)
AddEventHandler('chat:addMessage', addMessage)

local addSuggestion = function(name, help, params)
  SendNUIMessage({
    type = 'ON_SUGGESTION_ADD',
    suggestion = {
      name = name,
      help = help,
      params = params or nil
    }
  })
end

exports('addSuggestion', addSuggestion)
AddEventHandler('chat:addSuggestion', addSuggestion)

AddEventHandler('chat:addSuggestions', function(suggestions)
  SendNUIMessage({
    type = 'ON_SUGGESTION_ADD',
    suggestion = suggestions
  })
end)

AddEventHandler('chat:removeSuggestion', function(name)
  SendNUIMessage({
    type = 'ON_SUGGESTION_REMOVE',
    name = name
  })
end)

AddEventHandler('chat:addMode', function(mode)
  SendNUIMessage({
    type = 'ON_MODE_ADD',
    mode = mode
  })
end)

AddEventHandler('chat:removeMode', function(name)
  SendNUIMessage({
    type = 'ON_MODE_REMOVE',
    name = name
  })
end)

AddEventHandler('chat:addTemplate', function(id, html)
  SendNUIMessage({
    type = 'ON_TEMPLATE_ADD',
    template = {
      id = id,
      html = html
    }
  })
end)

AddEventHandler('chat:clear', function(name)
  SendNUIMessage({
    type = 'ON_CLEAR'
  })
end)

RegisterRawNuiCallback('chatResult', function(requestData, cb)
  local resource = requestData.resource
  local securityDisabled = UsePreSecurityBehavior();

  if resource == nil and not securityDisabled then
    return
  end

  chatInputActive = false
  setChatNuiFocus(false)

  local data = json.decode(requestData.body)

  if not data.canceled then
    if data.message:sub(1, 1) == '/' then

      if resource == currentResourceName or securityDisabled then
        ExecuteCommand(data.message:sub(2))
      end
    else
      local id = PlayerId()
      local r, g, b = 0, 0x99, 255
      TriggerServerEvent('_chat:messageEntered', GetPlayerName(id), { r, g, b }, data.message, data.mode)
    end
  end

  cb({ body = 'ok' })
end)

local function refreshCommands()
  if GetRegisteredCommands then
    local registeredCommands = GetRegisteredCommands()

    local suggestions = {}

    for _, command in ipairs(registeredCommands) do
        if IsAceAllowed(('command.%s'):format(command.name)) and command.name ~= 'toggleChat' then
            table.insert(suggestions, {
                name = '/' .. command.name,
                help = ''
            })
        end
    end

    TriggerEvent('chat:addSuggestions', suggestions)
  end
end

local function refreshThemes()
  local themes = {}

  for resIdx = 0, GetNumResources() - 1 do
    local resource = GetResourceByFindIndex(resIdx)

    if GetResourceState(resource) == 'started' then
      local numThemes = GetNumResourceMetadata(resource, 'chat_theme')

      if numThemes > 0 then
        local themeName = GetResourceMetadata(resource, 'chat_theme')
        local themeData = json.decode(GetResourceMetadata(resource, 'chat_theme_extra') or 'null')

        if themeName and themeData then
          themeData.baseUrl = 'nui://' .. resource .. '/'
          themes[themeName] = themeData
        end
      end
    end
  end

  SendNUIMessage({
    type = 'ON_UPDATE_THEMES',
    themes = themes
  })
end

AddEventHandler('onClientResourceStart', function(resName)
  Wait(500)

  refreshCommands()
  refreshThemes()
end)

AddEventHandler('onClientResourceStop', function(resName)
  Wait(500)

  refreshCommands()
  refreshThemes()
end)

RegisterNUICallback('loaded', function(data, cb)
  TriggerServerEvent('chat:init')

  refreshCommands()
  refreshThemes()

  chatLoaded = true
  addSuggestion('/toggleChat', 'set Chat state', {
    { name = "state", help = "whenactive hidden visible" },
  })
  cb('ok')
end)

local CHAT_HIDE_STATES = {
  SHOW_WHEN_ACTIVE = 0,
  ALWAYS_SHOW = 1,
  ALWAYS_HIDE = 2
}

local kvpEntry = GetResourceKvpString('hideState')
local chatHideState = kvpEntry and tonumber(kvpEntry) or CHAT_HIDE_STATES.SHOW_WHEN_ACTIVE
local isFirstHide = true

local externalHide = false
if RegisterKeyMapping then
	RegisterKeyMapping('toggleChat', 'Toggle chat', 'keyboard', 'l')
end

RegisterCommand('toggleChat', function(source, args, rawCommand)
  if not args[1] then
    if chatHideState == CHAT_HIDE_STATES.SHOW_WHEN_ACTIVE then
      chatHideState = CHAT_HIDE_STATES.ALWAYS_SHOW
    elseif chatHideState == CHAT_HIDE_STATES.ALWAYS_SHOW then
      chatHideState = CHAT_HIDE_STATES.ALWAYS_HIDE
    elseif chatHideState == CHAT_HIDE_STATES.ALWAYS_HIDE then
      chatHideState = CHAT_HIDE_STATES.SHOW_WHEN_ACTIVE
    end
  else
    if args[1] == "visible" then
      chatHideState = CHAT_HIDE_STATES.ALWAYS_SHOW
    elseif args[1] == "hidden" then
      chatHideState = CHAT_HIDE_STATES.ALWAYS_HIDE
    elseif args[1] == "whenactive" then
      chatHideState = CHAT_HIDE_STATES.SHOW_WHEN_ACTIVE
    end
  end
  isFirstHide = false
  SetResourceKvp('hideState', tostring(chatHideState))
end, false)

local function isPlayerLoggedIn()
  if LocalPlayer.state.isLoggedIn then return true end
  local ok, pd = pcall(function() return exports.qbx_core:GetPlayerData() end)
  return ok and pd ~= nil and pd.citizenid ~= nil
end

Citizen.CreateThread(function()
  SetTextChatEnabled(false)
  setChatNuiFocus(false)

  local lastChatHideState = -1
  local origChatHideState = -1
  local lastHardHide = nil
  local input = isRDR and `INPUT_MP_TEXT_CHAT_ALL` or 245

  while true do
    Wait(0)

    if not chatInputActive and not managedUiOwner() then
      if IsControlPressed(0, input) then
        chatInputActive = true
        chatInputActivating = true

        SendNUIMessage({
          type = 'ON_OPEN'
        })
      end
    end

    if chatInputActivating then
      if not IsControlPressed(0, input) then
        setChatNuiFocus(true)

        chatInputActivating = false
      end
    end

    if chatLoaded then

      local forceHide = IsScreenFadedOut() or IsPauseMenuActive() or (not isPlayerLoggedIn()) or externalHide
      local wasForceHide = false

      if forceHide ~= lastHardHide then
        lastHardHide = forceHide
        SendNUIMessage({ type = 'CK_HARD', on = forceHide })
      end

      if chatHideState ~= CHAT_HIDE_STATES.ALWAYS_HIDE then
        if forceHide then
          origChatHideState = chatHideState
          chatHideState = CHAT_HIDE_STATES.ALWAYS_HIDE
        end
      elseif not forceHide and origChatHideState ~= -1 then
        chatHideState = origChatHideState
        origChatHideState = -1
        wasForceHide = true
      end

      if chatHideState ~= lastChatHideState then
        lastChatHideState = chatHideState

        SendNUIMessage({
          type = 'ON_SCREEN_STATE_CHANGE',
          hideState = chatHideState,
          fromUserInteraction = not forceHide and not isFirstHide and not wasForceHide
        })

        isFirstHide = false
      end
    end
  end
end)

AddEventHandler('cookie_chat:escMode', function(on)
  SendNUIMessage({ type = 'ESC_MODE', on = on and true or false })
end)

AddEventHandler('cookie_chat:forceHide', function(on)
  externalHide = on and true or false
end)

RegisterNUICallback('requestOpen', function(_, cb)
  cb({ ok = true })
  setChatNuiFocus(true)
  SendNUIMessage({ type = 'ON_OPEN' })
end)

RegisterNUICallback('menuFocus', function(data, cb)
  cb({ ok = true })
  local on = data and data.on and true or false
  setChatNuiFocus(on)
end)

RegisterNUICallback('menuProfile', function(data, cb)
  cb({ ok = true })
  local nick = (data and data.nick) or '플레이어'
  TriggerEvent('chat:addMessage', {
    templateId = 'cookie_system',
    args = { ('%s 님의 프로필 정보는 준비 중입니다.'):format(nick) }
  })
end)

RegisterNUICallback('menuPay', function(data, cb)
  cb({ ok = true })
  local target = tonumber(data and data.src)
  local amount = tonumber(data and data.amount)
  if not target or not amount then return end
  TriggerServerEvent('cookie_chat:server:transfer', target, math.floor(amount))
end)
