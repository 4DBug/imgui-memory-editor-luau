-- Memory editor over a Roblox buffer (live-updating counter at 0x00, a float at 0x10, a string at 0x20).
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local G = require(RS:WaitForChild("ImGui"))
local MemoryEditor = require(RS:WaitForChild("MemoryEditor"))(G)
local ImGui = G.ImGui

local data = buffer.create(0x400)
buffer.writef32(data, 0x10, math.pi)
buffer.writestring(data, 0x20, "Hello from a Roblox buffer!")
for i = 0x40, 0x3FF do buffer.writeu8(data, i, (i * 37) % 256) end

local mem_edit = MemoryEditor.new()
mem_edit.OptShowDataPreview = true
local mem_edit2 = MemoryEditor.new() -- DrawContents() inside your own window, highlighting even bytes
mem_edit2.HighlightFn = function(mem, off) return buffer.readu8(mem, off) % 2 == 0 end

ImGui.CreateContext()
G.ImGui_ImplRoblox.Init() -- defaults to LocalPlayer.PlayerGui
local frame = 0
RunService.RenderStepped:Connect(function()
	frame += 1
	buffer.writeu32(data, 0x00, frame)
	G.ImGui_ImplRoblox.NewFrame()
	ImGui.NewFrame()
	mem_edit:DrawWindow("Memory Editor", data) -- size defaults to buffer.len(data)
	local _, visible = ImGui.Begin("Memory Editor (DrawContents)") -- returns (open, visible)
	if visible then
		ImGui.Text("frame = %d (the u32 at 0x00)", frame)
		mem_edit2:DrawContents(data, 0x80, 0x1000) -- first 0x80 bytes, displayed from address 0x1000
	end
	ImGui.End()
	ImGui.Render()
	G.ImGui_ImplRoblox.RenderDrawData(ImGui.GetDrawData())
end)
