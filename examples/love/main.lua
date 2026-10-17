-- Memory editor over a LÖVE ByteData:  love examples/love  (uses tools/core/build/imgui_love.lua)
local ROOT = love.filesystem.getSource() .. "/../../"   -- repo root
local f = assert(io.open(ROOT .. "tools/core/build/imgui_love.lua", "rb"), "missing tools/core: git submodule update --init")
local G = assert(loadstring(f:read("*a"), "@imgui_love.lua"))(); f:close()
local MemoryEditor = assert(loadfile(ROOT .. "MemoryEditor.lua"))()(G)
local ImGui = G.ImGui

data = love.data.newByteData(0x400) -- global: tests/love.lua checks it
local ptr = require("ffi").cast("uint8_t*", data:getFFIPointer())
for i = 0x40, 0x3FF do ptr[i] = (i * 37) % 256 end
local frame = 0

mem_edit = MemoryEditor.new()
mem_edit.OptShowDataPreview = true

function love.load()
    ImGui.CreateContext()
    local io = ImGui.GetIO()
    io.IniFilename = nil
    G.ImGui_ImplLove.Init({ root = ROOT .. "tools/core/" })
    io.Fonts:AddFontDefault()
end

function love.update(dt)
    frame = frame + 1
    ptr[0], ptr[1] = frame % 256, math.floor(frame / 256) % 256
    G.ImGui_ImplLove.NewFrame()
    ImGui.NewFrame()
    mem_edit:DrawWindow("Memory Editor", data) -- size defaults to data:getSize()
    ImGui.Render()
end

function love.draw()
    love.graphics.clear(0.45, 0.55, 0.60, 1)
    G.ImGui_ImplLove.RenderDrawData(ImGui.GetDrawData())
end

function love.mousemoved(x, y) G.ImGui_ImplLove.MouseMoved(x, y) end
function love.mousepressed(x, y, b) G.ImGui_ImplLove.MousePressed(x, y, b) end
function love.mousereleased(x, y, b) G.ImGui_ImplLove.MouseReleased(x, y, b) end
function love.wheelmoved(x, y) G.ImGui_ImplLove.WheelMoved(x, y) end
function love.keypressed(k) G.ImGui_ImplLove.KeyPressed(k) end
function love.keyreleased(k) G.ImGui_ImplLove.KeyReleased(k) end
function love.textinput(t) G.ImGui_ImplLove.TextInput(t) end
function love.focus(f) G.ImGui_ImplLove.Focus(f) end
