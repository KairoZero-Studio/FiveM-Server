local activeBlips = {}
local groupBlips = {}

-- =========================================================
-- nil 여부를 정확하게 처리
-- false도 정상적인 값으로 유지
-- =========================================================

local function pick(value, fallback)
    if value ~= nil then
        return value
    end

    return fallback
end

-- =========================================================
-- 고정 블립 제거
-- =========================================================

local function clearFixedBlips()
    for _, blip in pairs(activeBlips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end

    activeBlips = {}
end

-- =========================================================
-- 그룹 블립 제거
-- =========================================================

local function clearGroupBlips()
    for _, blip in ipairs(groupBlips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end

    groupBlips = {}
end

-- =========================================================
-- 고정 블립 생성
-- =========================================================

local function createFixedBlips()
    clearFixedBlips()

    local defaults = Config.Defaults or {}
    local loaded = 0

    for index, data in ipairs(Config.Blips or {}) do
        local coords = data.coords

        if coords and data.enabled ~= false then
            local blip = AddBlipForCoord(
                coords.x + 0.0,
                coords.y + 0.0,
                coords.z + 0.0
            )

            -- Sprite
            SetBlipSprite(
                blip,
                tonumber(data.sprite) or 1
            )

            -- Display
            SetBlipDisplay(
                blip,
                tonumber(data.display)
                    or tonumber(defaults.display)
                    or 4
            )

            -- Scale
            SetBlipScale(
                blip,
                (
                    tonumber(data.scale)
                    or tonumber(defaults.scale)
                    or 0.80
                ) + 0.0
            )

            -- Colour
            SetBlipColour(
                blip,
                tonumber(data.colour)
                    or tonumber(defaults.colour)
                    or 0
            )

            -- Short Range
            local shortRange = pick(
                data.shortRange,
                defaults.shortRange
            )

            SetBlipAsShortRange(
                blip,
                shortRange == true
            )

            -- Route
            local route = pick(
                data.route,
                defaults.route
            )

            SetBlipRoute(
                blip,
                route == true
            )

            if route == true then
                SetBlipRouteColour(
                    blip,
                    tonumber(data.routeColour)
                        or tonumber(defaults.routeColour)
                        or 0
                )
            end

            -- Name
            BeginTextCommandSetBlipName('STRING')

            AddTextComponentSubstringPlayerName(
                data.label
                    or ('COOKIE BLIP ' .. index)
            )

            EndTextCommandSetBlipName(blip)

            activeBlips[
                data.id or tostring(index)
            ] = blip

            loaded = loaded + 1
        end
    end

    print(
        ('[cookie_mapblips] %d fixed blip(s) loaded')
        :format(loaded)
    )
end

-- =========================================================
-- 그룹 블립 생성
--
-- 134~254의 unnamed category를 사용
--
-- AddTextEntry("BLIP_CAT_...")
-- 절대 사용하지 않음.
-- =========================================================

local function createGroupBlips()
    clearGroupBlips()

    local defaults = Config.Defaults or {}
    local loaded = 0

    for groupKey, group in pairs(Config.BlipGroups or {}) do

        local groupCategory =
            tonumber(group.category)

        for index, location in ipairs(group.locations or {}) do

            local coords = location.coords

            if coords and location.enabled ~= false then

                local blip = AddBlipForCoord(
                    coords.x + 0.0,
                    coords.y + 0.0,
                    coords.z + 0.0
                )

                -- =========================================
                -- Sprite
                -- =========================================

                SetBlipSprite(
                    blip,
                    tonumber(location.sprite)
                        or tonumber(group.sprite)
                        or 1
                )

                -- =========================================
                -- Display
                -- =========================================

                SetBlipDisplay(
                    blip,
                    tonumber(location.display)
                        or tonumber(group.display)
                        or tonumber(defaults.display)
                        or 4
                )

                -- =========================================
                -- Scale
                -- =========================================

                SetBlipScale(
                    blip,
                    (
                        tonumber(location.scale)
                        or tonumber(group.scale)
                        or tonumber(defaults.scale)
                        or 0.80
                    ) + 0.0
                )

                -- =========================================
                -- Colour
                -- =========================================

                SetBlipColour(
                    blip,
                    tonumber(location.colour)
                        or tonumber(group.colour)
                        or tonumber(defaults.colour)
                        or 0
                )

                -- =========================================
                -- Short Range
                -- =========================================

                local shortRange = pick(
                    location.shortRange,
                    pick(
                        group.shortRange,
                        defaults.shortRange
                    )
                )

                SetBlipAsShortRange(
                    blip,
                    shortRange == true
                )

                -- =========================================
                -- 그룹화
                --
                -- 134 = 차고지
                -- 135 = 편의점
                -- 136 = ATM
                --
                -- 카테고리 이름은 등록하지 않음.
                -- =========================================

                local category =
                    tonumber(location.category)
                    or groupCategory

                if category then
                    SetBlipCategory(
                        blip,
                        category
                    )
                end

                -- =========================================
                -- Route
                -- =========================================

                local route = pick(
                    location.route,
                    pick(
                        group.route,
                        defaults.route
                    )
                )

                SetBlipRoute(
                    blip,
                    route == true
                )

                if route == true then
                    SetBlipRouteColour(
                        blip,
                        tonumber(location.routeColour)
                            or tonumber(group.routeColour)
                            or tonumber(defaults.routeColour)
                            or 0
                    )
                end

                -- =========================================
                -- 개별 위치 이름
                -- =========================================

                BeginTextCommandSetBlipName('STRING')

                AddTextComponentSubstringPlayerName(
                    location.label
                        or group.label
                        or (
                            groupKey
                            .. ' '
                            .. tostring(index)
                        )
                )

                EndTextCommandSetBlipName(blip)

                groupBlips[
                    #groupBlips + 1
                ] = blip

                loaded = loaded + 1
            end
        end
    end

    print(
        ('[cookie_mapblips] %d grouped blip(s) loaded')
        :format(loaded)
    )
end

-- =========================================================
-- 전체 새로고침
-- =========================================================

local function reloadAllBlips()
    createFixedBlips()
    createGroupBlips()

    print(
        '[cookie_mapblips] all blips reloaded'
    )
end

-- =========================================================
-- 리소스 시작
-- =========================================================

CreateThread(function()
    Wait(500)

    reloadAllBlips()
end)

-- =========================================================
-- 현재 좌표 확인
--
-- /blippos
-- =========================================================

RegisterCommand('blippos', function()

    local ped =
        PlayerPedId()

    local coords =
        GetEntityCoords(ped)

    local heading =
        GetEntityHeading(ped)

    local message =
        ('vec3(%.2f, %.2f, %.2f) / heading %.2f')
        :format(
            coords.x,
            coords.y,
            coords.z,
            heading
        )

    print(
        '[cookie_mapblips] '
        .. message
    )

    TriggerEvent(
        'chat:addMessage',
        {
            color = {
                255,
                210,
                80
            },

            args = {
                'COOKIE BLIP',
                message
            }
        }
    )
end, false)

-- =========================================================
-- 맵 블립 다시 불러오기
--
-- /cookieblips
-- =========================================================

RegisterCommand('cookieblips', function()

    reloadAllBlips()

    TriggerEvent(
        'chat:addMessage',
        {
            color = {
                100,
                255,
                120
            },

            args = {
                'COOKIE BLIP',
                '맵 블립을 다시 불러왔습니다.'
            }
        }
    )
end, false)

-- =========================================================
-- 리소스 종료 시 정리
-- =========================================================

AddEventHandler(
    'onResourceStop',
    function(resourceName)

        if resourceName ~= GetCurrentResourceName() then
            return
        end

        clearFixedBlips()
        clearGroupBlips()
    end
)