local cooldown = {}
local workSession = {}
local ticketUseLock = {}

local function notify(src,msg,bad)
    TriggerClientEvent('cookie_admin:client:notify',src,tostring(msg or ''),bad==true)
end

local function cidOf(src)
    local p=exports.qbx_core:GetPlayer(src)
    return p and p.PlayerData and tostring(p.PlayerData.citizenid or '') or nil
end

local function detention(cid)
    if not cid then return nil end
    return MySQL.single.await([[
        SELECT id,charge,GREATEST(0,UNIX_TIMESTAMP(release_at)-UNIX_TIMESTAMP()) AS remain
        FROM cookie_police_detention_active
        WHERE citizenid=? AND active=1 AND release_at>NOW()
        ORDER BY id DESC LIMIT 1
    ]],{cid})
end

local function distance(a,b)
    local dx,dy,dz=a.x-b.x,a.y-b.y,a.z-b.z
    return math.sqrt(dx*dx+dy*dy+dz*dz)
end

local function playerCoords(src)
    local ped=GetPlayerPed(src)
    if not ped or ped==0 then return nil end
    return GetEntityCoords(ped)
end

local function inPrison(src)
    local p=playerCoords(src)
    if not p then return false end
    return distance(p,Config.PrisonCenter) <= (Config.PrisonRadius or 230.0)
end

local function nearAny(src,points,maxDistance)
    local p=playerCoords(src)
    if not p then return nil end
    for i,v in ipairs(points or {}) do
        if distance(p,v) <= maxDistance then return i end
    end
    return nil
end

lib.callback.register('cookie_prison:startWork',function(src)
    local cid=cidOf(src)
    local d=detention(cid)
    if not d or tonumber(d.remain or 0)<=0 then return {ok=false,message='현재 수감 중이 아닙니다.'} end
    if not inPrison(src) then return {ok=false,message='교도소 내부에서만 노역할 수 있습니다.'} end
    if not nearAny(src,Config.PickupPoints,3.0) then return {ok=false,message='박스 작업 지점 가까이에서 시작해주세요.'} end

    local dropCount=#(Config.DropPoints or {})
    if dropCount<1 then return {ok=false,message='교도소 적재 위치가 설정되지 않았습니다.'} end
    local dropIndex=math.random(1,dropCount)
    workSession[src]={dropIndex=dropIndex,startedAt=os.time(),detentionId=tonumber(d.id)}
    return {ok=true,dropIndex=dropIndex}
end)

RegisterNetEvent('cookie_prison:server:cancelWork',function()
    workSession[source]=nil
end)

RegisterNetEvent('cookie_prison:server:completeWork',function(dropIndex)
    local src=source
    local now=os.time()
    if (cooldown[src] or 0)>now then return end

    local session=workSession[src]
    if not session then return notify(src,'진행 중인 교도소 노역이 없습니다.',true) end
    dropIndex=tonumber(dropIndex)
    if not dropIndex or dropIndex~=tonumber(session.dropIndex) then
        workSession[src]=nil
        return notify(src,'노역 적재 위치 정보가 올바르지 않습니다.',true)
    end
    if now-(tonumber(session.startedAt) or now)<(Config.MinimumCarrySeconds or 4) then
        return notify(src,'박스를 실제 적재 위치까지 운반해주세요.',true)
    end
    if now-(tonumber(session.startedAt) or now)>(Config.WorkSessionTimeoutSeconds or 300) then
        workSession[src]=nil
        return notify(src,'노역 시간이 초과되었습니다. 다시 시작해주세요.',true)
    end

    local target=(Config.DropPoints or {})[dropIndex]
    local pc=playerCoords(src)
    if not target or not pc or distance(pc,target)>3.5 then
        return notify(src,'지정된 적재 위치에서 박스를 내려놓으세요.',true)
    end

    local cid=cidOf(src)
    local d=detention(cid)
    if not d or tonumber(d.remain or 0)<=0 or tonumber(d.id)~=tonumber(session.detentionId) then
        workSession[src]=nil
        return notify(src,'현재 수감 상태가 변경되어 노역 보상을 받을 수 없습니다.',true)
    end
    if not inPrison(src) then
        workSession[src]=nil
        return notify(src,'교도소 내부에서만 노역 보상을 받을 수 있습니다.',true)
    end

    local count=math.max(1,math.floor(tonumber(Config.WorkRewardTickets) or 1))
    local item=tostring(Config.ReleaseTicketItem or 'prison_release_ticket')
    local ok,ret=pcall(function()
        return exports.ox_inventory:AddItem(src,item,count)
    end)
    if not ok or ret~=true then
        workSession[src]=nil
        return notify(src,('출소티켓 지급 실패: 인벤토리 공간 또는 ox_inventory의 %s 등록 상태를 확인한 뒤 다시 노역해주세요.'):format(item),true)
    end

    cooldown[src]=now+(Config.WorkCooldownSeconds or 8)
    workSession[src]=nil
    notify(src,('박스 운반 완료 · 출소티켓 %d장 지급'):format(count),false)
end)

