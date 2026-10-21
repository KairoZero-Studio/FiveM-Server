local localCrimeCuffed = false

local function notify(msg, err)
    if lib and lib.notify then
        lib.notify({ title='COOKIE 팩션', description=tostring(msg or ''), type=err and 'error' or 'inform' })
    else
        TriggerEvent('chat:addMessage', { args={ 'COOKIE', tostring(msg or '') } })
    end
end

local function awaitCb(name, ...)
    local args={...}
    local ok,res=pcall(function()
        return lib.callback.await(name,false,table.unpack(args))
    end)
    if not ok then
        print(('[cookie_faction_recovery] callback %s failed: %s'):format(tostring(name),tostring(res)))
        return nil
    end
    return res
end

local function profile()
    return awaitCb('cookie_faction_recovery:profile')
end

local function nearestVehicle(maxDist)
    local ped=PlayerPedId()
    local pos=GetEntityCoords(ped)
    local best,bestDist=nil,maxDist or 6.0
    for _,veh in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(veh) then
            local d=#(pos-GetEntityCoords(veh))
            if d<=bestDist then best,bestDist=veh,d end
        end
    end
    return best
end

local function closestPlayer(maxDist)
    local pos=GetEntityCoords(PlayerPedId())
    local best,bestDist=nil,maxDist or 3.0
    for _,p in ipairs(GetActivePlayers()) do
        if p~=PlayerId() then
            local ped=GetPlayerPed(p)
            if DoesEntityExist(ped) then
                local d=#(pos-GetEntityCoords(ped))
                if d<=bestDist then
                    bestDist=d
                    best=GetPlayerServerId(p)
                end
            end
        end
    end
    return best
end

local openTowMenu

local function openAccount(p)
    local data=awaitCb('cookie_faction_recovery:accountOverview')
    if not data or data.ok==false then
        return notify((data and data.message) or '공동계좌 정보를 불러오지 못했습니다.',true)
    end

    local opts={
        {
            title=('공동계좌 %d원'):format(tonumber(data.balance) or 0),
            description=('내 은행 잔액 %d원'):format(tonumber(data.bank) or 0),
            icon='wallet', disabled=true
        },
        {
            title='공동계좌 입금',
            description='내 은행에서 팩션 공동계좌로 직접 입금합니다.',
            icon='arrow-down',
            onSelect=function()
                local input=lib.inputDialog('공동계좌 입금',{
                    {type='number',label='입금 금액',required=true,min=1},
                    {type='input',label='메모',placeholder='판매 정산 등'}
                })
                if not input then return end
                local r=awaitCb('cookie_faction_recovery:deposit',{amount=tonumber(input[1]),reason=tostring(input[2] or '')})
                notify((r and r.message) or '입금 실패',not (r and r.ok))
            end
        }
    }

    if data.canWithdraw then
        opts[#opts+1]={
            title='공동계좌 출금',
            description='간부/대표 권한으로 공동계좌에서 출금합니다.',
            icon='arrow-up',
            onSelect=function()
                local input=lib.inputDialog('공동계좌 출금',{
                    {type='number',label='출금 금액',required=true,min=1},
                    {type='input',label='출금 사유',required=true}
                })
                if not input then return end
                local r=awaitCb('cookie_faction_recovery:withdraw',{amount=tonumber(input[1]),reason=tostring(input[2] or '')})
                notify((r and r.message) or '출금 실패',not (r and r.ok))
            end
        }
    end

    for _,row in ipairs(data.logs or {}) do
        local d=tonumber(row.delta) or 0
        opts[#opts+1]={
            title=((d>=0) and '+' or '')..tostring(d)..'원',
            description=('%s · 잔액 %s원'):format(tostring(row.reason or row.category or '-'),tostring(row.balance_after or 0)),
            disabled=true
        }
    end

    lib.registerContext({id='cookie_faction_recovery_account',title=(p.name or '팩션')..' 공동계좌',options=opts})
    lib.showContext('cookie_faction_recovery_account')
end

local function towImpound()
    local veh=nearestVehicle(6.0)
    if not veh then return notify('근처 차량을 찾지 못했습니다.',true) end
    local plate=GetVehicleNumberPlateText(veh)
    local input=lib.inputDialog('차량 압류',{
        {type='input',label='번호판',default=plate,disabled=true},
        {type='input',label='압류 사유',required=true},
        {type='number',label='압류 비용',default=0,min=0,required=true}
    })
    if not input then return end
    local r=awaitCb('cookie_faction_recovery:towImpound',{
        netId=NetworkGetNetworkIdFromEntity(veh),
        plate=plate,
        reason=tostring(input[2] or ''),
        fee=tonumber(input[3]) or 0
    })
    notify((r and r.message) or '압류 실패',not (r and r.ok))
