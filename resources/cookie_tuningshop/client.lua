local shopOpen=false
local currentVeh=0
local currentPlate=''
local currentTune=nil
local baseTune=nil
local previewTune=nil
local tuneCam=nil
local repairRequired=false

local appliedByVehicle={}
local baseHandling={}
local durabilityState={}

local function notify(msg,err)
    if GetResourceState('cookie_admin')=='started' then
        TriggerEvent('cookie_admin:client:notify',msg,err and true or false)
    else
        lib.notify({title='튜닝샵',description=msg,type=err and 'error' or 'success'})
    end
end

local function trimPlate(p)
    return tostring(p or ''):gsub('^%s+',''):gsub('%s+$',''):upper()
end

local function clone(v)
    if type(v)~='table' then return nil end
    return json.decode(json.encode(v))
end

local function pcallValue(fn,fallback)
    local ok,val=pcall(fn)
    if ok and val~=nil then return val end
    return fallback
end

local function specialRgb(key)
    for _,c in ipairs(Config.SpecialPaints or {}) do
        if c.key==key and type(c.rgb)=='table' then return c.rgb end
    end
    return nil
end

local function ensureBase(veh)
    if not baseHandling[veh] then
        baseHandling[veh]={
            maxFlat=GetVehicleHandlingFloat(veh,'CHandlingData','fInitialDriveMaxFlatVel'),
            driveForce=GetVehicleHandlingFloat(veh,'CHandlingData','fInitialDriveForce'),
            driveInertia=GetVehicleHandlingFloat(veh,'CHandlingData','fDriveInertia'),
            clutchUp=GetVehicleHandlingFloat(veh,'CHandlingData','fClutchChangeRateScaleUpShift'),
            clutchDown=GetVehicleHandlingFloat(veh,'CHandlingData','fClutchChangeRateScaleDownShift'),
            brake=GetVehicleHandlingFloat(veh,'CHandlingData','fBrakeForce'),
            tractionMax=GetVehicleHandlingFloat(veh,'CHandlingData','fTractionCurveMax'),
            tractionMin=GetVehicleHandlingFloat(veh,'CHandlingData','fTractionCurveMin'),
        }
    end
    return baseHandling[veh]
end

local function getVehiclePerformanceProfile(veh)
    local profiles=Config.VehiclePerformanceProfiles or {}
    local hash=GetEntityModel(veh)

    for model,profile in pairs(profiles) do
        if joaat(tostring(model))==hash then
            return profile,tostring(model)
        end
    end

    return nil,nil
end

local function levelValue(tbl,level,fallback)
    if type(tbl)~='table' then return fallback end
    local v=tonumber(tbl[level])
    if v==nil then return fallback end
    return v
end

local function modIndexToLevel(veh,modType)
    local idx=GetVehicleMod(veh,modType)
    if idx<0 then return 0 end

    local count=GetNumVehicleMods(veh,modType)
    if count<=0 then return 0 end

    return math.max(1,math.min(5,math.ceil(((idx+1)/count)*5)))
end

local function levelToModIndex(veh,modType,level)
    local count=GetNumVehicleMods(veh,modType)
    if count<=0 or tonumber(level or 0)<=0 then return -1 end

    local ratio=math.min(1.0,math.max(0.0,(tonumber(level) or 0)/5.0))
    local idx=math.ceil(count*ratio)-1
    if idx<0 then idx=0 end
    if idx>count-1 then idx=count-1 end
    return idx
end

local function getModLabel(veh,modType,index,prefix)
    if index<0 then return '순정' end
    local label=pcallValue(function() return GetModTextLabel(veh,modType,index) end,nil)
    if label and label~='' then
        local translated=pcallValue(function() return GetLabelText(label) end,nil)
        if translated and translated~='' and translated~='NULL' then return translated end
    end
    return ('%s %d'):format(prefix or '옵션',index+1)
end

