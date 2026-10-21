

RegisterNetEvent('cookie_skill:client:levelUp', function(p)
    if type(p) ~= 'table' then return end

    local label = p.label or '숙련도'
    local lv = math.floor(tonumber(p.level) or 1)

    TriggerEvent('cookie_admin:client:notifyBottom',
        ('%s 숙련도가 LV%d 이 되었습니다'):format(label, lv), false)

    local b = p.bonus
    if type(b) == 'table' and b.fare then
        TriggerEvent('cookie_admin:client:notify',
            ('요금 %.2f배, 팁 %d%%'):format(b.fare, math.floor((b.tip or 0) * 100)), false)
    end

    PlaySoundFrontend(-1, 'RANK_UP', 'HUD_AWARDS', true)
end)
