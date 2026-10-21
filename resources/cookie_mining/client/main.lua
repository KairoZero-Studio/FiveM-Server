local busy=false
local pickaxeObj=nil
local equippedPickaxeItem=nil
local equippedPickaxeLabel=nil
local nextPickaxeInventoryCheck=0
local currentZone=nil
local spawnedNodes={}
local nodeStates={}
local zoneRequestAt=0
local runtimeSettings={
    mineDurationMs=Config.MineDurationMs,
    rhythmSuccessMs=Config.RhythmSuccessDurationMs,
    rhythmRounds=Config.RhythmRounds,
    nodeCount=Config.NodeCount,
    respawnMs=Config.NodeRespawnMs,
}
local activeNodeIndex=nil

local function vdist2(a,b)
    local dx,dy,dz=a.x-b.x,a.y-b.y,(a.z or 0.0)-(b.z or 0.0)
    return dx*dx+dy*dy+dz*dz
end

local function fract(x) return x-math.floor(x) end
local function seeded01(seed) return fract(math.sin(seed*12.9898+78.233)*43758.5453) end

local function loadModel(model)
    local hash=type(model)=='number' and model or joaat(model)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local timeout=GetGameTimer()+3500
    while not HasModelLoaded(hash) and GetGameTimer()<timeout do Wait(0) end
    return HasModelLoaded(hash) and hash or nil
end

local function loadPtfx(asset)
    RequestNamedPtfxAsset(asset)
    local t=GetGameTimer()+2000
    while not HasNamedPtfxAssetLoaded(asset) and GetGameTimer()<t do Wait(0) end
    return HasNamedPtfxAssetLoaded(asset)
end

local function attachPickaxe()
    if pickaxeObj and DoesEntityExist(pickaxeObj) then return true end
    local ped=PlayerPedId(); local hash=loadModel('prop_tool_pickaxe')
    if not hash then return false end
    pickaxeObj=CreateObject(hash,0.0,0.0,0.0,true,true,false)
    if not pickaxeObj or pickaxeObj==0 then SetModelAsNoLongerNeeded(hash); pickaxeObj=nil; return false end
    SetEntityCollision(pickaxeObj,false,false)
    SetEntityAsMissionEntity(pickaxeObj,true,true)
    AttachEntityToEntity(pickaxeObj,ped,GetPedBoneIndex(ped,57005),0.10,-0.02,-0.02,-80.0,10.0,28.0,true,true,false,true,1,true)
    SetModelAsNoLongerNeeded(hash)
    return true
end
local function removePickaxe()
    if pickaxeObj and DoesEntityExist(pickaxeObj) then DeleteEntity(pickaxeObj) end
    pickaxeObj=nil
end

local function miningNotify(msg,err)
    if lib and lib.notify then lib.notify({title='광질',description=msg,type=err and 'error' or 'inform'}) end
end

local function pickaxeByItem(item)
    item=tostring(item or '')
    for key,d in pairs(Config.Pickaxes or {}) do
        if d.item==item then return key,d end
    end
    return nil,nil
end

local function resolveUsedPickaxe(data,slot)
    if type(data)=='string' then return data end
    if type(data)=='table' then
        if data.name then return tostring(data.name) end
        if data.item then return tostring(data.item) end
    end
    if tonumber(slot) then
        local ok,s=pcall(function() return exports.ox_inventory:GetSlot(tonumber(slot)) end)
        if ok and type(s)=='table' and s.name then return tostring(s.name) end
    end
    return nil
end

local function localPickaxeCount(item)
    local ok,n=pcall(function() return exports.ox_inventory:Search('count',item) end)
    return ok and (tonumber(n) or 0) or 0
end

