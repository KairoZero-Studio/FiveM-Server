local hooksInstalled = false
local hookIds = {}

local function rememberHook(id)
    if id then
        hookIds[#hookIds + 1] = id
    end
end

local function installTrunkBlock()
    if hooksInstalled then return true end

    if GetResourceState('ox_inventory') ~= 'started' then
        return false
    end

    -- 공식 ox_inventory 방식:
    -- trunkXXXXXXXX 형태의 inventory id 자체를 필터링해서 열기 차단.
    local ok1, hook1 = pcall(function()
        return exports.ox_inventory:registerHook('openInventory', function(payload)
            return false
        end, {
            inventoryFilter = {
                '^trunk[%w]+',
                '^trunk[%W%w]+'
            }
        })
    end)

    if not ok1 then
        print(('^1[cookie_vehicleui]^7 trunk inventoryFilter hook failed: %s'):format(tostring(hook1)))
        return false
    end

    rememberHook(hook1)

    -- inventoryType까지 이중 차단.
    local ok2, hook2 = pcall(function()
        return exports.ox_inventory:registerHook('openInventory', function(payload)
            if payload and tostring(payload.inventoryType or ''):lower() == 'trunk' then
                return false
            end
        end)
    end)

    if ok2 then
        rememberHook(hook2)
    end

    -- 혹시 우회해서 열려도 trunk inventory와 아이템 이동 금지.
    local ok3, hook3 = pcall(function()
        return exports.ox_inventory:registerHook('swapItems', function(payload)
            if not payload then return end

            local fromType = tostring(payload.fromType or ''):lower()
            local toType = tostring(payload.toType or ''):lower()

            local fromInventory = tostring(payload.fromInventory or ''):lower()
            local toInventory = tostring(payload.toInventory or ''):lower()

            if fromType == 'trunk'
                or toType == 'trunk'
                or fromInventory:match('^trunk')
                or toInventory:match('^trunk')
            then
                return false
            end
        end, {
            inventoryFilter = {
                '^trunk[%w]+',
                '^trunk[%W%w]+'
            }
        })
    end)

    if ok3 then
        rememberHook(hook3)
    end

    hooksInstalled = true

    print('^2[cookie_vehicleui]^7 V2.5 HARD TRUNK BLOCK ACTIVE')
    print('^2[cookie_vehicleui]^7 Vehicle trunk inventory cannot be opened or used.')

    return true
end

CreateThread(function()
    while not installTrunkBlock() do
        Wait(1000)
    end
end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= 'ox_inventory' then return end

    hooksInstalled = false
    hookIds = {}

    CreateThread(function()
        Wait(1000)
        installTrunkBlock()
    end)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if GetResourceState('ox_inventory') ~= 'started' then return end

    for i = 1, #hookIds do
        pcall(function()
            exports.ox_inventory:removeHooks(hookIds[i])
        end)
    end
end)
