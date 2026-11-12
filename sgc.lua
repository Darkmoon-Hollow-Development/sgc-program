-- Stargate Command dialing computer, by Darkmoon Hollow (also built into the Eclipse Gate mod)
-- For Just Stargate Mod + CC: Tweaked. Install: pastebin get <code> sgc   or   wget <link> sgc
-- An SGC-style dialing screen for a Just Stargate Mod gate: the gate and its chevrons, the address being dialed,
-- an address book, the iris and IDC codes. The address book and IDC list are kept on this computer in /sgc/data.

local DATA = "/sgc/data"
local ORIGIN = { "Point of Origin", "Point of origin", 0 }

local gate, gateName = nil, nil
local mon = nil

-- ------------------------------------------------------------------ saved data

local data = {
    book = {},
    idc = {},          -- code -> { name = "SG-1", allow = true }
    autoIris = true,
    alarm = true,      -- the base alert: the computer's redstone (and the lamps beside it) flash on an incoming wormhole
    history = {},      -- name -> { count, last } for every address that's been dialed
}

local function loadData()
    if not fs.exists(DATA) then return end
    local f = fs.open(DATA, "r")
    local loaded = textutils.unserialize(f.readAll())
    f.close()
    if type(loaded) == "table" then
        data.book = loaded.book or data.book
        data.idc = loaded.idc or data.idc
        if loaded.autoIris ~= nil then data.autoIris = loaded.autoIris end
        data.gdo = loaded.gdo
        if loaded.alarm ~= nil then data.alarm = loaded.alarm end
        data.history = loaded.history or {}
        data.last = loaded.last
    end
end

local function save()
    local f = fs.open(DATA, "w")
    f.write(textutils.serialize(data))
    f.close()
end

-- Every Stargate in the world, written to /sgc/gates by the Eclipse Gate mod on its SGC's own computer (without
-- Eclipse Gate there's no such file, and only the address book is listed): a list of
-- { name, dim, x, y, z, symbols = { 8 Milky Way symbols } }, the SGC's own gate marked here = true. The others are
-- shown after the address book, and dialed like it.
local network = {}
local home = nil
local networkRead = -100

local function loadNetwork()
    if os.clock() - networkRead < 10 then return end
    networkRead = os.clock()
    if not fs.exists("/sgc/gates") then return end
    local f = fs.open("/sgc/gates", "r")
    local list = textutils.unserialize(f.readAll())
    f.close()
    if type(list) == "table" then
        network, home = {}, nil
        for _, e in ipairs(list) do
            if e.here then home = e else table.insert(network, e) end
        end
    end
end

-- The address book, then every gate from the network that isn't in it already. A book entry that matches a network
-- gate on its first six symbols takes that gate's full address, so a gate in another galaxy can be dialed too.
local function firstSix(symbols)
    local six = {}
    for k = 1, 6 do six[k] = string.lower(tostring(symbols[k] or "")) end
    return table.concat(six, ",")
end

local function entries()
    local out, used = {}, {}
    local byKey = {}
    for n, e in ipairs(network) do byKey[firstSix(e.symbols)] = n end
    for b, e in ipairs(data.book) do
        local n = byKey[firstSix(e.symbols)]
        if n then
            used[n] = true
            local g = network[n]
            table.insert(out, { name = e.name, symbols = g.symbols, book = b, dim = g.dim, x = g.x, y = g.y, z = g.z })
        else
            table.insert(out, { name = e.name, symbols = e.symbols, book = b })
        end
    end
    for n, e in ipairs(network) do
        if not used[n] then
            table.insert(out, { name = e.name, symbols = e.symbols, network = true, dim = e.dim, x = e.x, y = e.y, z = e.z })
        end
    end
    return out
end

-- ------------------------------------------------------------------ finding the gate and the screen

local function findDevices()
    gate, gateName = nil, nil
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "stargate" then
            gate, gateName = peripheral.wrap(name), name
            break
        end
    end
    -- the biggest monitor, if there are several
    mon = nil
    local best = 0
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "monitor" then
            local m = peripheral.wrap(name)
            m.setTextScale(0.5)
            local w, h = m.getSize()
            if w * h > best then
                best = w * h
                mon = m
            end
        end
    end
end

-- ------------------------------------------------------------------ the gate

local state = {
    status = "", iris = "", energy = 0, message = "STANDING BY", detail = "",
    address = {}, locked = 0, total = 0,       -- the address being dialed, and how many chevrons are locked
    incoming = false, open = false, dialing = nil, autoClosed = false, error = nil,
}

-- Calls a gate method safely: returns ok, first result, and a message on failure.
local function call(method, ...)
    if not gate then return false, nil, "NO STARGATE CONNECTED" end
    local r = table.pack(pcall(gate[method], ...))
    if not r[1] then return false, nil, tostring(r[2]) end
    if r[2] == false then return false, r[3], tostring(r[4] or r[3] or "failed") end
    return true, r[2], nil
end

