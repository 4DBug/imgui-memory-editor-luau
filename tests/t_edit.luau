-- Hex editing in a Roblox buffer: GotoAddrAndHighlight focuses byte 2, typing "AB" writes 0xAB and moves to byte 3;
-- clicking a byte starts editing it; ReadOnly never writes; MouseHoveredAddr follows the mouse.
local RS = game:GetService("ReplicatedStorage")
local G = require(RS:WaitForChild("ImGui"))
local MemoryEditor = require(RS:WaitForChild("MemoryEditor"))(G)
local ImGui, ImVec2 = G.ImGui, G.ImVec2

ImGui.CreateContext()
G.ImGui_ImplRoblox.Init()
local io = ImGui.GetIO()

local mem = buffer.create(256)
for i = 0, 255 do buffer.writeu8(mem, i, i) end
local ed = MemoryEditor.new()
ed.OptShowDataPreview = true
local s = {}

local frame, done = 0, false
local cellPos -- screen pos of byte 0x15 (line 1, col 5), found from the child window
game:GetService("RunService").Stepped:Connect(function()
    if done then return end
    frame += 1
    G.ImGui_ImplRoblox.NewFrame()
    io.DeltaTime = 1 / 60
    if frame == 3 then ed:GotoAddrAndHighlight(2, 3)
    elseif frame == 6 then io:AddInputCharacter(string.byte("A"))
    elseif frame == 7 then io:AddInputCharacter(string.byte("B"))
    elseif frame == 12 then io:AddMousePosEvent(cellPos.x + 2, cellPos.y + 2)
    elseif frame == 14 then io:AddMouseButtonEvent(0, true)
    elseif frame == 15 then io:AddMouseButtonEvent(0, false)
    elseif frame == 18 then ed.ReadOnly = true
    elseif frame == 20 then io:AddInputCharacter(string.byte("F"))
    elseif frame == 21 then io:AddInputCharacter(string.byte("F"))
    end
    ImGui.NewFrame()
    ImGui.SetNextWindowPos(ImVec2(0, 0))
    ed:DrawWindow("Memory", mem)
    if frame == 11 then
        local w = ImGui.FindWindowByName("Memory")
        local child = w.DC.ChildWindows.Data[1]
        ed:CalcSizes(s, 256, 0)
        local x = child.Pos.x + s.OffsetHexMinX + s.HexCellWidth * 5
        cellPos = ImVec2(x, child.Pos.y + child.WindowPadding.y + s.LineHeight * 1)
    end
    ImGui.Render()
    G.ImGui_ImplRoblox.RenderDrawData(ImGui.GetDrawData())
    if frame == 10 then
        assert(buffer.readu8(mem, 2) == 0xAB, "byte 2 not written: " .. buffer.readu8(mem, 2))
        assert(buffer.readu8(mem, 3) == 3, "byte 3 changed")
        assert(ed.DataEditingAddr == 3, "editing did not advance: " .. ed.DataEditingAddr)
        assert(ed.DataPreviewAddr == 3)
    elseif frame == 13 then
        assert(ed.MouseHovered and ed.MouseHoveredAddr == 0x15, "hovered " .. tostring(ed.MouseHoveredAddr))
    elseif frame == 17 then
        assert(ed.DataEditingAddr == 0x15, "click did not start editing: " .. ed.DataEditingAddr)
    elseif frame == 26 then
        done = true
        assert(buffer.readu8(mem, 0x15) == 0x15, "ReadOnly wrote")
        print("OK")
    end
end)
