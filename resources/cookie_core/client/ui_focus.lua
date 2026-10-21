print('^2[cookie_core]^7 UI FOCUS V0.7.0 ownership coordinator active')

local owner = nil
local ownerResource = nil
local acquiredAt = 0
local ownerKeepInput = false

local function normalizeOwner(name)
    name = tostring(name or '')
    if name == '' then name = 'unknown' end
    return name
end

local function resourceFromOwner(name)
    name = normalizeOwner(name)
    return name:match('^([^:]+)') or name
end

local function ownerStillAlive()
    if not ownerResource or ownerResource == '' then return false end
    if ownerResource == GetCurrentResourceName() then return true end
    local state = GetResourceState(ownerResource)
    return state == 'started' or state == 'starting'
end

local function clearOwnerState()
    owner = nil
    ownerResource = nil
    acquiredAt = 0
    ownerKeepInput = false
end

-- IMPORTANT:
-- SetNuiFocus must be called by the resource that actually owns the NUI page.
-- cookie_core only arbitrates ownership so one COOKIE UI does not overlap another.
exports('Acquire', function(name, keep)
    name = normalizeOwner(name)

    if owner and not ownerStillAlive() then
        clearOwnerState()
    end

    local previousOwner = owner
    if owner and owner ~= name then
        return false, owner, previousOwner
    end

    owner = name
    ownerResource = resourceFromOwner(name)
    acquiredAt = GetGameTimer()
    ownerKeepInput = keep == true
    return true, owner, previousOwner
end)

exports('Release', function(name)
    name = normalizeOwner(name)
    if owner and owner ~= name then
        return false, owner
    end
    clearOwnerState()
    return true, nil
end)

exports('ForceRelease', function()
    clearOwnerState()
    return true
end)

exports('Refresh', function(name)
    name = normalizeOwner(name)
    return owner == name, owner
end)

exports('IsOwner', function(name)
    return owner ~= nil and owner == normalizeOwner(name)
end)

exports('GetOwner', function()
    return owner, acquiredAt, ownerKeepInput
end)

RegisterNetEvent('cookie_ui:client:forceRelease', function()
    clearOwnerState()
end)

RegisterCommand('cookieuifix', function()
    clearOwnerState()
    TriggerEvent('cookie_admin:client:notify', 'UI 포커스 소유 상태를 초기화했습니다.', false)
end, false)

RegisterCommand('cookieuistatus', function()
    print(('^3[cookie_core]^7 UI owner=%s resource=%s keep=%s age=%sms')
        :format(tostring(owner), tostring(ownerResource), tostring(ownerKeepInput),
            owner and (GetGameTimer() - acquiredAt) or 0))
end, false)

local function resourceStopped(res)
    if ownerResource and res == ownerResource then
        clearOwnerState()
    end
end
AddEventHandler('onClientResourceStop', resourceStopped)
AddEventHandler('onResourceStop', resourceStopped)
