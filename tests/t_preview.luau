-- DrawPreviewData: every data type x LE/BE x Dec/Hex/Bin, compared with C printf output.
local RS = game:GetService("ReplicatedStorage")
local G = require(RS:WaitForChild("ImGui"))
local MemoryEditor = require(RS:WaitForChild("MemoryEditor"))(G)
local DT = G.ImGuiDataType
local ed = MemoryEditor.new()
local BIN, DEC, HEX = MemoryEditor.DataFormat_Bin, MemoryEditor.DataFormat_Dec, MemoryEditor.DataFormat_Hex

local function check(bytes, dt, endian, fmt, want)
    ed.PreviewEndianness = endian
    local got = ed:DrawPreviewData(0, bytes, #bytes, dt, fmt)
    assert(got == want, ("type %d endian %d fmt %d: got %q want %q"):format(dt, endian, fmt, got, want))
end
check({ 0xFF }, DT.S8, 0, DEC, "-1")
check({ 0xFF }, DT.U8, 0, DEC, "255")
check({ 0xFF }, DT.S8, 0, HEX, "0xff")
check({ 0x34, 0x12 }, DT.U16, 0, HEX, "0x1234")
check({ 0x34, 0x12 }, DT.U16, 1, HEX, "0x3412")
check({ 0x34, 0x12 }, DT.S16, 0, BIN, "00010010 00110100 ")
check({ 0xFE, 0xFF, 0xFF, 0xFF }, DT.S32, 0, DEC, "-2")
check({ 0xFE, 0xFF, 0xFF, 0xFF }, DT.U32, 0, DEC, "4294967294")
check({ 0xFE, 0xFF, 0xFF, 0xFF }, DT.S32, 0, HEX, "0xfffffffe")
check({ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF }, DT.U64, 0, DEC, "18446744073709551615")
check({ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF }, DT.S64, 0, DEC, "-1")
check({ 0, 0, 0, 0, 0, 0, 0, 0x80 }, DT.S64, 0, DEC, "-9223372036854775808")
check({ 1, 2, 3, 4, 5, 6, 7, 8 }, DT.U64, 0, HEX, "0x0807060504030201")
check({ 1, 2, 3, 4, 5, 6, 7, 8 }, DT.U64, 1, HEX, "0x0102030405060708")
check({ 0, 0, 0xC0, 0x3F }, DT.Float, 0, DEC, "1.500000")
check({ 0x3F, 0xC0, 0, 0 }, DT.Float, 1, DEC, "1.500000")
check({ 0, 0, 0xC0, 0x3F }, DT.Float, 0, HEX, "0x1.8p+0")
check({ 0, 0, 0x80, 0xBF }, DT.Float, 0, HEX, "-0x1p+0")
check({ 0, 0, 0, 0 }, DT.Float, 0, HEX, "0x0p+0")
check({ 1, 0, 0, 0 }, DT.Float, 0, HEX, "0x1p-149") -- float subnormal is a normal double
check({ 0, 0, 0x80, 0x7F }, DT.Float, 0, DEC, "inf")
check({ 0x18, 0x2D, 0x44, 0x54, 0xFB, 0x21, 0x09, 0x40 }, DT.Double, 0, DEC, "3.141593")
check({ 0x18, 0x2D, 0x44, 0x54, 0xFB, 0x21, 0x09, 0x40 }, DT.Double, 0, HEX, "0x1.921fb54442d18p+1")
check({ 1, 0, 0, 0, 0, 0, 0, 0 }, DT.Double, 0, HEX, "0x0.0000000000001p-1022")
-- truncated at the end of memory: only the available bytes
check({ 0x34, 0x12 }, DT.U32, 0, DEC, "4660")
check({ 0x34, 0x12 }, DT.U32, 0, BIN, "00010010 00110100 ")
-- buffer, string and ReadFn sources
local b = buffer.create(4); buffer.writeu32(b, 0, 0xDEADBEEF)
assert(ed:DrawPreviewData(0, b, 4, DT.U32, HEX) == "0xdeadbeef")
assert(ed:DrawPreviewData(0, "\xEF\xBE\xAD\xDE", 4, DT.U32, HEX) == "0xdeadbeef")
ed.ReadFn = function(mem, off) return mem[off + 1] + 1 end
assert(ed:DrawPreviewData(0, { 0x10, 0x20 }, 2, DT.U16, HEX) == "0x2111")
print("OK")