exports('usePickaxe',function(data,slot)
    local item=resolveUsedPickaxe(data,slot)
    local _,def=pickaxeByItem(item)
    if not def then return miningNotify('곡괭이 아이템 정보를 확인하지 못했습니다.',true) end
    if busy then return miningNotify('광질 중에는 곡괭이를 바꿀 수 없습니다.',true) end

    if equippedPickaxeItem==item then
        equippedPickaxeItem=nil
        equippedPickaxeLabel=nil
        removePickaxe()
        miningNotify(def.label..'를 넣었습니다.',false)
        return
    end

    equippedPickaxeItem=item
    equippedPickaxeLabel=def.label
    removePickaxe()
    if not attachPickaxe() then
        equippedPickaxeItem=nil
        equippedPickaxeLabel=nil
        return miningNotify('곡괭이 오브젝트를 불러오지 못했습니다.',true)
    end
    miningNotify(def.label..'를 들었습니다. 바위 가까이에서 E를 누르세요.',false)
end)

local function pointInPoly2D(pos, pts)
    if type(pts)~='table' or #pts<3 then return false end
    local inside=false; local j=#pts
    for i=1,#pts do
        local a,b=pts[i],pts[j]; local ax,ay=tonumber(a.x or a[1]),tonumber(a.y or a[2]); local bx,by=tonumber(b.x or b[1]),tonumber(b.y or b[2])
        if ax and ay and bx and by then local hit=((ay>pos.y)~=(by>pos.y)) and (pos.x<(bx-ax)*(pos.y-ay)/((by-ay)+0.0000001)+ax); if hit then inside=not inside end end
        j=i
    end
    return inside
end

local function nodePosFor(zone, idx)
    local margin=tonumber(Config.NodeMargin) or 1.0
    local seed=(tonumber(zone.id) or 0)*100+idx
    local rx,ry=seeded01(seed+1),seeded01(seed+2)
    local pos

    -- 중심/중간/외곽이 섞이도록 3개 밴드로 배치합니다.
    -- 기존 sqrt(random)은 면적 균등 때문에 체감상 외곽에 지나치게 몰렸습니다.
    local band=((idx-1)%3)+1
    local factor
    if band==1 then factor=0.18+0.22*seeded01(seed+20)      -- 중심부
    elseif band==2 then factor=0.42+0.24*seeded01(seed+21)  -- 중간
    else factor=0.68+0.22*seeded01(seed+22) end             -- 외곽(끝에 딱 붙지는 않음)

    if zone.shape=='sphere' then
        local maxR=math.max(2.0,(tonumber(zone.radius) or 10.0)-margin)
        local ang=seeded01(seed+3)*math.pi*2.0
        local dist=maxR*factor
        pos=vec3((zone.cx+0.0)+math.cos(ang)*dist,(zone.cy+0.0)+math.sin(ang)*dist,zone.cz+0.0)
    elseif zone.shape=='poly' and type(zone.polyPoints)=='table' and #zone.polyPoints>=3 then
        local minX,maxX,minY,maxY=999999,-999999,999999,-999999
        for _,pt in ipairs(zone.polyPoints) do
            local x,y=tonumber(pt.x or pt[1]),tonumber(pt.y or pt[2])
            if x and y then minX=math.min(minX,x);maxX=math.max(maxX,x);minY=math.min(minY,y);maxY=math.max(maxY,y) end
        end
        local cx,cy=tonumber(zone.cx) or ((minX+maxX)*0.5),tonumber(zone.cy) or ((minY+maxY)*0.5)
        for a=1,40 do
            local x=minX+(maxX-minX)*seeded01(seed+10+a*2)
            local y=minY+(maxY-minY)*seeded01(seed+11+a*2)
            -- 임의점과 중심 사이를 밴드 비율로 섞어 중심/중간/외곽 분포를 만듭니다.
            x=cx+(x-cx)*factor; y=cy+(y-cy)*factor
            if pointInPoly2D({x=x,y=y},zone.polyPoints) then pos=vec3(x,y,zone.cz+0.0); break end
        end
        if not pos then pos=vec3(cx,cy,zone.cz+0.0) end
    else
        local hl=math.max(2.0,((tonumber(zone.length) or 12.0)*0.5)-margin)
        local hw=math.max(2.0,((tonumber(zone.width) or 12.0)*0.5)-margin)
        local lx=(rx*2-1)*hl*factor
        local ly=(ry*2-1)*hw*factor
        local h=math.rad(tonumber(zone.heading) or 0.0)
        local cs,sn=math.cos(h),math.sin(h)
        pos=vec3((zone.cx+0.0)+(lx*cs-ly*sn),(zone.cy+0.0)+(lx*sn+ly*cs),zone.cz+0.0)
    end
    local ok,gz=GetGroundZFor_3dCoord(pos.x,pos.y,pos.z+60.0,false)
    if ok then pos=vec3(pos.x,pos.y,gz) end
    return pos
