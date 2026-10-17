-- LuaJIT: runs examples/love headless (core mock love) and types "AB" into byte 2 of the ByteData.
local ex = "examples/love"
dofile("tools/core/tools/test/love/mock_love.lua")
love.filesystem.getSource = function() return ex end
love.graphics.clear = function() end
dofile(ex .. "/main.lua")
love.load()
local function step() love.timer.step(1 / 60); love.update(1 / 60); love.draw() end
for i = 1, 5 do love.mousemoved(100 + i, 100); step() end
mem_edit:GotoAddrAndHighlight(2, 3)
for i = 1, 3 do step() end
love.textinput("A"); step(); love.textinput("B"); step(); step()
local ptr = require("ffi").cast("uint8_t*", data:getFFIPointer())
assert(ptr[2] == 0xAB, "byte 2 not written: " .. ptr[2])
assert(mem_edit.DataEditingAddr == 3, "editing did not advance")
-- preview decoding under LuaJIT (ImGuiDataType: U64 = 7, Float = 8; formats: Dec = 1, Hex = 2)
mem_edit.PreviewEndianness = 0
local ff = { 255, 255, 255, 255, 255, 255, 255, 255 }
assert(mem_edit:DrawPreviewData(0, ff, 8, 7, 1) == "18446744073709551615")
assert(mem_edit:DrawPreviewData(0, { 0, 0, 0xC0, 0x3F }, 4, 8, 2) == "0x1.8p+0")
assert(mem_edit:DrawPreviewData(0, { 0, 0, 0xC0, 0x3F }, 4, 8, 1) == "1.500000")
print("OK")
