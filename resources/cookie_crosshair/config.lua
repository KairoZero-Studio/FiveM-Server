

Config = Config or {}
Config.Crosshair = {}

Config.Crosshair.Debug = false

Config.Crosshair.Default = {
    custom = true, base = false, adsOnly = true,
    r = 255, g = 255, b = 255, a = 255,
    outline = true, outlineW = 1, outlineA = 255,
    dot = true, dotW = 4, dotA = 255,
    inner = true, inW = 2, inL = 8, inO = 4,
    outer = false, outW = 2, outL = 4, outO = 12,
    ring = false, ringR = 6, ringW = 2,
    top = true,
}

Config.Crosshair.Range = {
    r = { 0, 255 }, g = { 0, 255 }, b = { 0, 255 }, a = { 0, 255 },
    outlineW = { 0, 5 }, outlineA = { 0, 255 },
    dotW = { 1, 10 }, dotA = { 0, 255 },
    inW = { 1, 10 }, inL = { 0, 30 }, inO = { 0, 30 },
    outW = { 1, 10 }, outL = { 0, 30 }, outO = { 0, 50 },
    ringR = { 0, 20 }, ringW = { 1, 10 },
}

Config.Crosshair.Presets = {
    { id = 'dot',        label = '점',         set = { inner = false, outer = false, ring = false, dot = true, dotW = 3, top = true } },
    { id = 'dot_big',    label = '굵은 점',    set = { inner = false, outer = false, ring = false, dot = true, dotW = 5, top = true } },
    { id = 'cross',      label = '십자',       set = { inner = true, inW = 2, inL = 7, inO = 3, outer = false, ring = false, dot = false, top = true } },
    { id = 'cross_dot',  label = '십자+점',    set = { inner = true, inW = 2, inL = 7, inO = 3, outer = false, ring = false, dot = true, dotW = 2, top = true } },
    { id = 'cross_thin', label = '얇은 십자',  set = { inner = true, inW = 1, inL = 9, inO = 4, outer = false, ring = false, dot = false, top = true } },
    { id = 'tshape',     label = 'T자',        set = { inner = true, inW = 2, inL = 7, inO = 3, outer = false, ring = false, dot = false, top = false } },
    { id = 'circle',     label = '원',         set = { inner = false, outer = false, ring = true, ringR = 6, ringW = 2, dot = false, top = true } },
    { id = 'circle_dot', label = '원+점',      set = { inner = false, outer = false, ring = true, ringR = 6, ringW = 2, dot = true, dotW = 2, top = true } },
    { id = 'full',       label = '원+십자+점', set = { inner = true, inW = 2, inL = 6, inO = 8, outer = false, ring = true, ringR = 6, ringW = 2, dot = true, dotW = 2, top = true } },
    { id = 'white_dot',  label = '흰색 점',    set = { inner = false, outer = false, ring = false, dot = true, dotW = 4, top = true } },
}
