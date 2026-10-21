local savedAppearance = nil

local pandaCandidates = {
    'panda', 'Panda', 'PANDA',
    'a_c_panda', 'a_c_panda_01',
    'ig_panda', 'mp_panda', 's_m_panda',
    'panda_01', 'cookie_panda', 'pandaped',
}

RegisterCommand('pandafind', function()

    for _, name in ipairs(pandaCandidates) do
        local hash = joaat(name)
        if IsModelInCdimage(hash) then

        else

        end
    end

end, false)

local function applySkin(modelName)

    if not savedAppearance then
        savedAppearance = exports['illenium-appearance']:getPedAppearance(PlayerPedId())
    end

    local modelHash = joaat(modelName)
    if not IsModelInCdimage(modelHash) then

        return false
    end

    RequestModel(modelHash)
    local timeout = 0
    while not HasModelLoaded(modelHash) and timeout < 100 do
        Wait(50)
        timeout = timeout + 1
    end

    if HasModelLoaded(modelHash) then
        SetPlayerModel(PlayerId(), modelHash)
        SetModelAsNoLongerNeeded(modelHash)

        return true
    end

    return false
end

local function restoreSkin()
    if savedAppearance then
        exports['illenium-appearance']:setPlayerAppearance(savedAppearance)
        savedAppearance = nil

    end
end

exports('applySkin', applySkin)
exports('restoreSkin', restoreSkin)

RegisterCommand('pandaon', function(_, args)
    applySkin(args[1] or 'a_f_y_tourist_01')
end, false)
RegisterCommand('pandaoff', function()
    restoreSkin()
end, false)
