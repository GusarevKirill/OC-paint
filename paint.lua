local gpu = require"component".gpu
local event = require"event"
local fs = require"filesystem"
local shell = require"shell"
local unicode = require"unicode"
local uuid = require"uuid"
--
--
local DEFAULT_FG, DEFAULT_BG = 0xFFFFFF, 0x333333
local W, H = 160, 50
local CWD = shell.getWorkingDirectory()
local FORMAT = "kaka888 pic v0.0.1$$"
--
--
local x, y
local canvas = {}
local canvasWidth, canvasHeight = 146, 46
local run, saved = true, false
local palette = {
    0xFFFFFF, 0xCCCCCC, 0x999999, 0x666666,
    0x333333, 0x000000, 0xFF0000, 0x00FF00,
    0x0000FF, 0xFFFF00, 0x00FFFF, 0xFF00FF,
}
local brushes = {"█", "░", "▒"}
local currentColor, currentBrush = 0x000000, brushes[1]
--
--
------ Для разработки и отладки
debug_info = {}

function DBG_PRINT(msg)
    gpu.setForeground(0x00FF33) gpu.setBackground(0x000000) print(msg)
end

function DBG_SAVE(index, data)
    table.insert(debug_info[index], data)
end
------
function canvasToBytes(canvas)
    local bytes = ""
    
    for y = 1, canvasHeight do
        for x = 1, canvasWidth do
            local pixel = canvas[y][x]
            if pixel then
                local byte1, byte2, byte3 = 
                    bit32.band(pixel.color, tonumber("111111110000000000000000", 2)) >> 16,
                    bit32.band(pixel.color, tonumber("000000001111111100000000", 2)) >> 8,
                    bit32.band(pixel.color, tonumber("000000000000000011111111", 2))
                bytes = bytes .. string.char(byte1) .. string.char(byte2) .. string.char(byte3) .. pixel.brush
            end
        end
    end
    return FORMAT .. bytes
end    

function bytesToCanvas(bytes)
    DBG_SAVE(1, bytes)
    DBG_PRINT("#FORMAT: " .. #FORMAT)
    local canvas = {}
    local offset = 1 + #FORMAT
    --DBG_PRINT(({bytes:find(FORMAT)})[1])
    if bytes:find(({FORMAT:gsub("%$", "%%$")})[1]) == 1 then
        for y = 1, canvasHeight do
            canvas[y] = {}
            for x = 1, canvasWidth do
                local red, green, blue, brush =
                    string.byte(bytes:sub(offset,   offset)),
                    string.byte(bytes:sub(offset+1, offset+1)),
                    string.byte(bytes:sub(offset+2, offset+2)),
                    bytes:sub(offset+3, offset+3)
                DBG_SAVE(2, blue)
                canvas[y][x] = {color=red<<16 + green<<8 + blue, brush=brush}
                offset = offset + 4
            end
        end
    else
        return false, "unknown format"
    end
    return canvas
end

function saveToFile(path)
    local file
    if path and not fs.isDirectory(path) then
        file = io.open(path, "w")
    else
        local i = 1
        while true do
            local filename = string.format("Безымянный %03d.pic", i)
            if not fs.exists(CWD .. "/" .. filename) then
                file = io.open(CWD .. "/" .. filename, "w")
                break
            end
            i = i + 1
        end
    end
    file:write(canvasToBytes(canvas))
    require"computer".beep() -- Убрать
    file:close()
    saved = true
end

function loadFromFile(path)
    local file, reason = io.open(path, "r")
    if not file then
        return false, reason
    end
    local content = file:read("*a")
    file:close()
    return bytesToCanvas(content)
end

function draw(canvas)
    for y = 1, canvasHeight do
        for x = 1, canvasWidth do
            pixel = canvas[y][x]
            gpu.setForeground(pixel.color)
            gpu.set(x, y, pixel.brush)
        end
    end
end
--
--
local args, options = shell.parse(...)

-- Создание матрицы холста
for y = 1, H do
    canvas[y] = {}
end

gpu.setResolution(W, H)
gpu.setForeground(DEFAULT_FG)
gpu.setBackground(DEFAULT_BG)
gpu.fill(1, 1, W, H, " ")

gpu.set(1, 6, "Палитра")
for i, color in pairs(palette) do
    gpu.setForeground(color)
    x, y = 1+(i-1)%8, 6+1+(i-1)//8
    gpu.set(x, y, "█")
end

gpu.setForeground(DEFAULT_FG)

local BRUSHES_PANEL_Y_MIN = y + 2 + 1
gpu.set(1, y + 2, "Кисть")
for i, brush in pairs(brushes) do
    x, y = 1+(i-1)%8, BRUSHES_PANEL_Y_MIN+(i-1)//8
    gpu.set(x, y, brush)
end
local BRUSHES_PANEL_Y_MAX = y

gpu.setBackground(0xFFFFFF)
gpu.fill(11, 3, canvasWidth, canvasHeight, " ")

if args[1] then
    local path = args[1]
    DBG_PRINT(path)
    canvas, reason = loadFromFile(path)
    if not canvas then
        error(reason)
    end
    draw(canvas)
end

while run do
    local signal = {event.pull()}
    local x, y = signal[3], signal[4]
    if (signal[1] == "drag" or signal[1] == "touch") and x >= 11 and x <= 156 and y >= 3 and y <= 48 then -- холст
        gpu.setForeground(currentColor)
        gpu.set(x, y, currentBrush)
        canvas[y][x] = {
            color = currentColor,
            brush = currentBrush
        }
        saved = false
    elseif signal[1] == "touch" and x >= 1 and x <= 8 and y >= 7 and y <= 7+(#palette-1)//8 then -- палитра
        --#   (i-1)//8 + 7 = 0    |    (i-1)//8 = -7
        --currentColor = gpu.getForeground(x, y)
        currentColor = palette[(y-6-1)*8 + x] or currentColor -- [x] [y-6]
    elseif signal[1] == "touch" and x >= 1 and x <= 8 and y >= BRUSHES_PANEL_Y_MIN and y <= BRUSHES_PANEL_Y_MAX then -- кисти
        currentBrush = brushes[(y-BRUSHES_PANEL_Y_MIN)*8 + x] or currentBrush
    elseif signal[1] == "key_up" and signal[3] == 19 then -- сохранение
        if not saved then
            saveToFile(path)
        end
    elseif signal[1] == "key_down" and signal[3] == 23 then -- закрытие
        if not saved then
            saveToFile("/tmp/" .. uuid.next() .. ".pic")
        end
        run = false
    end
end