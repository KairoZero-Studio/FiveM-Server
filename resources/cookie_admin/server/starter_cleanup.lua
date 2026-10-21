-- COOKIE SERVER V14.2.1
-- QBOX default starter item cleanup
-- Removes the stock qbx_core starter inventory items while preserving
-- COOKIE's own DB-based identity / phone / driver-license systems.

local BLOCKED_STARTER_ITEMS = {
    phone = true,
    id_card = true,
    driver_license = true,
}

local CLEANUP_LABEL = '[cookie_admin] DEFAULT STARTER ITEM CLEANUP'

local function decodeInventory(raw)
    if raw == nil or raw == '' then return nil end
    if type(raw) == 'table' then return raw end

    local ok, data = pcall(json.decode, raw)
    if not ok or type(data) ~= 'table' then return nil end
    return data
end

local function filterInventory(raw)
    local inventory = decodeInventory(raw)
    if not inventory then return nil, false, 0 end

    local filtered = {}
    local changed = false
    local removed = 0

    for _, slot in pairs(inventory) do
        if type(slot) == 'table' and slot.name then
            if BLOCKED_STARTER_ITEMS[slot.name] then
                removed = removed + (tonumber(slot.count) or 1)
                changed = true
            else
                filtered[#filtered + 1] = slot
            end
        end
    end

    if not changed then return nil, false, 0 end

    table.sort(filtered, function(a, b)
        return (tonumber(a.slot) or 0) < (tonumber(b.slot) or 0)
    end)

    return (#filtered > 0 and json.encode(filtered) or nil), true, removed
end

local function getCitizenId(src)
    local ok, player = pcall(function()
        return exports.qbx_core:GetPlayer(tonumber(src))
    end)

    if not ok or not player or not player.PlayerData then return nil end
    return player.PlayerData.citizenid
end

local function removeOnline(src)
    src = tonumber(src)
    if not src or GetPlayerPing(src) <= 0 then return 0 end
    if GetResourceState('ox_inventory') ~= 'started' then return 0 end

    local ok, items = pcall(function()
        return exports.ox_inventory:GetInventoryItems(src)
    end)
    if not ok or type(items) ~= 'table' then return 0 end

    local removed = 0

    -- Use the exact slot + metadata so unique ID/license cards are removed safely.
    for _, slot in pairs(items) do
        if type(slot) == 'table' and BLOCKED_STARTER_ITEMS[slot.name] then
            local count = math.max(tonumber(slot.count) or 1, 1)
            local success = false

            local callOk, ret = pcall(function()
                return exports.ox_inventory:RemoveItem(
                    src,
                    slot.name,
                    count,
                    slot.metadata,
                    tonumber(slot.slot),
                    true
                )
            end)

            success = callOk and ret == true

            -- Fallback for inventory forks that reject slot/metadata arguments.
            if not success then
                local fallbackOk, fallbackRet = pcall(function()
                    return exports.ox_inventory:RemoveItem(src, slot.name, count)
                end)
                success = fallbackOk and fallbackRet == true
            end

            if success then
                removed = removed + count
            end
        end
    end

    if removed > 0 then
        print(('%s online src=%s citizenid=%s removed=%s'):format(
            CLEANUP_LABEL,
            tostring(src),
            tostring(getCitizenId(src) or '-'),
            tostring(removed)
        ))
    end

    return removed
end

local function onlineCitizenIds()
    local set = {}
    for _, src in ipairs(GetPlayers()) do
        local cid = getCitizenId(src)
        if cid then set[cid] = true end
    end
    return set
end

local function purgeOfflineDatabase()
    local online = onlineCitizenIds()
    local rows = MySQL.query.await([[
        SELECT citizenid, inventory
        FROM players
        WHERE inventory IS NOT NULL AND inventory <> ''
    ]]) or {}

    local playersChanged = 0
    local itemsRemoved = 0

    for _, row in ipairs(rows) do
        -- Never rewrite an online player's persisted JSON while ox_inventory owns
        -- the live state. Online players are cleaned through the inventory export.
        if row.citizenid and not online[row.citizenid] then
            local newInventory, changed, removed = filterInventory(row.inventory)
            if changed then
                MySQL.update.await('UPDATE players SET inventory = ? WHERE citizenid = ?', {
                    newInventory,
                    row.citizenid,
                })
                playersChanged = playersChanged + 1
                itemsRemoved = itemsRemoved + removed
            end
        end
    end

    print(('%s DB complete · players=%s · items=%s · blocked=phone,id_card,driver_license'):format(
        CLEANUP_LABEL,
        tostring(playersChanged),
        tostring(itemsRemoved)
    ))
end

local function cleanPlayerAfterLoad(src)
    -- qbx_core creates the Player object first and gives starter items immediately
    -- afterwards for a brand-new character. Run on subsequent scheduler ticks so
    -- the stock starter grant is removed before the player can meaningfully use it.
    SetTimeout(0, function() removeOnline(src) end)
    SetTimeout(500, function() removeOnline(src) end)
    SetTimeout(2000, function() removeOnline(src) end)
end

AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    local src = source
    if player and player.PlayerData and player.PlayerData.source then
        src = player.PlayerData.source
    end
    cleanPlayerAfterLoad(src)
end)

-- Some resources only emit the later compatibility event. Keep this as an
-- additional safety net; repeated cleanup is harmless when nothing is present.
RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    cleanPlayerAfterLoad(source)
end)

MySQL.ready(function()
    CreateThread(function()
        Wait(1000)
        purgeOfflineDatabase()

        -- Also clean anyone already connected if cookie_admin is restarted live.
        for _, src in ipairs(GetPlayers()) do
            cleanPlayerAfterLoad(tonumber(src))
        end
    end)
end)
