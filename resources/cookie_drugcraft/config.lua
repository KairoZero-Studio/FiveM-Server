Config = {}

Config.RequireCrimeFaction = true
Config.InteractDistance = 2.2
Config.MarkerDistance = 30.0
Config.CancelDistance = 18.0
Config.AdminMinLevel = 3
Config.AdminAce = 'cookie.drugcraft.admin'

Config.DefaultBaseSeconds = 20
Config.DefaultBoostSeconds = 8
Config.OrganizationBaseSeconds = 15
Config.OrganizationBoostSeconds = 5

Config.Marker = {
    type = 1,
    scale = vector3(1.35, 1.35, 0.28),
    color = { r = 160, g = 65, b = 230, a = 150 }
}

Config.Recipes = {
    cocaine = {
        label = '코카인',
        rawItem = 'crime_cocaine_raw',
        outputItem = 'crime_cocaine',
        rawPerBatch = 5,
        outputPerBatch = 1,
        minigame = 'cocaine',
    },
    cannabis = {
        label = '대마초',
        rawItem = 'crime_cannabis_raw',
        outputItem = 'crime_cannabis',
        rawPerBatch = 5,
        outputPerBatch = 1,
        minigame = 'cannabis',
    },
    meth = {
        label = '필로폰',
        rawItem = 'crime_meth_raw',
        outputItem = 'crime_meth',
        rawPerBatch = 5,
        outputPerBatch = 1,
        minigame = 'meth',
    },
    heroin = {
        label = '헤로인',
        rawItem = 'crime_heroin_raw',
        outputItem = 'crime_heroin',
        rawPerBatch = 5,
        outputPerBatch = 1,
        minigame = 'heroin',
    },
}