end

local function towScrap()
    local veh=nearestVehicle(6.0)
    if not veh then return notify('근처 차량을 찾지 못했습니다.',true) end
    local plate=GetVehicleNumberPlateText(veh)
    local c=lib.alertDialog({
        header='차량 폐차',
        content=('번호판 **%s** 차량을 폐차하시겠습니까?\n\n일반 개인 차량만 가능합니다.'):format(plate),
        centered=true,cancel=true,
        labels={confirm='폐차',cancel='취소'}
    })
    if c~='confirm' then return end
    local r=awaitCb('cookie_faction_recovery:towScrap',{netId=NetworkGetNetworkIdFromEntity(veh),plate=plate})
    notify((r and r.message) or '폐차 실패',not (r and r.ok))
end

local function towList()
    local rows=awaitCb('cookie_faction_recovery:towImpounds')
    if not rows then return notify('압류 목록을 불러오지 못했습니다.',true) end
    local opts={}
    if #rows==0 then
        opts[1]={title='압류 차량 없음',disabled=true}
    end
    for _,row in ipairs(rows) do
        opts[#opts+1]={
            title=('%s · %s'):format(tostring(row.plate or '-'),tostring(row.vehicle or '-')),
            description=('사유: %s | 비용: %s원'):format(tostring(row.reason or '-'),tostring(row.fee or 0)),
            icon='car',
            onSelect=function()
                local c=lib.alertDialog({
                    header='압류 해제',
                    content=('%s 차량을 차고로 반환하시겠습니까?'):format(tostring(row.plate or '-')),
                    centered=true,cancel=true,
                    labels={confirm='압류 해제',cancel='취소'}
                })
                if c~='confirm' then return end
                local r=awaitCb('cookie_faction_recovery:towRelease',tonumber(row.id))
                notify((r and r.message) or '압류 해제 실패',not (r and r.ok))
            end
        }
    end
    lib.registerContext({id='cookie_faction_recovery_impounds',title='렉카 압류 차량',options=opts})
    lib.showContext('cookie_faction_recovery_impounds')
end

openTowMenu=function()
    local p=profile()
    if not p or p.isTow~=true then return end
    lib.registerContext({
        id='cookie_faction_recovery_tow',
        title=(p.name or '렉카')..' · F5 업무',
        options={
            {title='근처 차량 압류',description='차량을 압류 상태로 전환',icon='truck',onSelect=towImpound},
            {title='근처 차량 폐차',description='일반 개인차 폐차',icon='trash',onSelect=towScrap},
            {title='압류 차량 관리',description='조회/압류 해제',icon='warehouse',onSelect=towList},
            {title='공동계좌',description='잔액·입금·출금',icon='wallet',onSelect=function() openAccount(p) end},
            {title='기존 F5 업무망',description='기존 cookie_factionmenu 호출',icon='list',onSelect=function() ExecuteCommand('cookie_factionmenu') end}
        }
    })
    lib.showContext('cookie_faction_recovery_tow')
end

local function crimeCuff()
    local target=closestPlayer(3.0)
    if not target then return notify('가까운 대상이 없습니다.',true) end
    TriggerServerEvent('cookie_faction_recovery:crimeCuff',target)
end

local function crimeEscort()
    local target=closestPlayer(3.5)
    if not target then return notify('가까운 대상이 없습니다.',true) end
    TriggerServerEvent('cookie_faction_recovery:crimeEscort',target)
end