-- The value a gate method answers with. JSG's methods answer either with the value itself, or with true and then the
-- value (and false and a reason when they can't): this gives the value either way, or nil.
local function ask(method, ...)
    if not gate or not gate[method] then return nil end
    local r = table.pack(pcall(gate[method], ...))
    if not r[1] or r[2] == false then return nil end
    if r[2] == true and r.n >= 3 then return table.unpack(r, 3, r.n) end
    return table.unpack(r, 2, r.n)
end

-- For the methods that answer true, a key naming the answer, and then the value (symbols_needed, energy_map,
-- stargate_time): the value.
local function keyed(method, ...)
    local r = table.pack(ask(method, ...))
    if type(r[1]) == "string" and r.n >= 2 then return table.unpack(r, 2, r.n) end
    return table.unpack(r, 1, r.n)
end

local function irisClosed()
    local s = string.upper(state.iris or "")
    return string.find(s, "CLOS") ~= nil
end

local function dialedCount()
    local d = ask("getDialedAddress")
    if type(d) == "table" then return #d end
    return nil
end

local function refresh()
    loadNetwork()
    if not gate then findDevices() end
    if not gate then
        state.status = "NO STARGATE"
        return
    end
    local s = ask("getGateStatus")
    state.status = s and string.upper(tostring(s)) or "?"
    s = ask("getIrisState")
    state.iris = s and string.upper(tostring(s)) or "NONE"
    state.energy = tonumber(ask("getEnergyStored")) or 0
    state.maxEnergy = tonumber(ask("getMaxEnergyStored")) or state.maxEnergy or 0
    state.open = string.find(state.status, "OPEN") ~= nil or string.find(state.status, "ENGAGED") ~= nil
    if state.open and not state.openedAt then
        local mins, secs = keyed("getOpenedTime")
        state.openedAt = os.clock() - ((tonumber(mins) or 0) * 60 + (tonumber(secs) or 0))
    end
    if not state.open then state.openedAt = nil end
end

local function setIris(closed)
    refresh()
    if irisClosed() == closed then return true end
    local ok, _, err = call("toggleIris")
    if not ok then state.detail = "IRIS: " .. string.upper(err) end
    return ok
end

-- ------------------------------------------------------------------ drawing helpers (for the computer's own screen)

local function fillRect(t, x1, y1, x2, y2, bg)
    t.setBackgroundColor(bg)
    local w = x2 - x1 + 1
    if w <= 0 then return end
    local blank = string.rep(" ", w)
    for y = y1, y2 do
        t.setCursorPos(x1, y)
        t.write(blank)
    end
end

local function text(t, x, y, s, fg, bg)
    t.setCursorPos(x, y)
    if bg then t.setBackgroundColor(bg) end
    t.setTextColor(fg or colors.white)
    t.write(s)
end

-- ------------------------------------------------------------------ the wall screen: a pixel canvas
-- Each character cell is 2x3 "pixels" (CC's teletext characters 128-159), so the gate, its chevrons and the lines
-- can be drawn finely; text is laid over the top cell by cell.

local Canvas = {}
Canvas.__index = Canvas

local function newCanvas(cw, ch)
    local c = setmetatable({ cw = cw, ch = ch, pw = cw * 2, ph = ch * 3, px = {}, txt = {} }, Canvas)
    for i = 1, c.pw * c.ph do c.px[i] = colors.black end
    return c
end

function Canvas:set(x, y, colour)
    x, y = math.floor(x + 0.5), math.floor(y + 0.5)
    if x < 1 or y < 1 or x > self.pw or y > self.ph then return end
    self.px[(y - 1) * self.pw + x] = colour
end

function Canvas:line(x1, y1, x2, y2, colour)
    local steps = math.max(math.abs(x2 - x1), math.abs(y2 - y1), 1)
    for i = 0, steps do
        self:set(x1 + (x2 - x1) * i / steps, y1 + (y2 - y1) * i / steps, colour)
    end
end

function Canvas:rect(x1, y1, x2, y2, colour)
    self:line(x1, y1, x2, y1, colour)
    self:line(x1, y2, x2, y2, colour)
    self:line(x1, y1, x1, y2, colour)
    self:line(x2, y1, x2, y2, colour)
end

function Canvas:fill(x1, y1, x2, y2, colour)
    for y = math.floor(y1), math.floor(y2) do
        for x = math.floor(x1), math.floor(x2) do self:set(x, y, colour) end
    end
end

function Canvas:circle(cx, cy, r, colour)
    local steps = math.max(24, math.floor(r * 8))
    for i = 0, steps do
        local a = i / steps * math.pi * 2
        self:set(cx + math.cos(a) * r, cy + math.sin(a) * r, colour)
    end
end

function Canvas:disc(cx, cy, r, colourAt)
    for y = math.floor(cy - r), math.ceil(cy + r) do
        for x = math.floor(cx - r), math.ceil(cx + r) do
            local dx, dy = x - cx, y - cy
            local d = math.sqrt(dx * dx + dy * dy)
            if d <= r then self:set(x, y, colourAt(d, dx, dy)) end
        end
    end
end

-- a thin ring, crisp: every pixel whose distance from the middle rounds to r
function Canvas:ring(cx, cy, r, colour)
    for y = math.floor(cy - r - 1), math.ceil(cy + r + 1) do
        for x = math.floor(cx - r - 1), math.ceil(cx + r + 1) do
            local d = math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2)
            if math.abs(d - r) < 0.5 then self:set(x, y, colour) end
        end
    end
end

-- a filled triangle
function Canvas:triangle(x1, y1, x2, y2, x3, y3, colour)
    local minX, maxX = math.floor(math.min(x1, x2, x3)), math.ceil(math.max(x1, x2, x3))
    local minY, maxY = math.floor(math.min(y1, y2, y3)), math.ceil(math.max(y1, y2, y3))
    local function side(ax, ay, bx, by, px, py) return (bx - ax) * (py - ay) - (by - ay) * (px - ax) end
    for y = minY, maxY do
        for x = minX, maxX do
            local d1, d2, d3 = side(x1, y1, x2, y2, x, y), side(x2, y2, x3, y3, x, y), side(x3, y3, x1, y1, x, y)
            local neg = d1 < 0 or d2 < 0 or d3 < 0
            local pos = d1 > 0 or d2 > 0 or d3 > 0
            if not (neg and pos) then self:set(x, y, colour) end
        end
    end
end

-- clears a box (in pixels) to a colour, taking away any text over it too: for windows drawn over the screen
function Canvas:clear(x1, y1, x2, y2, colour)
    self:fill(x1, y1, x2, y2, colour)
    for cy = math.floor((y1 - 1) / 3) + 1, math.floor((y2 - 1) / 3) + 1 do
        for cx = math.floor((x1 - 1) / 2) + 1, math.floor((x2 - 1) / 2) + 1 do
            self.txt[(cy - 1) * self.cw + cx] = nil
        end
    end
end

-- text over the canvas, in character cells
function Canvas:text(x, y, s, fg, bg)
    for i = 1, #s do
        local cx = x + i - 1
        if cx >= 1 and cx <= self.cw and y >= 1 and y <= self.ch then
            self.txt[(y - 1) * self.cw + cx] = { string.sub(s, i, i), fg or colors.white, bg or colors.black }
        end
    end
end

-- A 3x5 pixel font for the big status word.
local FONT = {
    A = "010101111101101", B = "110101110101110", C = "011100100100011", D = "110101101101110", E = "111100110100111",
    F = "111100110100100", G = "011100101101011", H = "101101111101101", I = "111010010010111", J = "001001001101010",
    K = "101101110101101", L = "100100100100111", M = "101111111101101", N = "110101101101101", O = "010101101101010",
    P = "110101110100100", Q = "010101101110011", R = "110101110101101", S = "011100010001110", T = "111010010010010",
    U = "101101101101111", V = "101101101101010", W = "101101111111101", X = "101101010101101", Y = "101101010010010",
    Z = "111001010100111", ["0"] = "111101101101111", ["1"] = "010110010010111", ["2"] = "110001010100111",
    ["3"] = "110001010001110", ["4"] = "101101111001001", ["5"] = "111100110001110", ["6"] = "011100111101111",
    ["7"] = "111001010010010", ["8"] = "111101111101111", ["9"] = "111101111001110", [" "] = "000000000000000",
    ["-"] = "000000111000000",
}

function Canvas:bigText(cx, y, s, scale, colour)
    local width = (#s * 4 - 1) * scale
    local x = math.floor(cx - width / 2)
    for i = 1, #s do
        local g = FONT[string.sub(s, i, i)] or FONT[" "]
        for row = 0, 4 do
            for col = 0, 2 do
                if string.sub(g, row * 3 + col + 1, row * 3 + col + 1) == "1" then
                    self:fill(x + col * scale, y + row * scale, x + col * scale + scale - 1, y + row * scale + scale - 1, colour)
                end
            end
        end
        x = x + 4 * scale
    end
end

-- Draws the canvas onto a monitor with blit: two colours per cell, the teletext character for its six pixels.
function Canvas:draw(t)
    local hex = {}
    for i = 0, 15 do hex[2 ^ i] = string.sub("0123456789abcdef", i + 1, i + 1) end
    for cy = 1, self.ch do
        local chars, fgs, bgs = {}, {}, {}
        for cx = 1, self.cw do
            local over = self.txt[(cy - 1) * self.cw + cx]
            if over then
                chars[cx], fgs[cx], bgs[cx] = over[1], hex[over[2]], hex[over[3]]
            else
                local p = {}
                local base = (cy - 1) * 3
                for k = 0, 5 do
                    local px = (cx - 1) * 2 + 1 + (k % 2)
                    local py = base + 1 + math.floor(k / 2)
                    p[k + 1] = self.px[(py - 1) * self.pw + px]
                end
                local bg = p[6]
                local fg = bg
                for k = 1, 5 do if p[k] ~= bg then fg = p[k] break end end
                local bits = 0
                for k = 1, 5 do if p[k] == fg and fg ~= bg then bits = bits + 2 ^ (k - 1) end end
                if bits == 0 then
                    chars[cx], fgs[cx], bgs[cx] = " ", hex[bg], hex[bg]
                else
                    chars[cx], fgs[cx], bgs[cx] = string.char(128 + bits), hex[fg], hex[bg]
                end
            end
        end
        t.setCursorPos(1, cy)
        t.blit(table.concat(chars), table.concat(fgs), table.concat(bgs))
    end
end

local buttons = {}
local function addButton(x1, y1, x2, y2, action)
    table.insert(buttons, { x1, y1, x2, y2, action })
end

-- Chevrons around the ring, clockwise from the top, as on the SGC's gate: 7 at the top, 1-3 down the right,
-- 8 and 9 at the bottom, 4-6 up the left. The order they lock in for 7, 8 and 9 symbols.
local CHEVRON_ANGLE = { [7] = 0, [1] = 40, [2] = 80, [3] = 120, [8] = 160, [9] = 200, [4] = 240, [5] = 280, [6] = 320 }
local function lockOrder(total)
    local order = { 1, 2, 3, 4, 5, 6 }
    if total >= 8 then table.insert(order, 8) end
    if total >= 9 then table.insert(order, 9) end
    table.insert(order, 7)                        -- the point of origin always locks chevron 7
    return order
end

function Canvas:triOutline(x1, y1, x2, y2, x3, y3, colour)
    self:line(x1, y1, x2, y2, colour)
    self:line(x2, y2, x3, y3, colour)
    self:line(x3, y3, x1, y1, colour)
end

-- the gate: double cyan rings with the 39 glyph positions ticked between them, nine chevrons (red outlines, filled
-- red once locked, the top one flashing as it clamps); in the middle the orange core when idle, the event horizon,
-- or the iris's vanes
local function drawGate(c, cx, cy, r, blink, tick)
    local lit = {}
    local order = lockOrder(math.max(state.total, 7))
    for i = 1, math.min(state.locked, #order) do lit[order[i]] = true end
    if state.open and state.total == 0 then for k in pairs(CHEVRON_ANGLE) do lit[k] = true end end
    local inner = r - 7
    if irisClosed() then
        c:disc(cx, cy, inner, function(d, dx, dy)
            local a = (math.deg(math.atan2(dy, dx)) + 360 + d * 9) % 360
            if d > inner - 1 then return colors.gray end
            return (math.floor(a / 18) % 2 == 0) and colors.lightGray or colors.gray      -- twenty vanes in a spiral
        end)
    elseif state.open then
        c:disc(cx, cy, inner, function(d, dx, dy)
            local a = math.deg(math.atan2(dy, dx))
            local wave = (d * 0.9 + math.sin(math.rad(a * 3 + tick * 40)) * 0.8 + tick * 0.6) % 4
            if d < 1.5 then return colors.white end
            if wave < 0.9 then return colors.lightBlue end
            if wave < 1.4 and d < inner * 0.6 then return colors.white end
            return colors.blue
        end)
    else
        local pulse = 1.6 + (tick % 4) * 0.35
        c:disc(cx, cy, pulse + 1.2, function(d)
            if d < pulse * 0.5 then return colors.yellow end
            if d < pulse then return colors.orange end
            return colors.red
        end)
    end
    -- the rings and the 39 glyph positions
    c:ring(cx, cy, r, colors.cyan)
    c:ring(cx, cy, r - 1, colors.cyan)
    c:ring(cx, cy, r - 5, colors.cyan)
    c:ring(cx, cy, inner, colors.cyan)
    for i = 0, 38 do
        local a = math.rad(i * 360 / 39)
        c:line(cx + math.sin(a) * (r - 2), cy - math.cos(a) * (r - 2), cx + math.sin(a) * (r - 4), cy - math.cos(a) * (r - 4), colors.gray)
    end
    -- HUD brackets round the gate
    local b = r + 7
    for _, sx in ipairs({ -1, 1 }) do
        for _, sy in ipairs({ -1, 1 }) do
            c:line(cx + sx * b, cy + sy * b, cx + sx * (b - 6), cy + sy * b, colors.cyan)
            c:line(cx + sx * b, cy + sy * b, cx + sx * b, cy + sy * (b - 6), colors.cyan)
        end
    end
    -- the chevrons
    for k, deg in pairs(CHEVRON_ANGLE) do
        local a = math.rad(deg)
        local sx, sy = math.sin(a), -math.cos(a)            -- out from the middle
        local tx, ty = -sy, sx                              -- along the ring
        local locking = (k == 7 and state.dialing and state.locked == state.total - 1 and state.total > 0)
        local colour = colors.red
        if locking and blink then colour = colors.yellow end
        local ox, oy = cx + sx * (r + 3), cy + sy * (r + 3)
        local ix, iy = cx + sx * (r - 3), cy + sy * (r - 3)
        if lit[k] then
            c:triangle(ox + tx * 4, oy + ty * 4, ox - tx * 4, oy - ty * 4, ix, iy, colour)
            local nx, ny = cx + sx * (r + 3.5), cy + sy * (r + 3.5)
            c:triangle(nx + tx * 2, ny + ty * 2, nx - tx * 2, ny - ty * 2, cx + sx * (r - 0.5), cy + sy * (r - 0.5), colors.black)
        else
            c:triOutline(ox + tx * 4, oy + ty * 4, ox - tx * 4, oy - ty * 4, ix, iy, locking and colour or colors.red)
        end
    end
end

-- ------------------------------------------------------------------ the event log

-- What the gate has done, with the day and time: shown on the EVENT LOG page (KEYBOARD, or the LOG button) and the
-- computer's own screen. Kept in /sgc/log, so it's still there after a restart; the last 200 events.
local LOG = "/sgc/log"
local log = {}
local logScroll = 0                  -- how many events back from the newest the EVENT LOG page is showing

if fs.exists(LOG) then
    local f = fs.open(LOG, "r")
    local loaded = textutils.unserialize(f.readAll())
    f.close()
    if type(loaded) == "table" then log = loaded end
end

local function logEvent(short, long, colour)
    local t = ""
    if textutils and textutils.formatTime and os.time then t = textutils.formatTime(os.time(), true) end
    if #t == 4 then t = "0" .. t end
    local day = os.day and os.day() or nil
    table.insert(log, { t = t, day = day, short = string.upper(short), long = string.upper(long or short), c = colour or colors.lightBlue })
    while #log > 200 do table.remove(log, 1) end
    if logScroll > 0 then logScroll = logScroll + 1 end           -- keep looking at the same events
    local f = fs.open(LOG, "w")
    if f then
        f.write(textutils.serialize(log))
        f.close()
    end
end

local WORDS = { "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE" }

-- The 37 Milky Way glyphs that can be dialed (the point of origin ends every address), in alphabetical order.
local GLYPHS = {
    "Andromeda", "Aquarius", "Aries", "Auriga", "Bootes", "Cancer", "Canis Minor", "Capricornus", "Centaurus", "Cetus",
    "Corona Australis", "Crater", "Equuleus", "Eridanus", "Gemini", "Hydra", "Leo", "Leo Minor", "Libra", "Lynx",
    "Microscopium", "Monoceros", "Norma", "Orion", "Pegasus", "Perseus", "Pisces", "Piscis Austrinus", "Sagittarius",
    "Sculptor", "Scorpius", "Scutum", "Serpens Caput", "Sextans", "Taurus", "Triangulum", "Virgo",
}

local function fe(n)
    n = tonumber(n) or 0
    if n >= 1e9 then return string.format("%.1fG", n / 1e9) end
    if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
    if n >= 1e3 then return string.format("%.1fK", n / 1e3) end
    return tostring(math.floor(n))
end

local function dimName(dim)
    if not dim then return "" end
    local known = {
        ["minecraft:overworld"] = "OVERWORLD", ["minecraft:the_nether"] = "THE NETHER", ["minecraft:the_end"] = "THE END",
        ["eclipsegate:moonlit_hollow"] = "THE MOONLIT HOLLOW",
    }
    if known[dim] then return known[dim] end
    local planet = string.match(dim, "^gtg:(.+)$")                  -- a Galactic Gates planet: P3X-888, Kresh Tar
    if planet then
        if string.match(planet, "^p%w%w_%d+$") then return "PLANET " .. string.upper(string.gsub(planet, "_", "-")) end
        return "PLANET " .. string.upper(string.gsub(planet, "_", " "))
    end
    local path = string.gsub(string.gsub(dim, "^.-:", ""), "_", " ")
    return string.upper(path)
end

local function clockText(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function pad(s, n)
    s = string.sub(s or "", 1, math.max(0, n))
    return s .. string.rep(" ", math.max(0, n - #s))
end

-- What the gate says about dialing an address: how many of its symbols it needs from here, and the power to open
-- and hold the wormhole. Asked again every few seconds at most.
local info = { key = nil, t = -100 }
local function gateInfo(symbols)
    local key = table.concat(symbols, ",")
    if info.key == key and os.clock() - info.t < 3 then return info end
    info = { key = key, t = os.clock() }
    if not gate or #symbols < 6 then return info end
    local n = tonumber(keyed("getSymbolsNeeded", symbols))
    if n then info.needed = math.max(6, math.min(#symbols, n - 1)) else info.missing = true end
    local use = {}
    for k = 1, math.min(#symbols, info.needed or 6) do use[k] = symbols[k] end
    local power = keyed("getEnergyRequiredToDial", use)
    if type(power) == "table" then info.power = power end
    return info
end

-- This gate: its own address, the iris, capacitors, how long the wormhole's been open. Asked every couple of seconds.
local selfInfo = { t = -100 }
local function homeInfo()
    if os.clock() - selfInfo.t < 2 then return selfInfo end
    selfInfo = { t = os.clock() }
    local addresses = ask("getStargateAddress")
    if type(addresses) == "table" then
        for k, v in pairs(addresses) do
            if type(v) == "table" and string.find(string.lower(tostring(k)), "milky") then selfInfo.address = v end
        end
        if not selfInfo.address then
            for _, v in pairs(addresses) do
                if type(v) == "table" and #v >= 6 then selfInfo.address = v break end
            end
        end
    end
    if not selfInfo.address and home then selfInfo.address = home.symbols end
    selfInfo.type = ask("getGateType")
    selfInfo.irisType = ask("getIrisType")
    local _, damage, max = ask("getIrisDurability")
    selfInfo.irisDamage, selfInfo.irisMax = tonumber(damage), tonumber(max)
    selfInfo.capacitors = tonumber(ask("getCapacitorsInstalled"))
    local mins, secs = keyed("getOpenedTime")
    if tonumber(mins) then selfInfo.openFor = tonumber(mins) * 60 + (tonumber(secs) or 0) end
    return selfInfo
end

-- ------------------------------------------------------------------ the screens

local blink = false
local tick = 0
local actions = {}
local overlay = false                -- the KEYBOARD overlay: the address book, manual dialing, IDC codes, the gate
local page = "book"
local bookScroll, bookSel = 0, 1
local idcScroll = 0
local manual = {}                    -- the address being put together glyph by glyph on the MANUAL DIAL page
local hexes = {}

local function hexLine(n)
    local s = ""
    for _ = 1, n do s = s .. string.format("%X", math.random(0, 15)) end
    return s
end

-- a frame round the character cells a..b on row r (the cells either side, and the rows above and below, stay clear)
local function box(c, a, b, r, colour)
    c:rect((a - 1) * 2, (r - 1) * 3, b * 2 + 1, r * 3 + 1, colour)
end

local function button(c, x, y, label, bg, fg, action)
    c:text(x, y, " " .. label .. " ", fg or colors.black, bg)
    addButton(x, y, x + #label + 1, y, action)
    return x + #label + 3
end

-- An address in framed boxes, chevron by chevron, in `cols` columns filled top to bottom; the point of origin last.
-- Symbols past `needed` (the 7th and 8th, only for farther gates) are dimmed. Returns the first row under it.
local function drawAddress(c, x1, x2, row, symbols, cols, needed)
    local list = {}
    for k = 1, #symbols do
        if not needed or k <= needed then table.insert(list, { k, symbols[k] }) end
    end
    table.insert(list, { #list + 1, "Point of Origin" })
    if needed then
        for k = needed + 1, #symbols do table.insert(list, { "-", symbols[k], true }) end
    end
    local per = math.max(cols == 2 and 4 or 1, math.ceil(#list / cols))
    local width = math.floor((x2 - x1 + 1) / cols)
    for i, item in ipairs(list) do
        local col = math.floor((i - 1) / per)
        local r = row + ((i - 1) % per) * 2
        local a = x1 + 1 + col * width
        local b = a + width - 3
        local origin = item[2] == "Point of Origin"
        local label = tostring(item[1]) .. " " .. string.upper(origin and "Point of Origin" or item[2])
        local fg = item[3] and colors.gray or (origin and colors.orange or colors.white)
        c:text(a, r, pad(label, b - a + 1), fg)
        box(c, a, b, r, colors.cyan)          -- one colour for every frame: neighbouring frames share character cells
    end
    return row + per * 2
end

-- the KEYBOARD overlay's pages
local function drawOverlay(c, W, H, PW, PH, frame)
    local o1, o2 = 10, PW - 10
    local p1, p2 = 8, PH - 10
    c:clear(o1, p1, o2, p2, colors.black)
    c:rect(o1, p1, o2, p2, frame)
    c:rect(o1 + 1, p1 + 1, o2 - 1, p2 - 1, frame)
    local X1, X2 = 7, math.floor(o2 / 2) - 2           -- the text area, in characters
    local top, bottom = 6, math.floor(p2 / 3) - 1      -- the first content row, and the buttons' row

    -- the tabs
    local tx = X1
    for _, t in ipairs({ { "book", "ADDRESS BOOK" }, { "manual", "MANUAL DIAL" }, { "idc", "IDC CODES" }, { "gate", "GATE STATUS" }, { "log", "EVENT LOG" } }) do
        local on = page == t[1]
        local id = t[1]
        tx = button(c, tx, 4, t[2], on and colors.cyan or colors.gray, on and colors.black or colors.white, function() page = id end)
    end
    button(c, X2 - 6, 4, "CLOSE", colors.white, colors.black, function() overlay = false end)
    c:line(o1 + 2, 15, o2 - 2, 15, frame)

    if page == "book" then
        local book = entries()
        local listW = math.max(16, math.floor((X2 - X1) * 0.36))
        local rows = bottom - top - 1
        bookSel = math.max(1, math.min(bookSel, #book))
        bookScroll = math.max(0, math.min(bookScroll, #book - rows))
        if bookSel <= bookScroll then bookScroll = bookSel - 1 end
        for n = 1, rows do
            local idx = n + bookScroll
            local entry = book[idx]
            if entry then
                local y = top + n - 1
                local label = pad(string.format("%2d ", idx) .. string.upper(entry.name), listW)
                local bg = entry.network and colors.cyan or colors.lightBlue
                if idx == bookSel then bg = colors.white end
                c:text(X1, y, label, colors.black, bg)
                addButton(X1, y, X1 + listW - 1, y, function() bookSel = idx end)
            end
        end
        local entry = book[bookSel]
        local dx = X1 + listW + 3
        if entry then
            local gi = gateInfo(entry.symbols)
            c:text(dx, top, string.upper(entry.name), colors.white)
            local kind = entry.book and "ADDRESS BOOK" or "GATE NETWORK"
            if entry.dim then kind = kind .. "  -  " .. dimName(entry.dim) end
            c:text(dx, top + 1, kind, entry.book and colors.lightBlue or colors.cyan)
            if entry.x then
                local where = "X " .. entry.x .. (entry.y and ("  Y " .. entry.y) or "") .. "  Z " .. entry.z
                if home and home.x and home.dim == entry.dim then
                    where = where .. "  " .. math.floor(math.sqrt((entry.x - home.x) ^ 2 + (entry.z - home.z) ^ 2)) .. " BLOCKS"
                end
                c:text(dx, top + 2, where, colors.lightGray)
            end
            local h = data.history[entry.name]
            if h then
                c:text(dx, top + 3, "DIALED " .. h.count .. (h.count == 1 and " TIME" or " TIMES") .. ", LAST AT " .. h.last, colors.gray)
            end
            local chevrons = (gi.needed or math.min(6, #entry.symbols)) + 1
            c:text(dx, top + 4, "GATE ADDRESS  " .. chevrons .. " CHEVRONS", colors.white)
            local after = drawAddress(c, dx, X2, top + 5, entry.symbols, 2, gi.needed or math.min(6, #entry.symbols))
            local py = after
            if gi.missing then
                c:text(dx, py, "NO STARGATE ANSWERS AT THIS ADDRESS", colors.red)
            elseif gi.power then
                local open, hold = tonumber(gi.power.open) or 0, tonumber(gi.power.keepAlive) or 0
                c:text(dx, py, "POWER TO DIAL  " .. fe(open) .. " FE", colors.lightBlue)
                c:text(dx, py + 1, "TO HOLD OPEN   " .. fe(hold) .. " FE/T", colors.lightBlue)
                if gi.power.canOpen then
                    c:text(dx, py + 2, "READY TO DIAL", colors.lime)
                else
                    c:text(dx, py + 2, "NOT ENOUGH POWER", blink and colors.red or colors.orange)
                end
            end
            local bx = X1
            bx = button(c, bx, bottom, "DIAL", colors.lime, colors.black, function() overlay = false actions.dial(bookSel) end)
            if entry.book then
                bx = button(c, bx, bottom, "DELETE", colors.red, colors.white, function()
                    table.remove(data.book, entry.book)
                    save()
                    logEvent("BOOK-", "REMOVED " .. entry.name .. " FROM THE ADDRESS BOOK")
                end)
            else
                bx = button(c, bx, bottom, "SAVE TO BOOK", colors.lightBlue, colors.black, function()
                    table.insert(data.book, { name = entry.name, symbols = entry.symbols })
                    save()
                    logEvent("BOOK+", "SAVED " .. entry.name .. " TO THE ADDRESS BOOK")
                end)
            end
            bx = button(c, bx, bottom, "^", colors.gray, colors.white, function() bookSel = bookSel - 1 end)
            button(c, bx, bottom, "v", colors.gray, colors.white, function() bookSel = bookSel + 1 end)
        else
            c:text(dx, top, "NO ADDRESSES YET", colors.lightGray)
        end
        c:text(X2 - 22, bottom, pad(#book .. " DESTINATIONS", 22), colors.gray)

    elseif page == "manual" then
        local cols = 4
        local colW = math.floor((X2 - X1 + 1) / cols)
        local used = {}
        for _, s in ipairs(manual) do used[s] = true end
        local rows = math.ceil(#GLYPHS / cols)
        for i, name in ipairs(GLYPHS) do
            local col = math.floor((i - 1) / rows)
            local y = top + (i - 1) % rows
            local x = X1 + col * colW
            local glyph = name
            if used[name] then
                c:text(x, y, pad(" " .. string.upper(name), colW - 1), colors.gray, colors.black)
            else
                c:text(x, y, pad(" " .. string.upper(name), colW - 1), colors.black, colors.lightBlue)
                addButton(x, y, x + colW - 2, y, function()
                    if #manual < 8 then table.insert(manual, glyph) end
                end)
            end
        end
        local ay = top + rows + 1
        c:text(X1, ay, "ADDRESS  " .. #manual .. " OF 6-8 SYMBOLS, THEN THE POINT OF ORIGIN", colors.white)
        for k = 1, 8 do
            local col = (k - 1) % 4
            local y = ay + 2 + math.floor((k - 1) / 4) * 2
            local a = X1 + 1 + col * colW
            local b = a + colW - 3
            local s = manual[k]
            c:text(a, y, pad(k .. " " .. (s and string.upper(s) or "----"), b - a + 1), s and colors.white or colors.gray)
            box(c, a, b, y, colors.cyan)
        end
        local my = ay + 6
        if #manual >= 6 then
            local found
            local key = firstSix(manual)
            for _, e in ipairs(entries()) do
                if firstSix(e.symbols) == key then found = e break end
            end
            if found then
                c:text(X1, my, "MATCHES " .. string.upper(found.name), colors.lime)
            else
                c:text(X1, my, "NO KNOWN GATE AT THIS ADDRESS", colors.orange)
            end
        end
        local bx = X1
        if #manual >= 6 then
            bx = button(c, bx, bottom, "DIAL", colors.lime, colors.black, function()
                overlay = false
                actions.dialAddress("Manual address", manual)
            end)
            bx = button(c, bx, bottom, "SAVE", colors.lightBlue, colors.black, function() actions.saveManual() end)
        end
        bx = button(c, bx, bottom, "UNDO", colors.yellow, colors.black, function() table.remove(manual) end)
        button(c, bx, bottom, "CLEAR", colors.orange, colors.black, function() manual = {} end)

    elseif page == "idc" then
        local codes = {}
        for code, v in pairs(data.idc) do table.insert(codes, { code = code, name = v.name, allow = v.allow }) end
        table.sort(codes, function(a, b) return a.code < b.code end)
        c:text(X1, top, pad("CODE", 12) .. pad("HOLDER", 26) .. "ACCESS", colors.white)
        local rows = bottom - top - 5
        idcScroll = math.max(0, math.min(idcScroll, #codes - rows))
        for n = 1, rows do
            local item = codes[n + idcScroll]
            if item then
                local y = top + n
                local code = item.code
                c:text(X1, y, pad(code, 12) .. pad(string.upper(item.name), 26), colors.lightBlue)
                local ax = button(c, X1 + 38, y, item.allow and "ALLOWED" or "DENIED ", item.allow and colors.lime or colors.red,
                        item.allow and colors.black or colors.white, function()
                            data.idc[code].allow = not data.idc[code].allow
                            save()
                        end)
                button(c, ax, y, "X", colors.gray, colors.white, function()
                    data.idc[code] = nil
                    save()
                    logEvent("IDC -1", "IDC " .. code .. " REMOVED")
                end)
            end
        end
        if #codes == 0 then c:text(X1, top + 1, "NO CODES YET: ADD ONE, OR ONE A TRAVELLER SENDS", colors.gray) end
        local ly = bottom - 3
        if state.lastCode then
            local known = data.idc[state.lastCode]
            c:text(X1, ly, "LAST CODE RECEIVED  " .. state.lastCode .. (known and ("  " .. string.upper(known.name)) or "  UNKNOWN"),
                    known and colors.lime or colors.orange)
            if not known then
                local code = state.lastCode
                button(c, X2 - 10, ly, "ADD IT", colors.lime, colors.black, function()
                    data.idc[code] = { name = "Traveller", allow = true }
                    save()
                    logEvent("IDC +1", "IDC " .. code .. " ADDED")
                end)
            end
        end
        c:text(X1, ly + 1, "OUR GDO CODE  " .. (data.gdo or "NOT SET") .. "  (SENT WHEN WE DIAL OUT)", colors.lightBlue)
        local bx = X1
        bx = button(c, bx, bottom, "ADD CODE", colors.lime, colors.black, function() actions.addCode() end)
        bx = button(c, bx, bottom, "SET GDO", colors.lightBlue, colors.black, function() actions.setGdo() end)
        if state.open and not state.incoming and data.gdo then
            bx = button(c, bx, bottom, "SEND GDO", colors.yellow, colors.black, function() actions.sendGdo() end)
        end
        if #codes > rows then
            bx = button(c, bx, bottom, "^", colors.gray, colors.white, function() idcScroll = idcScroll - rows end)
            bx = button(c, bx, bottom, "v", colors.gray, colors.white, function() idcScroll = idcScroll + rows end)
        end
        button(c, bx, bottom, data.autoIris and "AUTO IRIS ON" or "AUTO IRIS OFF", colors.lightGray, colors.black,
                function() data.autoIris = not data.autoIris save() end)

    elseif page == "log" then
        local rows = bottom - top - 1
        logScroll = math.max(0, math.min(logScroll, #log - rows))
        c:text(X1, top, pad("DAY", 6) .. pad("TIME", 7) .. "EVENT", colors.white)
        local last = #log - logScroll
        local first = math.max(1, last - rows + 1)
        for i = first, last do
            local e = log[i]
            local y = top + 1 + i - first
            c:text(X1, y, pad(e.day and tostring(e.day) or "", 6) .. pad(e.t, 7) .. string.sub(e.long, 1, X2 - X1 - 12), e.c)
        end
        if #log == 0 then c:text(X1, top + 1, "NOTHING LOGGED YET", colors.gray) end
        local bx = X1
        bx = button(c, bx, bottom, "^ OLDER", colors.gray, colors.white, function() logScroll = logScroll + rows end)
        bx = button(c, bx, bottom, "v NEWER", colors.gray, colors.white, function() logScroll = logScroll - rows end)
        bx = button(c, bx, bottom, "NEWEST", colors.lightGray, colors.black, function() logScroll = 0 end)
        button(c, bx, bottom, "CLEAR LOG", colors.red, colors.white, function()
            log = {}
            logScroll = 0
            logEvent("LOG", "EVENT LOG CLEARED")
        end)
        c:text(X2 - 22, bottom, pad(#log .. " EVENTS", 22), colors.gray)

    elseif page == "gate" then
        local hi = homeInfo()
        c:text(X1, top, "STARGATE COMMAND", colors.white)
        if home and home.x then
            c:text(X1 + 18, top, dimName(home.dim) .. "  X " .. home.x .. "  Y " .. (home.y or "?") .. "  Z " .. home.z, colors.lightGray)
        end
        local after = top + 2
        if hi.address then
            after = drawAddress(c, X1 - 1, X2, top + 2, hi.address, 3, math.min(6, #hi.address))
        else
            c:text(X1, after, "ADDRESS UNKNOWN", colors.gray)
            after = after + 2
        end
        local sy = after
        local half = math.floor((X2 - X1) / 2)
        local function stat(n, label, value, colour)
            c:text(X1, sy + n, pad(label, 15) .. string.sub(tostring(value), 1, half - 16), colour or colors.lightBlue)
        end
        stat(0, "GATE TYPE", string.upper(tostring(hi.type or "?")))
        stat(1, "STATUS", state.status ~= "" and state.status or "?", state.open and colors.lime or colors.lightBlue)
        stat(2, "POWER", fe(state.energy) .. " / " .. fe(state.maxEnergy) .. " FE")
        local barY = (sy + 3 - 1) * 3 + 2
        local bx1, bx2 = (X1 - 1) * 2 + 1, (X1 + half - 3) * 2
        c:rect(bx1, barY - 1, bx2, barY + 1, frame)
        local frac = (state.maxEnergy and state.maxEnergy > 0) and math.min(1, state.energy / state.maxEnergy) or 0
        if frac > 0 then c:line(bx1 + 1, barY, bx1 + 1 + (bx2 - bx1 - 2) * frac, barY, frac < 0.2 and colors.red or colors.lime) end
        stat(4, "CAPACITORS", hi.capacitors and tostring(hi.capacitors) or "-")
        stat(5, "IRIS", string.upper(tostring(hi.irisType or "NONE")) .. "  " .. (state.iris or ""), irisClosed() and colors.orange or colors.lightBlue)
        if hi.irisMax and hi.irisMax > 0 then
            stat(6, "IRIS STRENGTH", math.floor((hi.irisMax - (hi.irisDamage or 0)) / hi.irisMax * 100 + 0.5) .. "%")
        else
            stat(6, "IRIS STRENGTH", "-")
        end
        local openFor = state.openedAt and (os.clock() - state.openedAt) or nil
        stat(7, "WORMHOLE", openFor and ("OPEN " .. clockText(openFor)) or "CLOSED", openFor and colors.lime or colors.lightBlue)
        stat(8, "AUTO IRIS", data.autoIris and "ON" or "OFF")
        stat(9, "BASE ALERT", data.alarm and "ON" or "OFF")
        -- the most dialed addresses, on the right
        local lx = X1 + half + 1
        c:text(lx, sy, "MOST DIALED", colors.white)
        local most = {}
        for name, h in pairs(data.history) do table.insert(most, { name = name, count = h.count, last = h.last }) end
        table.sort(most, function(a, b) return a.count > b.count end)
        for i = 1, math.min(#most, bottom - sy - 3) do
            local m = most[i]
            c:text(lx, sy + i, pad(string.upper(m.name), X2 - lx - 9) .. string.format("%4dx", m.count), colors.lightBlue)
        end
        if #most == 0 then c:text(lx, sy + 1, "NOTHING DIALED YET", colors.gray) end
        local bx = X1
        bx = button(c, bx, bottom, irisClosed() and "OPEN IRIS" or "CLOSE IRIS", colors.orange, colors.black, function() actions.iris() end)
        bx = button(c, bx, bottom, "SHUTDOWN", colors.red, colors.white, function() actions.close() end)
        bx = button(c, bx, bottom, "ABORT DIAL", colors.yellow, colors.black, function() actions.abort() end)
        bx = button(c, bx, bottom, data.alarm and "ALERT ON" or "ALERT OFF", colors.pink, colors.black,
                function() data.alarm = not data.alarm save() end)
        button(c, bx, bottom, data.autoIris and "AUTO IRIS ON" or "AUTO IRIS OFF", colors.lightGray, colors.black,
                function() data.autoIris = not data.autoIris save() end)
    end
end

-- The SGC's dialing screen, after the one in the show: the gate in the middle, the destination boxes on the right,
-- the event log and the chevron lamps on the left, the big status word underneath, the authorisation code and the
-- operator along the bottom. Tap KEYBOARD for the address book, manual dialing, the IDC codes and the gate.
local function drawMonitor()
    if not mon then return end
    buttons = {}
    local W, H = mon.getSize()
    local c = newCanvas(W, H)
    local PW, PH = W * 2, H * 3
    local frame = colors.cyan
    c:rect(2, 2, PW - 1, PH - 1, frame)
    c:rect(3, 3, PW - 2, PH - 2, frame)

    -- panel edges (in characters, then pixels)
    local left = math.floor(W * 0.22)
    local right = W - math.floor(W * 0.15)
    local cx = math.floor(left * 2 + (right * 2 - left * 2) / 2)
    local r = math.floor(math.min((right - left) * 2 * 0.33, PH * 0.235))
    local cy = 6 + r + 4

    -- top left: an emblem (a little gate) and the telemetry streams beside and under it
    local logBottom = math.floor(H * 0.45)
    local ex, ey = 10, 8
    c:ring(ex, ey, 5, colors.cyan)
    c:ring(ex, ey, 3, colors.lightBlue)
    c:disc(ex, ey, 1, function() return state.open and colors.lightBlue or colors.orange end)
    local streams = logBottom - 2
    if #hexes == 0 or tick % 2 == 0 then
        table.remove(hexes, 1)
        while #hexes < streams do table.insert(hexes, hexLine(math.max(1, left - 10))) end
    end
    for i, line in ipairs(hexes) do
        local x = i <= 3 and 9 or 4                      -- beside the emblem, then the full width under it
        c:text(x, i + 1, string.sub(i <= 3 and line or (line .. hexLine(5)), 1, left - x - 1), (i % 3 == 2) and colors.yellow or colors.gray)
    end
    c:rect(5, 4, left * 2 - 2, logBottom * 3, frame)

    -- bottom left: the chevron lamps, with OK as each locks, and the power under them
    local lampTop = logBottom + 2
    local lamps = math.max(7, state.total)
    c:rect(5, (lampTop - 1) * 3 - 1, left * 2 - 2, (lampTop + lamps - 1) * 3 + 2, frame)
    for i = 1, lamps do
        local row = lampTop + i - 1
        local y = (row - 1) * 3 + 2
        local done = i <= state.locked
        c:fill(8, y, 13, y + 1, done and colors.red or colors.brown)
        c:text(9, row, tostring(i), colors.white)
        c:rect(18, y - 1, 26, y + 2, frame)
        if done then c:text(10, row, " OK", colors.lime) end
    end
    local pr = lampTop + lamps + 1
    if pr + 2 < H - 2 then
        local frac = (state.maxEnergy and state.maxEnergy > 0) and math.min(1, state.energy / state.maxEnergy) or 0
        c:text(3, pr, pad("POWER " .. fe(state.energy), left - 3), colors.white)
        local py = pr * 3 + 2
        c:rect(5, py - 1, left * 2 - 2, py + 1, frame)
        if frac > 0 then c:line(6, py, 6 + (left * 2 - 9) * frac, py, frac < 0.2 and colors.red or colors.lime) end
    end

    -- the gate and the lines from its chevrons to the destination boxes
    drawGate(c, cx, cy, r, blink, tick)
    local boxes = math.max(7, #state.address, state.total)     -- 7, 8 or 9 chevrons: a box each
    local bx1, bx2 = right * 2 + 1, PW - 6
    local top = 4 * 3
    local bh = math.max(4, math.floor((PH - 18 - top) / boxes))
    -- the destination header (OFFWRLD flashing red when something's coming in)
    if state.incoming and blink then
        c:text(right, 3, "  OFFWRLD  ", colors.white, colors.red)
    else
        c:text(right, 3, "DESTINATION", colors.white)
    end
    for i = 1, boxes do
        local y1 = top + (i - 1) * bh
        local y2 = y1 + bh - 2
        local locked = i <= state.locked
        local recognised = state.idc and state.idc.ok and blink
        if recognised then c:fill(bx1 + 1, y1 + 1, bx2 - 1, y2 - 1, colors.lime)
        elseif locked then c:fill(bx1 + 1, y1 + 1, bx2 - 1, y2 - 1, colors.red) end
        c:rect(bx1, y1, bx2, y2, locked and colors.red or frame)
        local my = math.floor((y1 + y2) / 2)
        local ay = math.floor(cy - r + (i - 0.5) * (2 * r) / boxes)
        local ex2 = cx + math.sqrt(math.max(0, r * r - (ay - cy) ^ 2)) + 4
        local kx = bx1 - 3 - (i % 4) * 2
        local lc = locked and colors.red or colors.gray
        c:line(ex2, ay, kx, ay, lc)
        c:line(kx, ay, kx, my, lc)
        c:line(kx, my, bx1 - 1, my, lc)
        local sym = state.address[i]
        if sym and locked then
            local name = string.upper(sym)
            if name == "POINT OF ORIGIN" then name = "ORIGIN" end
            c:text(math.floor(bx1 / 2) + 2, math.floor(my / 3) + 1, string.sub(name, 1, W - math.floor(bx1 / 2) - 3), colors.white, colors.red)
        end
    end
    -- the glyph being encoded: it appears in the middle of the gate and moves out to its box
    if state.anim then
        local a = state.anim
        local t = math.min(1, (os.clock() - a.start) / 1.2)
        local y1 = top + (a.box - 1) * bh
        local tyc = math.floor(((y1 + y1 + bh - 2) / 2) / 3) + 1
        local fromX, fromY = math.floor(cx / 2) - math.floor(#a.name / 2), math.floor(cy / 3) + 1
        local toX = math.floor(bx1 / 2) + 2
        local x = math.floor(fromX + (toX - fromX) * math.max(0, t - 0.3) / 0.7)
        local y = math.floor(fromY + (tyc - fromY) * math.max(0, t - 0.3) / 0.7)
        c:text(x, y, a.name, colors.black, colors.white)
        if t >= 1 then state.anim = nil end
    end

    -- under the gate: the LST CODE bars, then the big status word
    local sy1 = cy + r + 8
    local sx1, sx2 = cx - r - 10, cx + r + 10
    local lst = math.floor(sy1 / 3) - 1
    c:text(math.floor(sx1 / 2), lst, "LST CODE #1", colors.white)
    c:text(math.floor(sx2 / 2) - 10, lst, "LST CODE #2", colors.white)
    -- over the gate: where we're dialing, or how long the wormhole's been open
    local mid
    if state.dialing then mid = "DIALING " .. string.upper(state.dialing)
    elseif state.open and state.openedAt then mid = "WORMHOLE OPEN " .. clockText(os.clock() - state.openedAt) end
    if mid then
        mid = " " .. string.sub(mid, 1, right - left - 4) .. " "          -- set into the screen's top border, like a title
        c:text(math.floor(cx / 2) - math.floor(#mid / 2) + 1, 1, mid, state.dialing and colors.orange or colors.lime)
    end
    local sy2 = math.min(PH - 9, sy1 + 16)
    c:rect(sx1, sy1, sx2, sy2, frame)
    for x = sx1 + 2, sx2 - 2, 3 do c:set(x, sy1 + 1, colors.cyan) end
    local word, colour
    if not gate then word, colour = "NO GATE", colors.red
    elseif state.shutdownUntil and os.clock() < state.shutdownUntil then word, colour = "SHUTDOWN", blink and colors.red or colors.orange
    elseif state.incoming then word, colour = "INCOMING", blink and colors.red or colors.black
    elseif state.dialing then word, colour = "ENGAGED", colors.red
    elseif state.open then word, colour = "LOCKED", colors.white
    elseif irisClosed() then word, colour = "IRIS CLOSED", colors.red
    else word, colour = "IDLE", colors.lightGray end
    local scale = 2
    while scale > 1 and (#word * 4 - 1) * scale > (sx2 - sx1 - 4) do scale = scale - 1 end
    c:bigText(math.floor((sx1 + sx2) / 2), math.floor((sy1 + sy2) / 2 - 2.5 * scale) + 1, word, scale, colour)

    -- under the status word: the iris's state and the automatic iris (the IRIS button is by KEYBOARD)
    local ir = math.floor(sy2 / 3) + 2
    if gate and ir <= H - 4 then
        local x0, x1 = math.floor(sx1 / 2) + 1, math.floor(sx2 / 2)
        local w = x1 - x0 + 1
        local closed = irisClosed()
        local irisText = state.iris ~= "" and state.iris or "NONE"
        local moving = string.find(irisText, "ING") ~= nil
        c:text(x0, ir, "IRIS " .. irisText, closed and colors.orange or (moving and colors.yellow or colors.lime))
        local auto = data.autoIris and " AUTO IRIS ON " or " AUTO IRIS OFF "
        c:text(x1 - #auto + 1, ir, auto, colors.black, data.autoIris and colors.lightBlue or colors.gray)
        addButton(x1 - #auto + 1, ir, x1, ir, function()
            data.autoIris = not data.autoIris
            save()
            logEvent("AUTO", "AUTOMATIC IRIS " .. (data.autoIris and "ON" or "OFF"))
        end)
    end

    -- along the bottom: the authorisation code, the keyboard, the operator
    local by = H - 2
    c:text(3, by, "AUTH CODE", colors.white)
    c:text(3, by + 1, state.auth or "10183523652-4354393", colors.lightBlue)
    local kx = math.floor(W * 0.47)
    c:text(kx, by, "[########]", colors.lightGray)
    c:text(kx, by + 1, " KEYBOARD ", colors.black, colors.lightGray)
    addButton(kx, by, kx + 9, by + 1, function() overlay = true end)
    -- the iris, left of KEYBOARD: red to close it, green to open it, flashing while a wormhole comes in to an open iris
    if gate then
        local closed = irisClosed()
        local bg = closed and colors.lime or colors.red
        if state.incoming and not closed and blink then bg = colors.orange end
        c:text(kx - 11, by, "[########]", colors.lightGray)
        c:text(kx - 11, by + 1, closed and "OPEN IRIS " or "CLOSE IRIS", closed and colors.black or colors.white, bg)
        addButton(kx - 11, by, kx - 2, by + 1, function() actions.iris() end)
    end
    if data.last and kx - 22 > 22 then
        c:text(kx - 22, by, "[########]", colors.lightGray)
        c:text(kx - 22, by + 1, "  REDIAL  ", colors.black, colors.orange)
        local last = data.last
        addButton(kx - 22, by, kx - 13, by + 1, function() actions.dialAddress(last.name, last.symbols) end)
    end
    c:text(kx + 11, by, "[####]", colors.lightGray)
    c:text(kx + 11, by + 1, " LOG  ", colors.black, colors.cyan)
    addButton(kx + 11, by, kx + 16, by + 1, function()
        overlay = true
        page = "log"
        logScroll = 0
    end)
    local ux = kx + 19
    c:text(ux, by - 1, "USER: SGC DIAL OPERATOR", colors.lightBlue)
    c:text(ux, by, "STATUS: " .. (gate and "ACTIVE" or "OFFLINE") .. "   IRIS: " .. (data.autoIris and "AUTO" or "MANUAL"), colors.lightBlue)
    c:text(ux, by + 1, "SYS: " .. (state.incoming and "ALERT" or "NOMINAL") .. "   " .. string.upper(string.sub(state.message or "", 1, W - ux - 19)),
            state.incoming and colors.red or colors.lightBlue)

    -- the IDC window over the gate, while a code is being checked
    if state.idc and os.clock() - state.idc.t < 8 then
        local w1, w2 = cx - r + 2, cx + r - 2
        local h1, h2 = cy - 12, cy + 12
        c:clear(w1, h1, w2, h2, colors.black)
        c:rect(w1, h1, w2, h2, frame)
        local tx1 = math.floor(w1 / 2) + 2
        c:text(tx1, math.floor(h1 / 3) + 2, "CONTROL  HEX  900 IDC", colors.lightBlue)
        local wave = state.idc.ok and colors.lime or colors.red
        local mid2 = cy - 2
        local last
        for x = w1 + 3, w2 - 3 do
            local y = mid2 + math.sin((x + tick * 3) * 0.5) * 3 * (state.idc.ok and 1 or ((x % 5 == 0) and 1.3 or 0.4))
            if last then c:line(x - 1, last, x, y, wave) end
            last = y
        end
        local ty = math.floor((cy + 4) / 3) + 1
        if state.idc.ok then
            c:text(tx1, ty, "SIGNAL DECRYPTED CODE " .. state.idc.code, colors.lime)
            c:text(tx1, ty + 1, "RECOGNISED: " .. string.upper(state.idc.name), colors.lime)
        else
            c:text(tx1, ty, "CODE " .. state.idc.code .. "  NO MATCH", colors.red)
            if blink then c:text(tx1, ty + 1, "UNAUTHORISED TRAVELLER", colors.white, colors.red) end
        end
    end

    if overlay then drawOverlay(c, W, H, PW, PH, frame) end
    if state.notice then
        local n = state.notice
        local nx = math.floor((W - #n) / 2)
        c:clear(nx * 2 - 4, math.floor(H / 2) * 3 - 5, (nx + #n) * 2 + 4, math.floor(H / 2) * 3 + 4, colors.black)
        c:rect(nx * 2 - 4, math.floor(H / 2) * 3 - 5, (nx + #n) * 2 + 4, math.floor(H / 2) * 3 + 4, colors.yellow)
        c:text(nx + 1, math.floor(H / 2) + 1, n, colors.yellow)
    end
    c:draw(mon)
end

local function drawTerminal()
    local w, h = term.getSize()
    term.setBackgroundColor(colors.black)
    term.clear()
    fillRect(term, 1, 1, w, 1, colors.blue)
    text(term, 2, 1, "STARGATE COMMAND - DIALING COMPUTER", colors.white, colors.blue)
    text(term, 2, 3, "Gate:  " .. state.status, state.incoming and colors.red or colors.lightBlue, colors.black)
    text(term, 2, 4, "Iris:  " .. state.iris .. (data.autoIris and "  (automatic)" or "  (manual)"), irisClosed() and colors.orange or colors.lime, colors.black)
    text(term, 2, 5, "Power: " .. tostring(state.energy) .. " FE", colors.white, colors.black)
    text(term, 2, 6, state.message or "", colors.yellow, colors.black)
    text(term, 2, 7, state.detail or "", colors.lightGray, colors.black)
    if not gate then
        text(term, 2, 9, "No Stargate found. Devices this computer can see:", colors.red, colors.black)
        local y = 10
        for _, name in ipairs(peripheral.getNames()) do
            if y > h - 4 then break end
            text(term, 4, y, name .. " (" .. tostring(peripheral.getType(name)) .. ")", colors.lightGray, colors.black)
            y = y + 1
        end
        text(term, 2, h - 2, "Connect it next to the gate's base, or by wired", colors.white, colors.black)
        text(term, 2, h - 1, "modems (right-click the one by the gate).", colors.white, colors.black)
        return
    end
    local count = 0
    for _ in pairs(data.idc) do count = count + 1 end
    text(term, 2, 9, "Addresses: " .. #data.book .. "   Gates in the world: " .. #network .. "   IDC codes: " .. count, colors.lightGray, colors.black)
    text(term, 2, 10, "[1-9] dial   [A] add address   [X] remove", colors.white, colors.black)
    text(term, 2, 11, "[C] add IDC code   [R] remove   [T] auto iris", colors.white, colors.black)
    text(term, 2, 12, "[I] iris   [G] close gate   [B] abort   [Q] quit", colors.white, colors.black)
    text(term, 2, 13, "[P] our GDO code: " .. (data.gdo or "not set"), colors.white, colors.black)
    local logLines = math.min(#log, 4)
    local y = 15
    for i, entry in ipairs(entries()) do
        if y > h - logLines - 1 then break end
        text(term, 2, y, i .. ". " .. entry.name .. "  (" .. table.concat(entry.symbols, ", ") .. ")", colors.cyan, colors.black)
        y = y + 1
    end
    for i = 1, logLines do
        local e = log[#log - logLines + i]
        text(term, 2, h - logLines + i, string.sub(e.t .. " " .. e.long, 1, w - 2), e.c, colors.black)
    end
end

local function draw()
    drawMonitor()
    drawTerminal()
end

-- ------------------------------------------------------------------ actions

local pending = nil                  -- the address the dialer is to dial next

function actions.dialAddress(name, symbols)
    if state.dialing then
        state.detail = "ALREADY DIALING " .. string.upper(state.dialing)
        return
    end
    local copy = {}
    for k, s in ipairs(symbols) do copy[k] = s end
    pending = { name = name, symbols = copy }
    os.queueEvent("sgc_dial")
end

function actions.dial(i)
    local entry = entries()[i]
    if entry then actions.dialAddress(entry.name, entry.symbols) end
end

function actions.iris()
    refresh()
    local closing = not irisClosed()
    local ok, _, err = call("toggleIris")
    state.detail = ok and "IRIS TOGGLED" or ("IRIS: " .. string.upper(err))
    if ok then logEvent(closing and "IRIS C" or "IRIS O", closing and "IRIS CLOSED" or "IRIS OPENED", colors.orange) end
end

function actions.close()
    local ok, _, err = call("disengageGate")
    state.detail = ok and "CLOSING THE WORMHOLE" or ("CLOSE: " .. string.upper(err))
    if ok then logEvent("SHUTDN", "GATE SHUTDOWN ORDERED", colors.red) end
end

function actions.sendGdo()
    if not data.gdo then return end
    local ok, _, err = call("sendIrisCode", data.gdo)
    state.detail = ok and "GDO CODE SENT" or ("GDO: " .. string.upper(err))
    if ok then logEvent("GDO TX", "GDO CODE " .. data.gdo .. " SENT") end
end

function actions.abort()
    os.queueEvent("sgc_abort")
    local ok, _, err = call("abortDialing")
    state.dialing = nil
    state.locked = 0
    state.message = "DIALING ABORTED"
    state.detail = ok and "" or string.upper(err)
    logEvent("ABORT", "DIALING ABORTED", colors.yellow)
end

local function prompt(label)
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow)
    print(label)
    term.setTextColor(colors.white)
    return read()
end

local function addAddress()
    local name = prompt("Name for the address (empty to cancel):")
    if not name or name == "" then return end
    local entry = prompt("Its symbols, separated by commas (6, 7 or 8, without the point of origin), e.g.\nLynx, Pisces, Libra, Monoceros, Sextans, Perseus")
    local symbols = {}
    for part in string.gmatch(entry or "", "[^,]+") do
        local symbol = part:gsub("^%s+", ""):gsub("%s+$", "")
        if symbol ~= "" then table.insert(symbols, symbol) end
    end
    if #symbols < 6 or #symbols > 8 then
        state.detail = "AN ADDRESS NEEDS 6 TO 8 SYMBOLS"
        return
    end
    table.insert(data.book, { name = name, symbols = symbols })
    save()
    state.detail = "ADDED " .. string.upper(name)
end

local function removeAddress()
    local n = tonumber(prompt("Number of the address to remove:"))
    if n and data.book[n] then
        state.detail = "REMOVED " .. string.upper(data.book[n].name)
        table.remove(data.book, n)
        save()
    end
end

local function addCode()
    local code = prompt("IDC code (empty to cancel):")
    if not code or code == "" then return end
    local who = prompt("Who it belongs to:")
    data.idc[code] = { name = (who ~= "" and who) or "Unknown", allow = true }
    save()
    state.detail = "IDC " .. code .. " ADDED"
end

local function removeCode()
    local code = prompt("IDC code to remove:")
    if code and data.idc[code] then
        data.idc[code] = nil
        save()
        state.detail = "IDC " .. code .. " REMOVED"
    end
end

-- Asks on the computer's own screen, with a note on the wall screen to go and type there.
local function asking(f)
    state.notice = "TYPE ON THE DIALING COMPUTER'S KEYBOARD"
    drawMonitor()
    f()
    state.notice = nil
end

function actions.addCode() asking(addCode) end

function actions.setGdo()
    asking(function()
        local code = prompt("Our GDO code, sent to the far gate's iris when we dial out (empty to clear):")
        data.gdo = (code and code ~= "") and code or nil
        save()
    end)
end

function actions.saveManual()
    local symbols = {}
    for k, s in ipairs(manual) do symbols[k] = s end
    asking(function()
        local name = prompt("Name for this address (empty to cancel):")
        if name and name ~= "" then
            table.insert(data.book, { name = name, symbols = symbols })
            save()
            logEvent("BOOK+", "SAVED " .. name .. " TO THE ADDRESS BOOK")
        end
    end)
end

-- ------------------------------------------------------------------ dialing

-- Waits until the gate has locked `count` symbols (its chevron event, or the dialed address growing), up to `seconds`.
local function waitLocked(count, seconds)
    local deadline = os.clock() + seconds
    local timer = os.startTimer(0.5)
    while os.clock() < deadline do
        local e = table.pack(os.pullEvent())
        if e[1] == "sgc_abort" then return false end
        if e[1] == "stargate_chevron_engaged" then
            local n = dialedCount()
            if n == nil or n >= count then return true end
        elseif e[1] == "timer" and e[2] == timer then
            local n = dialedCount()
            if n and n >= count then return true end
            timer = os.startTimer(0.5)
        end
    end
    return false
end

-- Engages one symbol. The gate is "busy" for a moment after each chevron locks (the ring still settling), so a busy
-- answer is tried again for a while rather than taken as a failure.
local function engage(symbol)
    local deadline = os.clock() + 20
    while true do
        local ok, code, err = call("engageSymbol", symbol)
        if ok then return ok, code, err end
        local busy = string.find(string.lower(tostring(code) .. " " .. tostring(err)), "busy") ~= nil
        if not busy or os.clock() > deadline then return ok, code, err end
        local timer = os.startTimer(0.5)
        repeat
            local e, id = os.pullEvent()
            if e == "sgc_abort" then return false, "aborted", "aborted" end
        until e == "timer" and id == timer
    end
end

-- Waits for the point of origin's chevron: its event, the dialed address reaching `count`, or `seconds` passing.
local function waitOrigin(count, seconds)
    local timer = os.startTimer(seconds)
    local poll = os.startTimer(0.5)
    while true do
        local e = table.pack(os.pullEvent())
        if e[1] == "sgc_abort" then return false end
        if e[1] == "stargate_chevron_engaged" then return true end
        if e[1] == "timer" and e[2] == timer then return false end
        if e[1] == "timer" and e[2] == poll then
            local n = dialedCount()
            if n and n >= count then return true end
            poll = os.startTimer(0.5)
        end
    end
end

-- Opens the gate on the dialed address (engageGate), trying again for a while if the gate's still busy.
local function openGate()
    local deadline = os.clock() + 15
    while true do
        local ok, code, err = call("engageGate")
        if ok then return ok, code, err end
        local text = string.lower(tostring(code) .. " " .. tostring(err))
        if not string.find(text, "busy") or os.clock() > deadline then return ok, code, err end
        local timer = os.startTimer(0.5)
        repeat
            local e, id = os.pullEvent()
            if e == "sgc_abort" then return false, "aborted", "aborted" end
        until e == "timer" and id == timer
    end
end

local function dialer()
    while true do
        os.pullEvent("sgc_dial")
        local entry = pending
        pending = nil
        if entry and gate then
            -- how many of its symbols this gate needs (a gate in another galaxy needs 7 or 8)
            local symbols = entry.symbols
            if #symbols > 6 then
                -- counted with the point of origin; a gate JSG doesn't know of gets every symbol it was given
                local n = tonumber(keyed("getSymbolsNeeded", symbols)) or (#symbols + 1)
                n = n - 1
                n = math.max(6, math.min(#symbols, n))
                symbols = {}
                for k = 1, n do symbols[k] = entry.symbols[k] end
            end
            entry = { name = entry.name, symbols = symbols }
            state.dialing = entry.name
            state.address = {}
            for k, s in ipairs(entry.symbols) do state.address[k] = s end
            table.insert(state.address, "Point of Origin")
            state.total = #state.address
            state.locked = 0
            state.message = "DIALING " .. string.upper(entry.name)
            state.detail = ""
            logEvent("DIAL", "DIALING " .. entry.name .. " (" .. #entry.symbols .. " SYMBOLS)", colors.orange)
            os.queueEvent("sgc_redraw")
            local failed = false
            for n, symbol in ipairs(entry.symbols) do
                state.anim = { name = string.upper(symbol), box = n, start = os.clock() }
                local ok, _, err = engage(symbol)
                if not ok then
                    state.message = "CHEVRON " .. WORDS[n] .. " FAILED TO ENCODE"
                    state.detail = string.upper(symbol .. ": " .. err)
                    logEvent("FAIL " .. n, "CHEVRON " .. WORDS[n] .. " FAILED: " .. err, colors.red)
                    failed = true
                    break
                end
                if not waitLocked(n, 20) then
                    state.message = "CHEVRON " .. WORDS[n] .. " DID NOT LOCK"
                    logEvent("FAIL " .. n, "CHEVRON " .. WORDS[n] .. " DID NOT LOCK", colors.red)
                    failed = true
                    break
                end
                state.locked = n
                state.message = "CHEVRON " .. WORDS[n] .. " ENCODED"
                logEvent("CHV " .. n, "CHEVRON " .. WORDS[n] .. " ENCODED: " .. symbol)
                os.queueEvent("sgc_redraw")
            end
            if not failed then
                local ok, err = false, "no point of origin"
                state.anim = { name = "ORIGIN", box = #entry.symbols + 1, start = os.clock() }
                for _, origin in ipairs(ORIGIN) do
                    local r, _x
                    r, _x, err = engage(origin)
                    if r then
                        ok = true
                        break
                    end
                end
                if ok then
                    -- the point of origin: the gate may not count it in its dialed address, so its chevron event
                    -- (or a few seconds) is enough; then open the gate, trying again while it's still busy locking
                    waitOrigin(#entry.symbols + 1, 6)
                    state.locked = #entry.symbols + 1
                    state.message = "CHEVRON " .. WORDS[state.locked] .. " LOCKED"
                    logEvent("LOCK " .. state.locked, "CHEVRON " .. WORDS[state.locked] .. " LOCKED", colors.orange)
                    os.queueEvent("sgc_redraw")
                    local opened, _, e2 = openGate()
                    if opened then
                        state.message = "WORMHOLE ESTABLISHED"
                        local h = data.history[entry.name] or { count = 0 }
                        h.count = h.count + 1
                        h.last = (log[#log] and log[#log].t) or ""
                        data.history[entry.name] = h
                        data.last = { name = entry.name, symbols = entry.symbols }
                        save()
                        state.detail = string.upper(entry.name)
                        logEvent("OPEN", "WORMHOLE ESTABLISHED: " .. entry.name, colors.lime)
                        if data.gdo then actions.sendGdo() end
                    else
                        state.message = "UNABLE TO ESTABLISH A LOCK"
                        state.detail = string.upper(tostring(e2))
                        logEvent("NOLOCK", "UNABLE TO ESTABLISH A LOCK: " .. tostring(e2), colors.red)
                    end
                else
                    state.message = "POINT OF ORIGIN DID NOT LOCK"
                    logEvent("ORIG X", "POINT OF ORIGIN DID NOT LOCK", colors.red)
                    state.detail = string.upper(tostring(err))
                end
            end
            state.dialing = nil
            os.queueEvent("sgc_redraw")
        end
    end
end

-- ------------------------------------------------------------------ events

local function lastString(e)
    for i = e.n, 2, -1 do
        if type(e[i]) == "string" and not peripheral.isPresent(e[i]) then return e[i] end
    end
    return nil
end

local function onEvent(e)
    local name = e[1]
    if name == "stargate_wormhole_incoming" then
        state.incoming = true
        state.message = "UNSCHEDULED OFFWORLD ACTIVATION"
        if data.alarm then logEvent("ALERT", "BASE ALERT SOUNDED", colors.red) end
        logEvent("OFFWLD", "UNSCHEDULED OFFWORLD ACTIVATION", colors.red)
        state.address = {}
        state.locked = 0
        if data.autoIris and not irisClosed() then
            if setIris(true) then
                state.autoClosed = true
                logEvent("IRIS C", "IRIS CLOSED AUTOMATICALLY", colors.orange)
            end
        end
    elseif name == "stargate_iris_code_received" then
        local code = lastString(e) or "?"
        state.lastCode = code
        local known = data.idc[code]
        state.idc = { code = code, name = known and known.name or "", ok = known and known.allow or false, t = os.clock() }
        if known and known.allow then
            state.message = "IDC RECEIVED: " .. string.upper(known.name)
            logEvent("IDC OK", "IDC " .. code .. " RECOGNISED: " .. known.name, colors.lime)
            state.detail = "OPENING THE IRIS"
            setIris(false)
            call("sendMessageToIncoming", "Code accepted: " .. known.name .. ". The iris is open.")
        else
            state.message = "UNKNOWN IDC: " .. code
            logEvent("IDC ??", "IDC " .. code .. " NOT RECOGNISED", colors.red)
            state.detail = "THE IRIS STAYS CLOSED"
            call("sendMessageToIncoming", "Code not recognised. The iris stays closed.")
        end
    elseif name == "stargate_wormhole_close_fully" then
        state.incoming = false
        state.address = {}
        state.locked = 0
        state.total = 0
        state.message = "WORMHOLE DISENGAGED"
        logEvent("CLOSED", "WORMHOLE DISENGAGED")
        state.shutdownUntil = os.clock() + 3
        if state.autoClosed then
            setIris(false)
            state.autoClosed = false
        end
    elseif name == "monitor_touch" then
        local x, y = e[3], e[4]
        for _, b in ipairs(buttons) do
            if x >= b[1] and x <= b[3] and y >= b[2] and y <= b[4] then
                b[5]()
                break
            end
        end
    elseif name == "char" then
        local c = string.lower(e[2])
        local n = tonumber(c)
        if n and n >= 1 then actions.dial(n)
        elseif c == "a" then addAddress()
        elseif c == "x" then removeAddress()
        elseif c == "c" then addCode()
        elseif c == "r" then removeCode()
        elseif c == "t" then
            data.autoIris = not data.autoIris
            save()
            state.detail = "AUTOMATIC IRIS " .. (data.autoIris and "ON" or "OFF")
        elseif c == "i" then actions.iris()
        elseif c == "g" then actions.close()
        elseif c == "b" then actions.abort()
        elseif c == "p" then
            local code = prompt("Our GDO code, sent to the far gate's iris when we dial out (empty to clear):")
            data.gdo = (code and code ~= "") and code or nil
            save()
        elseif c == "q" then return "quit"
        end
    elseif name == "peripheral" or name == "peripheral_detach" or name == "monitor_resize" then
        findDevices()
    end
end

-- The base alert: every side of the computer gives a redstone signal, on and off, while a wormhole is coming in (the
-- lamps either side of SGC's dialing computer flash with it).
local alerting = false
local function alert(on)
    on = on and true or false
    if on == alerting or not redstone then return end
    alerting = on
    for _, side in ipairs(redstone.getSides()) do pcall(redstone.setOutput, side, on) end
end

local function ui()
    local timer = os.startTimer(0.2)
    while true do
        refresh()
        draw()
        local e = table.pack(os.pullEvent())
        if e[1] == "timer" and e[2] == timer then
            tick = tick + 1
            blink = math.floor(tick / 2) % 2 == 0
            timer = os.startTimer(0.2)
            alert(state.incoming and data.alarm and blink)
        elseif onEvent(e) == "quit" then
            return
        end
    end
end

loadData()
findDevices()
do
    -- an authorisation code for this computer, the same every time
    local id = os.getComputerID and os.getComputerID() or 0
    local a = (id * 7919 + 1018352365) % 100000000000
    state.auth = string.format("%011d-%07d", a, (id * 104729 + 4354393) % 10000000)
end
parallel.waitForAny(ui, dialer)
alert(false)
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
if mon then
    mon.setBackgroundColor(colors.black)
    mon.clear()
end
print("Stargate Command closed. Type sgc to start it again.")
