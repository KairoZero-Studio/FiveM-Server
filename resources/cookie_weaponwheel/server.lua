

local ITEMS = exports.ox_inventory:Items()

lib.callback.register('cookie_weaponwheel:getWeapons', function(source)
    local inv = exports.ox_inventory:GetInventoryItems(source)
    if not inv then return {} end

    local out = {}
    for _, it in pairs(inv) do
        if it and it.name and it.name:sub(1, 7) == 'WEAPON_' then
            local def = ITEMS[it.name]
            out[#out + 1] = {
                slot = it.slot,
                name = it.name,
                label = (def and def.label) or it.name,
                ammo = it.metadata and it.metadata.ammo or nil,
                durability = it.metadata and it.metadata.durability or nil,
            }
        end
    end
    table.sort(out, function(a, b) return a.slot < b.slot end)
    return out
end)