end

local function deleteNode(idx)
    local n=spawnedNodes[idx]
    if n and n.obj and DoesEntityExist(n.obj) then DeleteEntity(n.obj) end
    spawnedNodes[idx]=nil
end

local function createNode(idx, stage)
    if not currentZone then return end
    deleteNode(idx)
    local models=Config.NodeModels or {'prop_rock_4_big2'}
    local model=models[((stage or 0)%#models)+1]
    local hash=loadModel(model)
    if not hash then return end
    local pos=nodePosFor(currentZone,idx)
    local obj=CreateObject(hash,pos.x,pos.y,pos.z-0.15,false,false,false)
    if obj and obj~=0 then
        PlaceObjectOnGroundProperly(obj)
        FreezeEntityPosition(obj,true)
        SetEntityHeading(obj,seeded01((currentZone.id or 0)*400+idx)*360.0)
        SetEntityAsMissionEntity(obj,true,true)
        local st=nodeStates[idx] or {}
        if st.depleted then SetEntityVisible(obj,false,false); SetEntityCollision(obj,false,false) end
        spawnedNodes[idx]={obj=obj,pos=GetEntityCoords(obj),stage=stage or 0}
    end
    SetModelAsNoLongerNeeded(hash)
end

local function clearNodes()
    for idx in pairs(spawnedNodes) do deleteNode(idx) end
    spawnedNodes={}
end

local function spawnZoneNodes()
    clearNodes()
    if not currentZone then return end
    local count=tonumber(runtimeSettings.nodeCount) or tonumber(Config.NodeCount) or 9
    for i=1,count do createNode(i,0) end
end

local function applyNodeState(idx,depleted,remainingMs,busyState)
    nodeStates[idx]=nodeStates[idx] or {}
    local st=nodeStates[idx]
    st.depleted=depleted==true
    st.busy=busyState==true
    st.cooldownUntil=st.depleted and (GetGameTimer()+math.max(0,tonumber(remainingMs) or 0)) or nil
    local n=spawnedNodes[idx]
    if n and n.obj and DoesEntityExist(n.obj) then
        SetEntityVisible(n.obj,not st.depleted,false)
        SetEntityCollision(n.obj,not st.depleted,not st.depleted)
        if not st.depleted then ResetEntityAlpha(n.obj) end
    end
end

local promptVisible=false
local function showMinePrompt(x,y,z)
    local ok,sx,sy=World3dToScreen2d(x,y,z)
    if not ok then
        if promptVisible then SendNUIMessage({action='minePrompt',show=false});promptVisible=false end
        return
    end
    SendNUIMessage({action='minePrompt',show=true,text='[E] 광질',x=sx,y=sy})
    promptVisible=true
end
local function hideMinePrompt()
    if promptVisible then SendNUIMessage({action='minePrompt',show=false});promptVisible=false end
end

local function hitFx(idx,stage)
    local n=spawnedNodes[idx]
    if not n or not n.obj or not DoesEntityExist(n.obj) then return end
    local p=GetEntityCoords(n.obj)
    if loadPtfx('core') then
        UseParticleFxAssetNextCall('core')
        StartParticleFxNonLoopedAtCoord('ent_dst_rocks',p.x,p.y,p.z+0.55,0.0,0.0,0.0,0.8,false,false,false)
    end
    PlaySoundFromEntity(-1,'Drill_Pin_Break',n.obj,'DLC_HEIST_FLEECA_SOUNDSET',true,0)
    local h=GetEntityHeading(n.obj)
    SetEntityRotation(n.obj,math.random(-3,3)+0.0,math.random(-3,3)+0.0,h+math.random(-5,5)+0.0,2,true)
    SetTimeout(90,function()
        if n and n.obj and DoesEntityExist(n.obj) then SetEntityRotation(n.obj,0.0,0.0,h,2,true) end
    end)
    if stage and stage>0 and n.stage~=stage then createNode(idx,stage) end
end

local function miningAnimAndFx(idx,duration)
    local ped=PlayerPedId(); local dict='melee@large_wpn@streamed_core'
    RequestAnimDict(dict)
    local t=GetGameTimer()+3000
    while not HasAnimDictLoaded(dict) and GetGameTimer()<t do Wait(0) end
    CreateThread(function()
        local started=GetGameTimer(); local hit=0
        while busy and activeNodeIndex==idx and GetGameTimer()-started<duration do
            hit=hit+1
            if HasAnimDictLoaded(dict) then TaskPlayAnim(ped,dict,'ground_attack_0',3.0,3.0,750,0,0.0,false,false,false) end
            local progress=(GetGameTimer()-started)/math.max(duration,1)
            local stage=progress>=0.66 and 2 or (progress>=0.33 and 1 or 0)
            hitFx(idx,stage)
            Wait(800)
        end
    end)
end

local activeMiningSkillRound=nil
local activeMiningSkillResult=nil

RegisterNUICallback('miningSkillJudged',function(data,cb)
    cb('ok')
    if type(data)~='table' then return end

    local roundId=tostring(data.roundId or '')
    if not activeMiningSkillRound or roundId~=activeMiningSkillRound then
        return
    end

    activeMiningSkillResult=data.success==true
end)

local function closeMiningCircle()
    activeMiningSkillRound=nil
    activeMiningSkillResult=nil
    SendNUIMessage({action='miningSkillClose'})
end

local function runCircleRound(round,totalRounds)
    local later=round>=math.max(3,totalRounds-1)

    -- V13.8:
    -- 화면상 목표 범위와 실제 판정이 최대한 일치하도록
    -- 판정 여유를 약간 넓히고 NUI가 직접 현재 표시 위치를 판정합니다.
    local tolerance=later and 30.0 or 40.0
    local period=later and 1120 or 1320
    local timeout=5000
    local target=(GetGameTimer()*0.173 + round*137.0 + math.random(0,359))%360.0
    local roundId=('%s:%s:%s'):format(GetPlayerServerId(PlayerId()),round,GetGameTimer())

    activeMiningSkillRound=roundId
    activeMiningSkillResult=nil

    SendNUIMessage({
        action='miningSkillOpen',
        round=round,
        total=totalRounds,
        roundId=roundId,
        target=target,
        tolerance=tolerance,
        period=period,
        label=('광질 타이밍 %d / %d'):format(round,totalRounds),
    })

    -- 바위를 시작할 때 누른 E가 미니게임 입력으로 먹는 것을 방지.
    Wait(420)

    local started=GetGameTimer()

    while GetGameTimer()-started < timeout do
        Wait(0)

        DisableControlAction(0,38,true) -- E
        DisableControlAction(0,22,true) -- SPACE

        -- V13.8: Released가 아니라 Pressed 순간을 판정한다.
        -- 길게 누르는 사람/키보드 입력 지연으로 원을 지나친 뒤 판정되는 문제를 막는다.
        if IsDisabledControlJustPressed(0,38) or IsDisabledControlJustPressed(0,22) then
            activeMiningSkillResult=nil

            -- 실제 화면을 그리고 있는 NUI가 그 순간의 흰 원 위치를 직접 판정한다.
            SendNUIMessage({
                action='miningSkillJudge',
                roundId=roundId,
            })

            local waitUntil=GetGameTimer()+750
            while activeMiningSkillResult==nil and GetGameTimer()<waitUntil do
                Wait(0)
            end

            local ok=activeMiningSkillResult==true
            activeMiningSkillRound=nil
            activeMiningSkillResult=nil

            if ok then
                Wait(380)
            else
                Wait(520)
            end
            return ok
        end
    end

    if activeMiningSkillRound==roundId then
        activeMiningSkillRound=nil
        activeMiningSkillResult=nil
    end

    SendNUIMessage({
        action='miningSkillResult',
        success=false,
        timeout=true,
        roundId=roundId,
    })
    Wait(520)
    return false
end

local function runRhythm(rounds)
    rounds=math.max(1,math.min(10,tonumber(rounds) or 4))
    Wait(250)

    miningNotify(('원형 타이밍 미니게임 · %d라운드'):format(rounds),false)

    for round=1,rounds do
        local success=runCircleRound(round,rounds)
        if not success then
            closeMiningCircle()
            miningNotify('타이밍 실패 · 기본 채굴 시간으로 진행합니다.',true)
            return false
        end
        if round<rounds then Wait(180) end
    end

    closeMiningCircle()
    miningNotify('타이밍 성공! 채굴 시간이 단축됩니다.',false)
    return true
end

RegisterNetEvent('cookie_mining:client:systemSettings',function(s)
    if not s then return end
    runtimeSettings.mineDurationMs=tonumber(s.mineDurationMs) or runtimeSettings.mineDurationMs
    runtimeSettings.rhythmSuccessMs=tonumber(s.rhythmSuccessMs) or runtimeSettings.rhythmSuccessMs
    runtimeSettings.rhythmRounds=tonumber(s.rhythmRounds) or runtimeSettings.rhythmRounds
    local old=runtimeSettings.nodeCount
    runtimeSettings.nodeCount=tonumber(s.nodeCount) or runtimeSettings.nodeCount
    runtimeSettings.respawnMs=tonumber(s.respawnMs) or runtimeSettings.respawnMs
    if currentZone and old~=runtimeSettings.nodeCount then spawnZoneNodes() end
end)

RegisterNetEvent('cookie_mining:client:zoneNodesState',function(payload)
    if not payload or not payload.zone then return end
    currentZone=payload.zone
    if payload.settings then TriggerEvent('cookie_mining:client:systemSettings',payload.settings) end
    nodeStates=payload.states or {}
    spawnZoneNodes()
end)

RegisterNetEvent('cookie_mining:client:nodeState',function(zoneId,idx,depleted,remainingMs,busyState)
    if not currentZone or tonumber(currentZone.id)~=tonumber(zoneId) then return end
    applyNodeState(tonumber(idx),depleted,remainingMs,busyState)
end)

RegisterNetEvent('cookie_mining:client:rhythm',function(data)
    if busy then return end
    if not equippedPickaxeItem then return miningNotify('퀵슬롯에서 곡괭이를 먼저 들어주세요.',true) end
    busy=true
    attachPickaxe()
    activeNodeIndex=tonumber(data.nodeIndex)
    local ped=PlayerPedId()
    local n=activeNodeIndex and spawnedNodes[activeNodeIndex]
    if n and n.obj and DoesEntityExist(n.obj) then TaskTurnPedToFaceEntity(ped,n.obj,450); Wait(450) end
    FreezeEntityPosition(ped,true)

    local success=runRhythm(data.rhythmRounds or runtimeSettings.rhythmRounds)
    print(('[cookie_mining] rhythm result = %s'):format(success and 'SUCCESS' or 'FAIL'))

    TriggerServerEvent('cookie_mining:server:rhythmResult',success)
end)

RegisterNetEvent('cookie_mining:client:mineStart',function(data)
    if not busy then busy=true end
    activeNodeIndex=tonumber(data.nodeIndex) or activeNodeIndex
    local duration=tonumber(data.duration) or runtimeSettings.mineDurationMs
    local ped=PlayerPedId()
    FreezeEntityPosition(ped,true)
    attachPickaxe(); miningAnimAndFx(activeNodeIndex,duration)
    local label=(data.rhythmSuccess and '리듬 성공! 빠른 채굴' or '광질 중...')
    if data.pickaxeLabel and data.pickaxeLabel~='' then label=label..' · '..data.pickaxeLabel end
    local ok=lib.progressCircle({duration=duration,position='bottom',label=label,useWhileDead=false,canCancel=true,disable={move=true,car=true,combat=true,sprint=true}})
    ClearPedTasks(PlayerPedId()); FreezeEntityPosition(PlayerPedId(),false); busy=false
    if equippedPickaxeItem then attachPickaxe() else removePickaxe() end
    local idx=activeNodeIndex; activeNodeIndex=nil
    TriggerServerEvent('cookie_mining:server:finish',ok==true,idx)
end)

-- 광물 관리인: 구매 / 판매 / 기록 탭 NUI
-- V1.6.2: cookie_admin 상호작용 라우팅에 의존하지 않고 cookie_mining이 직접 처리한다.
local miningManagerOpen=false
local miningManagerNpcs={}
local miningManagerPrompt=false
local miningManagerLastPress=0

local function isMiningManagerJob(v)
    v=tostring(v or ''):lower()
    return v=='mining' or v=='miner' or v=='mineral'
end

local function setMiningManagerNpcs(rows)
    local nextRows={}
    for _,r in ipairs(rows or {}) do
        if isMiningManagerJob(r.job_key) then
            local id=tonumber(r.id)
            if id then
                nextRows[id]={
                    id=id,
                    label=tostring(r.label or '광물 관리인'),
                    x=tonumber(r.x) or 0.0,
                    y=tonumber(r.y) or 0.0,
                    z=tonumber(r.z) or 0.0,
                }
            end
        end
    end
    miningManagerNpcs=nextRows
    local n=0; for _ in pairs(nextRows) do n=n+1 end
    print(('[cookie_mining] manager NPC list updated: %d'):format(n))
end

RegisterNetEvent('cookie_mining:client:managerNpcList',function(rows)
    setMiningManagerNpcs(rows)
end)

-- cookie_admin이 NPC 목록을 갱신하면 광물 관리인 목록도 즉시 동기화한다.
RegisterNetEvent('cookie_admin:client:npcList',function(rows)
    setMiningManagerNpcs(rows)
end)

local function requestMiningManagerNpcs()
    TriggerServerEvent('cookie_mining:server:requestManagerNpcs')
end

CreateThread(function()
    Wait(1500)
    requestMiningManagerNpcs()
    while true do
        Wait(30000)
        requestMiningManagerNpcs()
    end
end)

CreateThread(function()
    while true do
        local wait=700
        -- 정상 상황에서는 cookie_admin 공용 NPC 라우터가 E키를 담당한다.
        -- cookie_admin이 꺼진 경우에만 이 루프가 비상 fallback으로 동작한다.
        if GetResourceState('cookie_admin') ~= 'started' and not miningManagerOpen and not busy and not IsPauseMenuActive() then
            local ped=PlayerPedId()
            if not IsPedInAnyVehicle(ped,false) then
                local pos=GetEntityCoords(ped)
                local best,bestD=nil,3.0
                for _,n in pairs(miningManagerNpcs) do
                    local d=#(pos-vec3(n.x,n.y,n.z))
                    if d<bestD then best,bestD=n,d end
                end

                if best then
                    wait=0
                    if not miningManagerPrompt then
                        lib.showTextUI(('[E] %s와 대화'):format(best.label),{position='left-center'})
                        miningManagerPrompt=true
                    end
                    if IsControlJustReleased(0,38) or IsDisabledControlJustReleased(0,38) then
                        local now=GetGameTimer()
                        if now-miningManagerLastPress>600 then
                            miningManagerLastPress=now
                            if miningManagerPrompt then
                                lib.hideTextUI()
                                miningManagerPrompt=false
                            end
                            print(('[cookie_mining] manager interact npc=%s'):format(best.id))
                            TriggerServerEvent('cookie_mining:server:managerMenu',best.id)
                        end
                    end
                elseif miningManagerPrompt then
                    lib.hideTextUI()
                    miningManagerPrompt=false
                end
            elseif miningManagerPrompt then
                lib.hideTextUI()
                miningManagerPrompt=false
            end
        elseif miningManagerPrompt then
            lib.hideTextUI()
            miningManagerPrompt=false
        end
        Wait(wait)
    end
end)
local function openMiningManager(payload)
    local npcId=tonumber(payload and payload.npcId)
    if not npcId then return false end

    print(('[cookie_mining] open manager requested npc=%s'):format(npcId))

    -- 서버 DB 조회가 잠깐 늦거나 기록 쿼리에서 문제가 나도
    -- 'E를 눌렀는데 아무 반응이 없는' 상태가 되지 않도록 UI 셸부터 연다.
    miningManagerOpen=true
    if miningManagerPrompt then lib.hideTextUI(); miningManagerPrompt=false end
    SetNuiFocus(true,true)
    SendNUIMessage({
        action='openManager',
        data={
            npcId=npcId,
            label=tostring((payload and payload.label) or '광물 관리인'),
            loading=true,
            shop={},
            minerals={},
            totalValue=0,
            totalCount=0,
            records={discovered=0,total=0,totalMined=0,rows={},leaderboard={}}
        }
    })

    TriggerServerEvent('cookie_mining:server:managerMenu',npcId)
    return true
end

RegisterNetEvent('cookie_mining:client:openManager',function(payload)
    openMiningManager(payload)
end)

exports('OpenManager',function(payload)
    return openMiningManager(payload)
end)

RegisterNetEvent('cookie_mining:client:managerMenu',function(data)
    if not data then return end
    if miningManagerPrompt then lib.hideTextUI(); miningManagerPrompt=false end
    miningManagerOpen=true
    SetNuiFocus(true,true)
    data.loading=false
    SendNUIMessage({action='openManager',data=data})
end)

RegisterNetEvent('cookie_mining:client:managerMenuError',function(message)
    if not miningManagerOpen then return end
    SendNUIMessage({action='managerError',message=tostring(message or '광물 관리인 정보를 불러오지 못했습니다.')})
end)

RegisterNUICallback('managerClose',function(_,cb)
    miningManagerOpen=false
    if miningManagerPrompt then lib.hideTextUI(); miningManagerPrompt=false end
    SetNuiFocus(false,false)
    cb({ok=true})
end)
RegisterNUICallback('managerBuy',function(d,cb)
    cb({ok=true})
    if d and d.kind and d.npcId then TriggerServerEvent('cookie_mining:server:buy',d.kind,d.npcId) end
end)
RegisterNUICallback('managerSellOne',function(d,cb)
    cb({ok=true})
    if d then TriggerServerEvent('cookie_mining:server:sellOne',d.npcId,d.key,d.slot) end
end)
RegisterNUICallback('managerSellAll',function(d,cb)
    cb({ok=true})
    if d and d.npcId then TriggerServerEvent('cookie_mining:server:sellAll',d.npcId) end
end)

CreateThread(function()
    while true do
        local wait=600
        local zone=nil
        local ok,res=pcall(function() return exports.cookie_safezone:getMiningZone() end)
        if ok then zone=res end
        if zone then
            local changed=not currentZone or tonumber(currentZone.id)~=tonumber(zone.id)
            if changed then
                currentZone=zone
                zoneRequestAt=0
                nodeStates={}
                clearNodes()
            else
                -- 같은 광산이면 서버에서 받은 full zone payload를 보존한다.
                -- safezone export가 더 상세한 값을 갖고 있을 때만 최신화한다.
                if zone.cx and zone.cy and zone.cz then
                    currentZone=zone
                elseif currentZone then
                    currentZone.label=zone.label or currentZone.label
                end
            end
            if not next(spawnedNodes) or GetGameTimer()-zoneRequestAt>10000 then
                zoneRequestAt=GetGameTimer(); TriggerServerEvent('cookie_mining:server:requestZoneNodes',zone.id)
            end
        else
            if currentZone then clearNodes() end
            currentZone=nil; nodeStates={}
        end
        Wait(wait)
    end
end)

CreateThread(function()
    while true do
        local wait=500
        if currentZone and equippedPickaxeItem and not IsPedInAnyVehicle(PlayerPedId(),false) then
            local p=GetEntityCoords(PlayerPedId())
            local bestIdx,bestD=nil,999999.0
            for idx,n in pairs(spawnedNodes) do
                local st=nodeStates[idx] or {}
                if n.obj and DoesEntityExist(n.obj) then
                    if st.depleted and st.cooldownUntil and st.cooldownUntil<=GetGameTimer() then
                        applyNodeState(idx,false,0,false); createNode(idx,0); st=nodeStates[idx] or {}
                    end
                    if not st.depleted and not st.busy then
                        local d2=vdist2(p,n.pos)
                        if d2<bestD then bestD=d2; bestIdx=idx end
                    end
                end
            end
            local maxD=tonumber(Config.InteractDistance) or 2.4
            if bestIdx and bestD<=(maxD*maxD) then
                wait=0
                local n=spawnedNodes[bestIdx]
                if n and n.obj and DoesEntityExist(n.obj) then
                    local rp=GetEntityCoords(n.obj)
                    showMinePrompt(rp.x,rp.y,rp.z+0.90)
                end
                if not busy and IsControlJustReleased(0,38) then hideMinePrompt();TriggerServerEvent('cookie_mining:server:start',currentZone.id,bestIdx,equippedPickaxeItem); Wait(350) end
            else
                hideMinePrompt()
            end
        else
            hideMinePrompt()
        end
        Wait(wait)
    end
end)


CreateThread(function()
    while true do
        Wait(700)
        if equippedPickaxeItem then
            if IsEntityDead(PlayerPedId()) or localPickaxeCount(equippedPickaxeItem)<=0 then
                if not busy then
                    equippedPickaxeItem=nil
                    equippedPickaxeLabel=nil
                    removePickaxe()
                end
            else
                attachPickaxe()
            end
        end
    end
end)

AddEventHandler('onResourceStop',function(res)
    if res~=GetCurrentResourceName() then return end
    hideMinePrompt(); clearNodes(); removePickaxe(); ClearPedTasks(PlayerPedId()); FreezeEntityPosition(PlayerPedId(),false)
end)

print('^2[cookie_mining]^7 RHYTHM FIX V1.6.1 active')

print('^2[cookie_mining]^7 MANAGER INTERACTION FIX V1.6.2 active')

print('^2[cookie_mining]^7 NPC FALLBACK V1.6.6 active')

print('^2[cookie_mining]^7 NPC DIALOG HOTFIX V1.6.7 active')

print('^2[cookie_mining]^7 NPC ROUTE SYNC V1.6.8 active')

print('^2[cookie_mining]^7 QUICK SLOT PICKAXE EQUIP V1.7.5 active')

print('^2[cookie_mining]^7 BUILTIN CIRCLE MINIGAME V13.6 ready')

print('^2[cookie_mining]^7 RHYTHM NUI SYNC V13.8 ready')