RegisterNetEvent('cookie_prison:server:useReleaseTicket',function()
    local src=source
    if ticketUseLock[src] then return end
    ticketUseLock[src]=true

    local function done() ticketUseLock[src]=nil end
    local cid=cidOf(src)
    local d=detention(cid)
    if not d or tonumber(d.remain or 0)<=0 then
        done(); return notify(src,'현재 수감 중이 아니라 출소티켓을 사용할 수 없습니다.',true)
    end
    if not inPrison(src) then
        done(); return notify(src,'교도소 내부에서만 출소티켓을 사용할 수 있습니다.',true)
    end

    local item=tostring(Config.ReleaseTicketItem or 'prison_release_ticket')
    local count=exports.ox_inventory:GetItemCount(src,item)
    if (tonumber(count) or 0)<1 then done(); return notify(src,'출소티켓이 없습니다.',true) end

    local sec=math.max(1,math.floor(tonumber(Config.SecondsPerTicket) or 60))
    local current=tonumber(d.remain) or 0
    local newRemain=math.max(0,current-sec)

    local removed=exports.ox_inventory:RemoveItem(src,item,1)
    if removed~=true then done(); return notify(src,'출소티켓 사용에 실패했습니다.',true) end

    local dbOk=false
    if newRemain<=0 then
        local changed=MySQL.update.await([[
            UPDATE cookie_police_detention_active
            SET active=0,released_at=NOW(),released_by='PRISON_TICKET'
            WHERE id=? AND active=1
        ]],{d.id})
        dbOk=changed and changed>0
        if dbOk then
            workSession[src]=nil
            TriggerClientEvent('cookie_police:client:setDetained',src,0,'출소티켓 사용',false)
            notify(src,'출소티켓을 사용해 남은 형기를 모두 줄였습니다. 출소합니다.',false)
        end
    else
        local changed=MySQL.update.await(([[
            UPDATE cookie_police_detention_active
            SET release_at=DATE_SUB(release_at,INTERVAL %d SECOND)
            WHERE id=? AND active=1
        ]]):format(sec),{d.id})
        dbOk=changed and changed>0
        if dbOk then
            TriggerClientEvent('cookie_police:client:setDetained',src,newRemain,d.charge,false)
            notify(src,('출소티켓 1장 사용 · 남은 형기 %d분 %d초'):format(math.floor(newRemain/60),newRemain%60),false)
        end
    end

    if not dbOk then
        pcall(function() exports.ox_inventory:AddItem(src,item,1) end)
        notify(src,'형기 감소 저장에 실패해 출소티켓을 돌려드렸습니다.',true)
    end
    done()
end)

AddEventHandler('playerDropped',function()
    cooldown[source]=nil
    workSession[source]=nil
    ticketUseLock[source]=nil
end)

print('^2[cookie_prison]^7 labor + release ticket V1.1.0 ready')