local function openPhone()
    if IsPauseMenuActive() then return end
    local p=profile()
    if not p or not p.allowed then return notify((p and p.reason) or '소속 팩션이 없습니다.',true) end

    local opts={}
    if p.isTow then
        opts={
            {title='차량 압류',icon='truck',onSelect=towImpound},
            {title='차량 폐차',icon='trash',onSelect=towScrap},
            {title='압류 차량',icon='warehouse',onSelect=towList},
            {title='공동계좌',icon='wallet',onSelect=function() openAccount(p) end},
            {title='F5 상세 업무',icon='list',onSelect=openTowMenu}
        }
    elseif p.type=='police' or p.type=='security' then
        opts={
            {title='수갑 사용/해제',description='기존 G 기능',icon='link',onSelect=function() ExecuteCommand('+cookie_police_cuff') end},
            {title='끌고가기/해제',description='기존 H 기능',icon='person-walking',onSelect=function() ExecuteCommand('+cookie_police_escort') end},
            {title='미란다 고지',description='기존 PAGE UP 기능',icon='comment',onSelect=function() ExecuteCommand('+cookie_police_miranda') end},
            {title='지원 요청',description='기존 F1 기능',icon='location-dot',onSelect=function() ExecuteCommand('+cookie_police_backup') end},
            {title='공동계좌',icon='wallet',onSelect=function() openAccount(p) end},
            {title='F5 상세 업무',icon='list',onSelect=function() ExecuteCommand('cookie_factionmenu') end}
        }
    elseif p.type=='crime' then
        opts={
            {title='수갑 사용/해제',icon='link',onSelect=crimeCuff},
            {title='끌고가기/해제',icon='person-walking',onSelect=crimeEscort},
            {title='공동계좌',icon='wallet',onSelect=function() openAccount(p) end},
            {title='F5 조직 업무',icon='list',onSelect=function() ExecuteCommand('cookie_factionmenu') end}
        }
    else
        opts={
            {title='공동계좌',icon='wallet',onSelect=function() openAccount(p) end},
            {title='F5 상세 업무',icon='list',onSelect=function() ExecuteCommand('cookie_factionmenu') end}
        }
    end

    lib.registerContext({id='cookie_faction_recovery_phone',title=(p.name or '팩션')..' · 현장 휴대전화',options=opts})
    lib.showContext('cookie_faction_recovery_phone')
end

RegisterCommand('cookie_fieldphone',openPhone,false)
RegisterKeyMapping('cookie_fieldphone','COOKIE 팩션 현장 휴대전화','keyboard','I')

RegisterCommand('cookie_tow_f5_recovery',function()
    local p=profile()
    if p and p.isTow then openTowMenu() end
end,false)
RegisterKeyMapping('cookie_tow_f5_recovery','COOKIE 렉카 F5 복구 메뉴','keyboard','F5')

RegisterCommand('cookie_faction_recovery_diag',function()
    local p=profile()
    print('========== COOKIE FACTION RECOVERY ==========')
    print(('admin=%s factionmenu=%s police=%s'):format(GetResourceState('cookie_admin'),GetResourceState('cookie_factionmenu'),GetResourceState('cookie_police')))
    if p then
        print(('allowed=%s id=%s name=%s type=%s tow=%s officer=%s leader=%s'):format(
            tostring(p.allowed),tostring(p.id),tostring(p.name),tostring(p.type),tostring(p.isTow),tostring(p.isOfficer),tostring(p.isLeader)))
    else
        print('profile=nil')
    end
    print('=============================================')
    notify('진단 결과를 F8에 출력했습니다.')
end,false)

RegisterNetEvent('cookie_faction_recovery:setCrimeCuffed',function(state)
    localCrimeCuffed=state==true
    local ped=PlayerPedId()
    if localCrimeCuffed then
        SetEnableHandcuffs(ped,true)
        SetCurrentPedWeapon(ped,GetHashKey('WEAPON_UNARMED'),true)
        RequestAnimDict('mp_arresting')
        local t=GetGameTimer()+1500
        while not HasAnimDictLoaded('mp_arresting') and GetGameTimer()<t do Wait(10) end
        if HasAnimDictLoaded('mp_arresting') then
            TaskPlayAnim(ped,'mp_arresting','idle',8.0,-8.0,-1,49,0.0,false,false,false)
        end
    else
        SetEnableHandcuffs(ped,false)
        DetachEntity(ped,true,false)
        ClearPedSecondaryTask(ped)
    end
end)

RegisterNetEvent('cookie_faction_recovery:setCrimeEscorted',function(serverId)
    local ped=PlayerPedId()
    if not serverId then
        DetachEntity(ped,true,false)
        return
    end
    local player=GetPlayerFromServerId(tonumber(serverId))
    if player==-1 then return end
    local escortPed=GetPlayerPed(player)
    if not DoesEntityExist(escortPed) then return end
    AttachEntityToEntity(ped,escortPed,GetPedBoneIndex(escortPed,11816),0.35,0.45,0.0,0.0,0.0,0.0,false,false,false,false,2,true)
end)

CreateThread(function()
    while true do
        if localCrimeCuffed then
            DisablePlayerFiring(PlayerId(),true)
            DisableControlAction(0,24,true)
            DisableControlAction(0,25,true)
            DisableControlAction(0,37,true)
            DisableControlAction(0,45,true)
            DisableControlAction(0,140,true)
            DisableControlAction(0,141,true)
            DisableControlAction(0,142,true)
            Wait(0)
        else
            Wait(500)
        end
    end
end)

print('^2[cookie_faction_recovery]^7 I PHONE + TOW F5 recovery V1.0.0 ready')