local function buildModOptions(veh,modType,prefix)
    local out={{id=-1,label='순정'}}
    local count=GetNumVehicleMods(veh,modType)
    for i=0,count-1 do
        out[#out+1]={id=i,label=getModLabel(veh,modType,i,prefix)}
    end
    return out
end

local function buildExtras(veh)
    local state={}
    local options={}
    for i=0,20 do
        if DoesExtraExist(veh,i) then
            local on=IsVehicleExtraTurnedOn(veh,i)
            state[tostring(i)]=on
            options[#options+1]={id=i,label=('EXTRA %d'):format(i),enabled=on}
        end
    end
    return state,options
end

local function captureTune(veh)
    SetVehicleModKit(veh,0)

    local pIndex,sIndex=GetVehicleColours(veh)
    local pCustom=GetIsVehiclePrimaryColourCustom(veh)
    local sCustom=GetIsVehicleSecondaryColourCustom(veh)

    local pr,pg,pb=GetVehicleCustomPrimaryColour(veh)
    local sr,sg,sb=GetVehicleCustomSecondaryColour(veh)

    local _,wheelColor=GetVehicleExtraColours(veh)
    local tr,tg,tb=GetVehicleTyreSmokeColor(veh)
    local nr,ng,nb=GetVehicleNeonLightsColour(veh)

    local extras=buildExtras(veh)

    local xenonColor=pcallValue(function()
        return GetVehicleXenonLightsColor(veh)
    end,0)

    local interiorColor=pcallValue(function()
        return GetVehicleInteriorColor(veh)
    end,0)

    return {
        primary={pr or 255,pg or 255,pb or 255},
        secondary={sr or 255,sg or 255,sb or 255},
        primaryCustom=pCustom==true,
        secondaryCustom=sCustom==true,
        primaryIndex=tonumber(pIndex) or 0,
        secondaryIndex=tonumber(sIndex) or 0,
        specialKey='none',

        wheelColor=tonumber(wheelColor) or 0,
        windowTint=tonumber(GetVehicleWindowTint(veh)) or 4,
        interiorColor=tonumber(interiorColor) or 0,

        engineLevel=modIndexToLevel(veh,11),
        speedLevel=0,
        durabilityLevel=0,
        brakeLevel=modIndexToLevel(veh,12),
        suspensionLevel=modIndexToLevel(veh,15),
        transmissionLevel=modIndexToLevel(veh,13),
        turbo=IsToggleModOn(veh,18),

        bulletproofTyres=not GetVehicleTyresCanBurst(veh),
        tyreSmoke={tr or 255,tg or 255,tb or 255},
        tyreSmokeEnabled=IsToggleModOn(veh,20),

        hornIndex=GetVehicleMod(veh,14),

        xenonEnabled=IsToggleModOn(veh,22),
        xenonColor=tonumber(xenonColor) or 0,

        engineAudio='stock',
        extras=extras,

        plateStyle=tonumber(GetVehicleNumberPlateTextIndex(veh)) or 0,

        neonEnabled=IsVehicleNeonLightEnabled(veh,0)
            or IsVehicleNeonLightEnabled(veh,1)
            or IsVehicleNeonLightEnabled(veh,2)
            or IsVehicleNeonLightEnabled(veh,3),
        neonColor={nr or 255,ng or 255,nb or 255},
        neonSides={
            left=IsVehicleNeonLightEnabled(veh,0),
            right=IsVehicleNeonLightEnabled(veh,1),
            front=IsVehicleNeonLightEnabled(veh,2),
            back=IsVehicleNeonLightEnabled(veh,3),
        },

        wheelType=tonumber(GetVehicleWheelType(veh)) or 0,
        wheelIndex=GetVehicleMod(veh,23),

        frontBumper=GetVehicleMod(veh,1),
        rearBumper=GetVehicleMod(veh,2),
        roofIndex=GetVehicleMod(veh,10),
        exhaustIndex=GetVehicleMod(veh,4),
    }
end

local function captureCondition(veh)
    local engine=GetVehicleEngineHealth(veh)
    local body=GetVehicleBodyHealth(veh)
    local tank=GetVehiclePetrolTankHealth(veh)

    local tyreBurst=false
    for _,i in ipairs({0,1,2,3,4,5,6,7,45,47}) do
        if pcallValue(function() return IsVehicleTyreBurst(veh,i,false) end,false) then
            tyreBurst=true
            break
        end
    end

    local brokenWindow=false
    for i=0,7 do
        local intact=pcallValue(function() return IsVehicleWindowIntact(veh,i) end,true)
        if not intact then brokenWindow=true break end
    end

    local threshold=tonumber(Config.RepairHealthThreshold) or 999.0
    local required=engine<threshold or body<threshold or tank<threshold or tyreBurst or brokenWindow

    return {
        engine=engine,
        body=body,
        tank=tank,
        enginePct=math.max(0,math.min(100,math.floor((engine/1000.0)*100+0.5))),
        bodyPct=math.max(0,math.min(100,math.floor((body/1000.0)*100+0.5))),
        tankPct=math.max(0,math.min(100,math.floor((tank/1000.0)*100+0.5))),
        tyreBurst=tyreBurst,
        brokenWindow=brokenWindow,
        required=required,
    }
end

local function doFullRepair(veh)
    SetVehicleFixed(veh)
    SetVehicleDeformationFixed(veh)
    SetVehicleEngineHealth(veh,1000.0)
    SetVehicleBodyHealth(veh,1000.0)
    SetVehiclePetrolTankHealth(veh,1000.0)
    SetVehicleDirtLevel(veh,0.0)

    for _,i in ipairs({0,1,2,3,4,5,6,7,45,47}) do
        pcall(function() SetVehicleTyreFixed(veh,i) end)
    end
    for i=0,7 do
        pcall(function() FixVehicleWindow(veh,i) end)
    end
end

local function forceStockAudio(veh)
    local model=GetEntityModel(veh)
    local display=GetDisplayNameFromVehicleModel(model)
    if display and display~='' and display~='NULL' then
        pcall(function() ForceVehicleEngineAudio(veh,display) end)
    end
end

local function applyTune(veh,t)
    if not veh or veh==0 or not DoesEntityExist(veh) or type(t)~='table' then return end

    SetVehicleModKit(veh,0)

    -- 1/2차 색상: 순정 인덱스 보존 + 변경 시 RGB.
    local cp,cs=GetVehicleColours(veh)
    local pIndex=tonumber(t.primaryIndex) or cp
    local sIndex=tonumber(t.secondaryIndex) or cs

    pcall(function() ClearVehicleCustomPrimaryColour(veh) end)
    pcall(function() ClearVehicleCustomSecondaryColour(veh) end)
    SetVehicleColours(veh,pIndex,sIndex)

    local special=specialRgb(t.specialKey)
    if special then
        SetVehicleCustomPrimaryColour(veh,special[1],special[2],special[3])
    elseif t.primaryCustom==true and type(t.primary)=='table' then
        SetVehicleCustomPrimaryColour(veh,t.primary[1] or 255,t.primary[2] or 255,t.primary[3] or 255)
    end

    if t.secondaryCustom==true and type(t.secondary)=='table' then
        SetVehicleCustomSecondaryColour(veh,t.secondary[1] or 255,t.secondary[2] or 255,t.secondary[3] or 255)
    end

    local pearl,_=GetVehicleExtraColours(veh)
    SetVehicleExtraColours(veh,pearl,tonumber(t.wheelColor) or 0)

    SetVehicleWindowTint(veh,tonumber(t.windowTint) or 4)
    pcall(function() SetVehicleInteriorColor(veh,tonumber(t.interiorColor) or 0) end)

    SetVehicleMod(veh,11,levelToModIndex(veh,11,t.engineLevel),false)
    SetVehicleMod(veh,12,levelToModIndex(veh,12,t.brakeLevel),false)
    SetVehicleMod(veh,15,levelToModIndex(veh,15,t.suspensionLevel),false)
    SetVehicleMod(veh,13,levelToModIndex(veh,13,t.transmissionLevel),false)

    ToggleVehicleMod(veh,18,t.turbo==true)

    local b=ensureBase(veh)
    local sl=math.max(0,math.min(Config.MaxSpeedLevel or 5,math.floor(tonumber(t.speedLevel) or 0)))
    local el=math.max(0,math.min(Config.MaxEngineLevel or 5,math.floor(tonumber(t.engineLevel) or 0)))
    local profile=getVehiclePerformanceProfile(veh)

    if profile then
        -- COOKIE 차량별 기본 핸들링 프로필.
        -- 튜닝 저장 여부와 무관하게 해당 모델은 순정부터 지정된 주행감으로 적용.
        if type(profile.baseHandling)=='table' then
            for field,value in pairs(profile.baseHandling) do
                local n=tonumber(value)
                if n~=nil then
                    SetVehicleHandlingFloat(veh,'CHandlingData',tostring(field),n)
                end
            end
        end

        -- COOKIE 차량별 성능 프로필:
        -- 속도 강화는 정확한 km/h 상한, 엔진 강화는 실제 가속/응답값을 사용.
        local speedKmh=levelValue(profile.speeds,sl,180.0)
        local driveForce=levelValue(profile.driveForce,el,b.driveForce or 0.30)
        local driveInertia=levelValue(profile.driveInertia,el,b.driveInertia or 1.0)
        local clutchUp=levelValue(profile.clutchUp,el,b.clutchUp or 1.0)
        local clutchDown=levelValue(profile.clutchDown,el,b.clutchDown or 1.0)

        SetVehicleHandlingFloat(veh,'CHandlingData','fInitialDriveForce',driveForce)
        SetVehicleHandlingFloat(veh,'CHandlingData','fDriveInertia',driveInertia)
        SetVehicleHandlingFloat(veh,'CHandlingData','fClutchChangeRateScaleUpShift',clutchUp)
        SetVehicleHandlingFloat(veh,'CHandlingData','fClutchChangeRateScaleDownShift',clutchDown)

        -- handling 자체는 최고단까지 낼 수 있게 두고 실제 단계별 최고속도만 정확히 제한.
        SetVehicleMaxSpeed(veh,speedKmh/3.6)
    else
        -- All unprofiled vehicles: generic performance tuning, not just a speed multiplier.
        -- All figures derive from the vehicle's own stock handling, preserving unique feel.
        local mult=(Config.SpeedMultipliers and Config.SpeedMultipliers[sl]) or 1.0
        if b.maxFlat and b.maxFlat>0 then
            SetVehicleHandlingFloat(veh,'CHandlingData','fInitialDriveMaxFlatVel',b.maxFlat*mult)
        end
        if b.driveForce and b.driveForce>0 then
            local gain=tonumber(Config.GenericTuneDriveForceGain) or 0.18
            SetVehicleHandlingFloat(veh,'CHandlingData','fInitialDriveForce',b.driveForce*(1.0+gain*el/5.0))
        end
        if b.brake and b.brake>0 then
            local brakeLevel=math.max(0,math.min(5,tonumber(t.brakeLevel) or 0))
            SetVehicleHandlingFloat(veh,'CHandlingData','fBrakeForce',b.brake*(1.0+(tonumber(Config.GenericTuneBrakeGain) or 0.20)*brakeLevel/5.0))
        end
        local gripLevel=math.max(0,math.min(5,tonumber(t.suspensionLevel) or 0))
        local gripGain=(tonumber(Config.GenericTuneTractionGain) or 0.08)*gripLevel/5.0
        if b.tractionMax and b.tractionMax>0 then
            SetVehicleHandlingFloat(veh,'CHandlingData','fTractionCurveMax',b.tractionMax*(1.0+gripGain))
        end
        if b.tractionMin and b.tractionMin>0 then
            SetVehicleHandlingFloat(veh,'CHandlingData','fTractionCurveMin',b.tractionMin*(1.0+gripGain))
        end
        -- Model classes have clear final top-speed bounds (rather than raising every car equally).
        local modelHash=GetEntityModel(veh)
        for model,tier in pairs(Config.TuneVehicleTier or {}) do
            if joaat(tostring(model))==modelHash then
                local top=(Config.TuneTierTopSpeed or {})[tier]
                if tonumber(top) then SetVehicleMaxSpeed(veh,tonumber(top)/3.6) end
                break
            end
        end
    end

    SetVehicleTyresCanBurst(veh,t.bulletproofTyres~=true)

    if type(t.tyreSmoke)=='table' then
        ToggleVehicleMod(veh,20,t.tyreSmokeEnabled==true)
        SetVehicleTyreSmokeColor(
            veh,
            tonumber(t.tyreSmoke[1]) or 255,
            tonumber(t.tyreSmoke[2]) or 255,
            tonumber(t.tyreSmoke[3]) or 255
        )
    end

    SetVehicleMod(veh,14,tonumber(t.hornIndex) or -1,false)

    ToggleVehicleMod(veh,22,t.xenonEnabled==true)
    pcall(function() SetVehicleXenonLightsColor(veh,tonumber(t.xenonColor) or 0) end)

    if tostring(t.engineAudio or 'stock')=='stock' then
        forceStockAudio(veh)
    else
        pcall(function() ForceVehicleEngineAudio(veh,tostring(t.engineAudio)) end)
    end

    if type(t.extras)=='table' then
        for k,v in pairs(t.extras) do
            local id=tonumber(k)
            if id and DoesExtraExist(veh,id) then
                SetVehicleExtra(veh,id,v~=true)
            end
        end
    end

    SetVehicleNumberPlateTextIndex(veh,tonumber(t.plateStyle) or 0)

    local sides=t.neonSides or {}
    SetVehicleNeonLightEnabled(veh,0,t.neonEnabled==true and sides.left==true)
    SetVehicleNeonLightEnabled(veh,1,t.neonEnabled==true and sides.right==true)
    SetVehicleNeonLightEnabled(veh,2,t.neonEnabled==true and sides.front==true)
    SetVehicleNeonLightEnabled(veh,3,t.neonEnabled==true and sides.back==true)

    if type(t.neonColor)=='table' then
        SetVehicleNeonLightsColour(
            veh,
            tonumber(t.neonColor[1]) or 255,
            tonumber(t.neonColor[2]) or 255,
            tonumber(t.neonColor[3]) or 255
        )
    end

    SetVehicleWheelType(veh,tonumber(t.wheelType) or 0)
    SetVehicleMod(veh,23,tonumber(t.wheelIndex) or -1,false)
    if GetNumVehicleMods(veh,24)>0 then
        SetVehicleMod(veh,24,tonumber(t.wheelIndex) or -1,false)
    end

    SetVehicleMod(veh,1,tonumber(t.frontBumper) or -1,false)
    SetVehicleMod(veh,2,tonumber(t.rearBumper) or -1,false)
    SetVehicleMod(veh,10,tonumber(t.roofIndex) or -1,false)
    SetVehicleMod(veh,4,tonumber(t.exhaustIndex) or -1,false)

    appliedByVehicle[veh]=clone(t)
    durabilityState[veh]={
        level=math.max(0,math.floor(tonumber(t.durabilityLevel) or 0)),
        engine=GetVehicleEngineHealth(veh),
        body=GetVehicleBodyHealth(veh),
    }
end

local function buildDynamicOptions(veh)
    local _,extrasOptions=buildExtras(veh)
    return {
        horn=buildModOptions(veh,14,'경적'),
        frontBumper=buildModOptions(veh,1,'앞범퍼'),
        rearBumper=buildModOptions(veh,2,'뒷범퍼'),
        roof=buildModOptions(veh,10,'루프'),
        exhaust=buildModOptions(veh,4,'배기구'),
        extras=extrasOptions,
    }
end

local function wheelOptions(veh,wheelType)
    local oldType=GetVehicleWheelType(veh)
    local oldIndex=GetVehicleMod(veh,23)

    SetVehicleWheelType(veh,tonumber(wheelType) or oldType)
    local out=buildModOptions(veh,23,'휠')

    SetVehicleWheelType(veh,oldType)
    SetVehicleMod(veh,23,oldIndex,false)

    return out
end

local function destroyCam()
    if tuneCam and DoesCamExist(tuneCam) then
        RenderScriptCams(false,true,250,true,true)
        DestroyCam(tuneCam,false)
    end
    tuneCam=nil
end

local function createCam(veh)
    destroyCam()
    local p=GetOffsetFromEntityInWorldCoords(veh,4.6,6.2,2.2)
    tuneCam=CreateCam('DEFAULT_SCRIPTED_CAMERA',true)
    SetCamCoord(tuneCam,p.x,p.y,p.z)
    PointCamAtEntity(tuneCam,veh,0.0,0.0,0.4,true)
    SetCamFov(tuneCam,48.0)
    RenderScriptCams(true,true,250,true,true)
end

local function closeShop(restore)
    if not shopOpen then return end
    shopOpen=false

    if restore and currentVeh~=0 and DoesEntityExist(currentVeh) and currentTune then
        applyTune(currentVeh,currentTune)
    end

    SetNuiFocus(false,false)
    SendNUIMessage({action='close'})
    destroyCam()

    if currentVeh~=0 and DoesEntityExist(currentVeh) then
        FreezeEntityPosition(currentVeh,false)
    end

    TriggerServerEvent('cookie_tuningshop:server:closeSession')

    currentVeh=0
    currentPlate=''
    currentTune=nil
    baseTune=nil
    previewTune=nil
    repairRequired=false
end

RegisterNetEvent('cookie_tuningshop:client:open',function()
    if shopOpen then return end

    local ped=PlayerPedId()
    local veh=GetVehiclePedIsIn(ped,false)

    if veh==0 then
        return notify('차량을 튜닝 베이에 넣고 운전석에서 이용해주세요.',true)
    end
    if GetPedInVehicleSeat(veh,-1)~=ped then
        return notify('운전석에서만 튜닝샵을 이용할 수 있습니다.',true)
    end
    if GetEntitySpeed(veh)>(Config.InteractMaxSpeed or 3.0) then
        return notify('차량을 정차한 뒤 이용해주세요.',true)
    end

    SetVehicleModKit(veh,0)

    local plate=trimPlate(GetVehicleNumberPlateText(veh))
    local captured=captureTune(veh)
    local condition=captureCondition(veh)

    local data=lib.callback.await('cookie_tuningshop:server:open',false,{
        plate=plate,
        baseTuning=captured,
        damageRequired=condition.required
    })

    if type(data)~='table' or data.ok~=true then
        return notify((type(data)=='table' and data.message) or '튜닝샵을 열 수 없습니다.',true)
    end

    currentVeh=veh
    currentPlate=plate
    baseTune=clone(captured)
    currentTune=clone(data.tuning)
    previewTune=clone(data.tuning)
    repairRequired=data.repairRequired==true
    shopOpen=true

    ensureBase(veh)
    applyTune(veh,currentTune)

    SetEntityVelocity(veh,0.0,0.0,0.0)
    FreezeEntityPosition(veh,true)
    createCam(veh)

    local dynamic=buildDynamicOptions(veh)
    dynamic.wheel=wheelOptions(veh,currentTune.wheelType or 0)

    data.condition=condition
    data.dynamicOptions=dynamic

    SetNuiFocus(true,true)
    SendNUIMessage({action='open',data=data})
end)

RegisterNUICallback('preview',function(data,cb)
    cb({ok=true})
    if not shopOpen or repairRequired or currentVeh==0 or not DoesEntityExist(currentVeh) then return end

    local t=data and data.tuning
    if type(t)~='table' then return end

    previewTune=clone(t)
    applyTune(currentVeh,previewTune)
end)

RegisterNUICallback('wheelOptions',function(data,cb)
    if not shopOpen or currentVeh==0 or not DoesEntityExist(currentVeh) then
        cb({ok=false,options={}})
        return
    end

    cb({
        ok=true,
        options=wheelOptions(currentVeh,tonumber(data and data.wheelType) or 0)
    })
end)

RegisterNUICallback('repair',function(_,cb)
    if not shopOpen or currentVeh==0 or not DoesEntityExist(currentVeh) then
        cb({ok=false,message='차량을 찾을 수 없습니다.'})
        return
    end

    local res=lib.callback.await('cookie_tuningshop:server:repair',false,currentPlate)
    if type(res)=='table' and res.ok then
        doFullRepair(currentVeh)
        repairRequired=false

        local condition=captureCondition(currentVeh)
        res.condition=condition
        res.repairRequired=false

        notify(res.message or '전체 수리가 완료되었습니다.',false)
    end
    cb(type(res)=='table' and res or {ok=false,message='전체 수리에 실패했습니다.'})
end)

RegisterNUICallback('purchase',function(data,cb)
    if not shopOpen or currentVeh==0 or not DoesEntityExist(currentVeh) then
        cb({ok=false,message='튜닝 차량을 찾을 수 없습니다.'})
        return
    end
    if repairRequired then
        cb({ok=false,message='전체 수리를 먼저 진행해주세요.'})
        return
    end

    local t=data and data.tuning
    if type(t)~='table' then
        cb({ok=false,message='튜닝 데이터가 올바르지 않습니다.'})
        return
    end

    local res=lib.callback.await('cookie_tuningshop:server:purchase',false,{
        plate=currentPlate,
        baseTuning=baseTune,
        tuning=t
    })

    if type(res)=='table' and res.ok then
        currentTune=clone(res.tuning)
        previewTune=clone(res.tuning)
        applyTune(currentVeh,currentTune)
        notify(res.message or '튜닝이 완료되었습니다.',false)
        cb(res)
    else
        if currentTune then applyTune(currentVeh,currentTune) end
        previewTune=clone(currentTune)
        cb(type(res)=='table' and res or {ok=false,message='튜닝 결제에 실패했습니다.'})
    end
end)

RegisterNUICallback('resetPreview',function(_,cb)
    cb({ok=true})
    if shopOpen and currentVeh~=0 and currentTune then
        previewTune=clone(currentTune)
        applyTune(currentVeh,currentTune)
    end
end)

RegisterNUICallback('close',function(_,cb)
    cb({ok=true})
    closeShop(true)
end)

CreateThread(function()
    while true do
        if shopOpen then
            DisableControlAction(0,75,true)
            DisableControlAction(0,23,true)
            if IsControlJustPressed(0,200) then closeShop(true) end
            Wait(0)
        else
            Wait(500)
        end
    end
end)

-- 차고 재출고 / 재접속 후 영구 튜닝 재적용.
CreateThread(function()
    local lastVeh=0
    local lastPlate=''

    while true do
        Wait(Config.ApplyCheckMs or 1200)

        if not shopOpen then
            local ped=PlayerPedId()
            local veh=GetVehiclePedIsIn(ped,false)

            if veh~=0 and GetPedInVehicleSeat(veh,-1)==ped then
                local plate=trimPlate(GetVehicleNumberPlateText(veh))
                if veh~=lastVeh or plate~=lastPlate then
                    lastVeh=veh
                    lastPlate=plate
                    ensureBase(veh)

                    local t=lib.callback.await('cookie_tuningshop:server:getByPlate',false,plate)
                    if t then
                        applyTune(veh,t)
                    else
                        -- 저장된 튜닝이 없는 COOKIE 성능 프로필 차량도 순정(0단계) 성능 적용.
                        local profile=getVehiclePerformanceProfile(veh)
                        if profile then
                            local stock=captureTune(veh)
                            stock.engineLevel=0
                            stock.speedLevel=0
                            applyTune(veh,stock)
                        end
                    end
                end
            else
                lastVeh=0
                lastPlate=''
            end
        end
    end
end)

-- COOKIE 내구도 강화: 받은 엔진/차체 손상의 일부를 단계별 복원.
CreateThread(function()
    while true do
        Wait(220)

        for veh,s in pairs(durabilityState) do
            if not DoesEntityExist(veh) then
                durabilityState[veh]=nil
                appliedByVehicle[veh]=nil
                baseHandling[veh]=nil
            elseif s.level and s.level>0 then
                local reduction=(Config.DurabilityReduction and Config.DurabilityReduction[s.level]) or 0.0

                if reduction>0 then
                    local eng=GetVehicleEngineHealth(veh)
                    local body=GetVehicleBodyHealth(veh)

                    if s.engine and eng<s.engine then
                        local loss=s.engine-eng
                        eng=eng+(loss*reduction)
                        SetVehicleEngineHealth(veh,eng)
                    end

                    if s.body and body<s.body then
                        local loss=s.body-body
                        body=body+(loss*reduction)
                        SetVehicleBodyHealth(veh,body)
                    end

                    s.engine=eng
                    s.body=body
                end
            end
        end
    end
end)

AddEventHandler('onResourceStop',function(res)
    if res~=GetCurrentResourceName() then return end
    if shopOpen then closeShop(true) end
end)
