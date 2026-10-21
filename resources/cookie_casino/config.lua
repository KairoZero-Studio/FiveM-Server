

Config = {}

Config.Debug = false

Config.Chip = 'casino_chip'

Config.Exchange = {
    chipPrice    = 100,
    minChips     = 1,
    maxChips     = 10000,

    buyAccount   = 'cash',
    sellAccount  = 'cash',

    useRenewedBankForBank = true,
}

Config.Tables = {
    [1] = {
        label  = '블랙잭 테이블 1',
        dealer = vec4(925.0, 46.0, 81.1, 240.0),
        seats  = {
            vec4(926.2, 47.0, 81.1, 60.0),

        },
        minBet = 10,
        maxBet = 500,
        target = {
            radius = 1.2,
        },
    },
}

function CasinoLog(event, data)
    if not Config.Debug then return end
    local parts = {}
    if type(data) == 'table' then
        for k, v in pairs(data) do
            parts[#parts + 1] = ('%s=%s'):format(k, tostring(v))
        end
    end

end
