-- Memory Editor for imgui-luau. Port of imgui_club's imgui_memory_editor.h v0.59
-- (https://github.com/ocornut/imgui_club @ b083116866e05e0d4bccb2c7f28d94a76ee4965e).
-- Usage (same as C++):
--   local MemoryEditor = require(path.MemoryEditor)(G)    -- G = the table returned by the ImGui module
--   local mem_edit = MemoryEditor.new()                    -- C++: static MemoryEditor mem_edit;
--   mem_edit:DrawWindow("Memory Editor", data, size)       -- or mem_edit:DrawContents(data, size)
-- [Port] mem_data (C++ void*) is a Roblox `buffer`, a LÖVE `ByteData` (FFI pointer, or getString() read-only
-- without FFI) or a table of bytes (index 1 = offset 0). mem_size defaults to the data's length.
-- Offsets/addresses are 0-based like upstream; "none" (C++ (size_t)-1) is -1.
-- Plain Lua 5.1 syntax so the same file loads on LÖVE (LuaJIT).
return function(G)
    local ImGui, ImVec2 = G.ImGui, G.ImVec2
    local ImGuiCol, ImGuiKey, ImGuiCond = G.ImGuiCol, G.ImGuiKey, G.ImGuiCond
    local ImGuiWindowFlags, ImGuiChildFlags, ImGuiInputTextFlags = G.ImGuiWindowFlags, G.ImGuiChildFlags, G.ImGuiInputTextFlags
    local ImGuiStyleVar, ImGuiComboFlags, ImGuiHoveredFlags, ImGuiDataType = G.ImGuiStyleVar, G.ImGuiComboFlags, G.ImGuiHoveredFlags, G.ImGuiDataType
    local FLT_MIN, FLT_MAX, IM_COL32 = G.FLT_MIN, G.FLT_MAX, G.IM_COL32
    local bor, floor, format, char, byte = bit32.bor, math.floor, string.format, string.char, string.byte
    local NONE = -1

    local MemoryEditor = {}
    MemoryEditor.__index = MemoryEditor
    MemoryEditor.DataFormat_Bin, MemoryEditor.DataFormat_Dec, MemoryEditor.DataFormat_Hex, MemoryEditor.DataFormat_COUNT = 0, 1, 2, 3

    -- [Port] void* -> accessors. Returns read(off) -> byte, write(off, byte) or nil, length.
    local ffi
    do
        local ok, m = pcall(require, "ffi")
        if ok then ffi = m end
    end
    local function Access(mem)
        local t = type(mem)
        if t == "buffer" then -- Roblox/Luau
            local readu8, writeu8 = buffer.readu8, buffer.writeu8
            return function(off) return readu8(mem, off) end, function(off, d) writeu8(mem, off, d) end, buffer.len(mem)
        elseif t == "string" then
            return function(off) return byte(mem, off + 1) or 0 end, nil, #mem
        elseif (t == "userdata" or t == "table") and mem.getSize then -- LÖVE Data (ByteData, ImageData, ...)
            local n = mem:getSize()
            if ffi and mem.getFFIPointer then
                local p = ffi.cast("uint8_t*", mem:getFFIPointer())
                return function(off) return p[off] end, function(off, d) p[off] = d end, n
            end
            local s = mem:getString()
            return function(off) return byte(s, off + 1) or 0 end, nil, n
        elseif t == "table" then
            return function(off) return mem[off + 1] or 0 end, function(off, d) mem[off + 1] = d end, #mem
        end
        error("MemoryEditor: unsupported mem_data type " .. t)
    end
    MemoryEditor.Access = Access

    function MemoryEditor.new()
        local self = setmetatable({}, MemoryEditor)
        -- Settings
        self.Open = true                  -- set to false when DrawWindow() was closed. ignore if not using DrawWindow().
        self.ReadOnly = false             -- disable any editing.
        self.Cols = 16                    -- number of columns to display.
        self.OptShowOptions = true        -- display options button/context menu.
        self.OptShowDataPreview = false   -- display a footer previewing the decimal/binary/hex/float representation of the selected bytes.
        self.OptShowHexII = false         -- display values in HexII representation instead of regular hexadecimal.
        self.OptShowAscii = true          -- display ASCII representation on the right side.
        self.OptGreyOutZeroes = true      -- display null/zero bytes using the TextDisabled color.
        self.OptUpperCaseHex = true       -- display hexadecimal values as "FF" instead of "ff".
        self.OptMidColsCount = 8          -- set to 0 to disable extra spacing between every mid-cols.
        self.OptAddrDigitsCount = 0       -- number of addr digits to display (default calculated based on maximum displayed addr).
        self.OptFooterExtraHeight = 0.0   -- space to reserve at the bottom of the widget to add custom widgets
        self.HighlightColor = IM_COL32(255, 255, 255, 50)
        -- Function handlers: ReadFn(mem, off, user_data) -> byte, WriteFn(mem, off, d, user_data),
        -- HighlightFn(mem, off, user_data) -> bool, BgColorFn(mem, off, user_data) -> ImU32
        self.ReadFn, self.WriteFn, self.HighlightFn, self.BgColorFn, self.UserData = nil, nil, nil, nil, nil
        -- Public read-only data
        self.MouseHovered = false
        self.MouseHoveredAddr = 0
        -- [Internal State]
        self.ContentsWidthChanged = false
        self.DataPreviewAddr, self.DataEditingAddr = NONE, NONE
        self.DataEditingTakeFocus = false
        self.DataInputBuf = ImGui.NewTextBuffer("", 32)
        self.AddrInputBuf = ImGui.NewTextBuffer("", 32)
        self.GotoAddr = NONE
        self.HighlightMin, self.HighlightMax = NONE, NONE
        self.PreviewEndianness = 0
        self.PreviewDataType = ImGuiDataType.S32
        return self
    end

    function MemoryEditor:GotoAddrAndHighlight(addr_min, addr_max)
        self.GotoAddr = addr_min
        self.HighlightMin = addr_min
        self.HighlightMax = addr_max
    end

    function MemoryEditor:CalcSizes(s, mem_size, base_display_addr)
        local style = ImGui.GetStyle()
        s.AddrDigitsCount = self.OptAddrDigitsCount
        if s.AddrDigitsCount == 0 then
            local n = base_display_addr + mem_size - 1
            while n > 0 do s.AddrDigitsCount = s.AddrDigitsCount + 1; n = floor(n / 16) end
        end
        s.LineHeight = ImGui.GetTextLineHeight()
        s.GlyphWidth = ImGui.CalcTextSize("F").x + 1                 -- We assume the font is mono-space
        s.HexCellWidth = floor(s.GlyphWidth * 2.5)                    -- "FF " we include trailing space in the width to easily catch clicks everywhere
        s.SpacingBetweenMidCols = floor(s.HexCellWidth * 0.25)        -- Every OptMidColsCount columns we add a bit of extra spacing
        s.OffsetHexMinX = (s.AddrDigitsCount + 2) * s.GlyphWidth
        s.OffsetHexMaxX = s.OffsetHexMinX + (s.HexCellWidth * self.Cols)
        s.OffsetAsciiMinX, s.OffsetAsciiMaxX = s.OffsetHexMaxX, s.OffsetHexMaxX
        if self.OptShowAscii then
            s.OffsetAsciiMinX = s.OffsetHexMaxX + s.GlyphWidth * 1
            if self.OptMidColsCount > 0 then
                s.OffsetAsciiMinX = s.OffsetAsciiMinX + floor((self.Cols + self.OptMidColsCount - 1) / self.OptMidColsCount) * s.SpacingBetweenMidCols
            end
            s.OffsetAsciiMaxX = s.OffsetAsciiMinX + self.Cols * s.GlyphWidth
        end
        s.WindowWidth = s.OffsetAsciiMaxX + style.ScrollbarSize + style.WindowPadding.x * 2 + s.GlyphWidth
    end

    -- Standalone Memory Editor window
    function MemoryEditor:DrawWindow(title, mem_data, mem_size, base_display_addr)
        if mem_size == nil then mem_size = select(3, Access(mem_data)) end
        base_display_addr = base_display_addr or 0
        local s = {}
        self:CalcSizes(s, mem_size, base_display_addr)
        ImGui.SetNextWindowSize(ImVec2(s.WindowWidth, s.WindowWidth * 0.60), ImGuiCond.FirstUseEver)
        ImGui.SetNextWindowSizeConstraints(ImVec2(0.0, 0.0), ImVec2(s.WindowWidth, FLT_MAX))

        local open, visible = ImGui.Begin(title, true, ImGuiWindowFlags.NoScrollbar)
        self.Open = open
        if visible then
            self:DrawContents(mem_data, mem_size, base_display_addr)
            if self.ContentsWidthChanged then
                self:CalcSizes(s, mem_size, base_display_addr)
                ImGui.SetWindowSize(ImVec2(s.WindowWidth, ImGui.GetWindowSize().y))
            end
        end
        ImGui.End()
    end

    -- InputText callback for the byte being edited (upstream InputTextUserData::Callback)
    local function DataInputCallback(data)
        local user_data = data.UserData
        if not data:HasSelection() then
            user_data.CursorPos = data.CursorPos
        end
        if data.SelectionStart == 0 and data.SelectionEnd == data.BufTextLen then
            -- When not editing a byte, always refresh its InputText content pulled from underlying memory data
            data:DeleteChars(0, data.BufTextLen)
            data:InsertChars(0, user_data.CurrentBufOverwrite)
            data.SelectionStart = 0
            data.SelectionEnd = 2
            data.CursorPos = 0
        end
        return 0
    end
    local input_text_user_data = { CurrentBufOverwrite = "", CursorPos = -1 }

    local function SetBuf(buf, str) -- snprintf into a NewTextBuffer
        for i = 1, #buf do buf[i] = byte(str, i) or 0 end
        buf[#buf] = 0
    end
    local function Hex(upper, digits, v) -- "%0*zX" / "%0*zx"
        return format(upper and "%0" .. math.max(digits, 1) .. "X" or "%0" .. math.max(digits, 1) .. "x", v)
    end
    MemoryEditor._Hex = Hex

    -- Memory Editor contents only
    function MemoryEditor:DrawContents(mem_data, mem_size, base_display_addr)
        if self.Cols < 1 then self.Cols = 1 end
        local read, write, len = Access(mem_data)
        if mem_size == nil then mem_size = len end
        base_display_addr = base_display_addr or 0
        local ReadFn, WriteFn, HighlightFn, BgColorFn, UserData = self.ReadFn, self.WriteFn, self.HighlightFn, self.BgColorFn, self.UserData
        local function Read(addr)
            if ReadFn then return ReadFn(mem_data, addr, UserData) end
            return read(addr)
        end
        local Cols, OptMidColsCount = self.Cols, self.OptMidColsCount

        local s = {}
        self:CalcSizes(s, mem_size, base_display_addr)
        local style = ImGui.GetStyle()

        local contents_pos_start = ImGui.GetCursorScreenPos()

        -- We begin into our scrolling region with the 'ImGuiWindowFlags_NoMove' in order to prevent click from moving the window.
        local height_separator = style.ItemSpacing.y
        local footer_height = self.OptFooterExtraHeight
        if self.OptShowOptions then
            footer_height = footer_height + height_separator + ImGui.GetFrameHeightWithSpacing() * 1
        end
        if self.OptShowDataPreview then
            footer_height = footer_height + height_separator + ImGui.GetFrameHeightWithSpacing() * 1 + ImGui.GetTextLineHeightWithSpacing() * 3
        end
        ImGui.BeginChild("##scrolling", ImVec2(-FLT_MIN, -footer_height), ImGuiChildFlags.None, bor(ImGuiWindowFlags.NoMove, ImGuiWindowFlags.NoNav))
        local draw_list = ImGui.GetWindowDrawList()

        ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, ImVec2(0, 0))
        ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, ImVec2(0, 0))

        -- We are not really using the clipper API correctly here, because we rely on visible_start_addr/visible_end_addr for our scrolling function.
        local avail_size = ImGui.GetContentRegionAvail()
        local line_total_count = floor((mem_size + Cols - 1) / Cols)
        local clipper = G.ImGuiListClipper()
        clipper:Begin(line_total_count, s.LineHeight)

        local data_next = false

        if self.DataEditingAddr >= mem_size then self.DataEditingAddr = NONE end
        if self.DataPreviewAddr >= mem_size then self.DataPreviewAddr = NONE end

        local preview_data_type_size = self.OptShowDataPreview and self:DataTypeGetSize(self.PreviewDataType) or 0
        local DataPreviewAddr = self.DataPreviewAddr
        local preview_end = DataPreviewAddr ~= NONE and DataPreviewAddr + preview_data_type_size or NONE -- [Port] no size_t wrap

        local data_editing_addr_next = NONE
        if self.DataEditingAddr ~= NONE then
            -- Move cursor but only apply on next frame so scrolling with be synchronized
            local a = self.DataEditingAddr
            if ImGui.IsKeyPressed(ImGuiKey.UpArrow) and a >= Cols then data_editing_addr_next = a - Cols
            elseif ImGui.IsKeyPressed(ImGuiKey.DownArrow) and a < mem_size - Cols then data_editing_addr_next = a + Cols
            elseif ImGui.IsKeyPressed(ImGuiKey.LeftArrow) and a > 0 then data_editing_addr_next = a - 1
            elseif ImGui.IsKeyPressed(ImGuiKey.RightArrow) and a < mem_size - 1 then data_editing_addr_next = a + 1
            end
        end

        -- Draw vertical separator
        local window_pos = ImGui.GetWindowPos()
        if self.OptShowAscii then
            local x = window_pos.x + s.OffsetAsciiMinX - s.GlyphWidth
            draw_list:AddLine(ImVec2(x, window_pos.y), ImVec2(x, window_pos.y + 9999), ImGui.GetColorU32(ImGuiCol.Border))
        end

        local color_text = ImGui.GetColorU32(ImGuiCol.Text)
        local color_disabled = self.OptGreyOutZeroes and ImGui.GetColorU32(ImGuiCol.TextDisabled) or color_text

        local upper = self.OptUpperCaseHex
        local format_byte = upper and "%02X" or "%02x"
        local format_byte_space = upper and "%02X " or "%02x "

        self.MouseHovered = false
        self.MouseHoveredAddr = 0

        local HighlightMin, HighlightMax = self.HighlightMin, self.HighlightMax
        local function InPreview(a) return DataPreviewAddr ~= NONE and a >= DataPreviewAddr and a < preview_end end

        while clipper:Step() do
            for line_i = clipper.DisplayStart, clipper.DisplayEnd - 1 do -- display only visible lines
                local addr = line_i * Cols
                ImGui.TextUnformatted(Hex(upper, s.AddrDigitsCount, base_display_addr + addr) .. ": ")

                -- Draw Hexadecimal
                local n = 0
                while n < Cols and addr < mem_size do
                    local byte_pos_x = s.OffsetHexMinX + s.HexCellWidth * n
                    if OptMidColsCount > 0 then
                        byte_pos_x = byte_pos_x + floor(n / OptMidColsCount) * s.SpacingBetweenMidCols
                    end
                    ImGui.SameLine(byte_pos_x)

                    -- Draw highlight or custom background color
                    local is_highlight_from_user_range = (addr >= HighlightMin and addr < HighlightMax)
                    local is_highlight_from_user_func = (HighlightFn ~= nil and HighlightFn(mem_data, addr, UserData)) and true or false
                    local is_highlight_from_preview = InPreview(addr)

                    local bg_color = 0
                    local is_next_byte_highlighted = false
                    if is_highlight_from_user_range or is_highlight_from_user_func or is_highlight_from_preview then
                        is_next_byte_highlighted = (addr + 1 < mem_size) and ((HighlightMax ~= NONE and addr + 1 < HighlightMax)
                            or (HighlightFn ~= nil and HighlightFn(mem_data, addr + 1, UserData) and true) or InPreview(addr + 1)) or false
                        bg_color = self.HighlightColor
                    elseif BgColorFn ~= nil then
                        is_next_byte_highlighted = (addr + 1 < mem_size) and (BgColorFn(mem_data, addr + 1, UserData) >= 0x1000000) -- & IM_COL32_A_MASK
                        bg_color = BgColorFn(mem_data, addr, UserData)
                    end
                    if bg_color ~= 0 then
                        local bg_width = s.GlyphWidth * 2
                        if is_next_byte_highlighted or (n + 1 == Cols) then
                            bg_width = s.HexCellWidth
                            if OptMidColsCount > 0 and n > 0 and (n + 1) < Cols and ((n + 1) % OptMidColsCount) == 0 then
                                bg_width = bg_width + s.SpacingBetweenMidCols
                            end
                        end
                        local pos = ImGui.GetCursorScreenPos()
                        draw_list:AddRectFilled(pos, ImVec2(pos.x + bg_width, pos.y + s.LineHeight), bg_color)
                    end

                    if self.DataEditingAddr == addr then
                        -- Display text input on current byte
                        local data_write = false
                        ImGui.PushID(addr)
                        if self.DataEditingTakeFocus then
                            ImGui.SetKeyboardFocusHere(0)
                            SetBuf(self.AddrInputBuf, Hex(upper, s.AddrDigitsCount, base_display_addr + addr))
                            SetBuf(self.DataInputBuf, format(format_byte, Read(addr)))
                        end
                        input_text_user_data.CursorPos = -1
                        input_text_user_data.CurrentBufOverwrite = format(format_byte, Read(addr))
                        local flags = bor(ImGuiInputTextFlags.CharsHexadecimal, ImGuiInputTextFlags.EnterReturnsTrue, ImGuiInputTextFlags.AutoSelectAll,
                            ImGuiInputTextFlags.NoHorizontalScroll, ImGuiInputTextFlags.CallbackAlways)
                        if self.ReadOnly then flags = bor(flags, ImGuiInputTextFlags.ReadOnly) end
                        flags = bor(flags, ImGuiInputTextFlags.AlwaysOverwrite)
                        ImGui.SetNextItemWidth(s.GlyphWidth * 2)
                        if ImGui.InputText("##data", self.DataInputBuf, 32, flags, DataInputCallback, input_text_user_data) then
                            data_write, data_next = true, true
                        elseif not self.DataEditingTakeFocus and not ImGui.IsItemActive() then
                            self.DataEditingAddr, data_editing_addr_next = NONE, NONE
                        end
                        self.DataEditingTakeFocus = false
                        if input_text_user_data.CursorPos >= 2 then data_write, data_next = true, true end
                        if data_editing_addr_next ~= NONE then data_write, data_next = false, false end
                        local hex = ImGui.TextBufferToString(self.DataInputBuf):match("^%s*(%x+)") -- sscanf("%X")
                        if not self.ReadOnly and data_write and hex then
                            local data_input_value = tonumber(hex, 16) % 256
                            if WriteFn then
                                WriteFn(mem_data, addr, data_input_value, UserData)
                            elseif write then
                                write(addr, data_input_value)
                            end
                        end
                        if ImGui.IsItemHovered() then
                            self.MouseHovered = true
                            self.MouseHoveredAddr = addr
                        end
                        ImGui.PopID()
                    else
                        -- NB: The trailing space is not visible but ensure there's no gap that the mouse cannot click on.
                        local b = Read(addr)

                        if self.OptShowHexII then
                            if b >= 32 and b < 128 then
                                ImGui.TextUnformatted("." .. char(b) .. " ")
                            elseif b == 0xFF and self.OptGreyOutZeroes then
                                ImGui.TextDisabled("## ")
                            elseif b == 0x00 then
                                ImGui.TextUnformatted("   ")
                            else
                                ImGui.TextUnformatted(format(format_byte_space, b))
                            end
                        else
                            if b == 0 and self.OptGreyOutZeroes then
                                ImGui.TextDisabled("00 ")
                            else
                                ImGui.TextUnformatted(format(format_byte_space, b))
                            end
                        end
                        if ImGui.IsItemHovered() then
                            self.MouseHovered = true
                            self.MouseHoveredAddr = addr
                            if ImGui.IsMouseClicked(0) then
                                self.DataEditingTakeFocus = true
                                data_editing_addr_next = addr
                            end
                        end
                    end
                    n, addr = n + 1, addr + 1
                end

                if self.OptShowAscii then
                    -- Draw ASCII values
                    ImGui.SameLine(s.OffsetAsciiMinX)
                    local pos = ImGui.GetCursorScreenPos()
                    addr = line_i * Cols

                    local mouse_off_x = ImGui.GetIO().MousePos.x - pos.x
                    local mouse_addr = (mouse_off_x >= 0.0 and mouse_off_x < s.OffsetAsciiMaxX - s.OffsetAsciiMinX) and addr + floor(mouse_off_x / s.GlyphWidth) or NONE

                    ImGui.PushID(line_i)
                    if ImGui.InvisibleButton("ascii", ImVec2(s.OffsetAsciiMaxX - s.OffsetAsciiMinX, s.LineHeight)) then
                        self.DataEditingAddr, self.DataPreviewAddr = mouse_addr, mouse_addr
                        self.DataEditingTakeFocus = true
                    end
                    if ImGui.IsItemHovered() then
                        self.MouseHovered = true
                        self.MouseHoveredAddr = mouse_addr
                    end
                    ImGui.PopID()
                    n = 0
                    while n < Cols and addr < mem_size do
                        local pmax = ImVec2(pos.x + s.GlyphWidth, pos.y + s.LineHeight)
                        if addr == self.DataEditingAddr then
                            draw_list:AddRectFilled(pos, pmax, ImGui.GetColorU32(ImGuiCol.FrameBg))
                            draw_list:AddRectFilled(pos, pmax, ImGui.GetColorU32(ImGuiCol.TextSelectedBg))
                        elseif BgColorFn then
                            draw_list:AddRectFilled(pos, pmax, BgColorFn(mem_data, addr, UserData))
                        end
                        local c = Read(addr)
                        local printable = c >= 32 and c < 128
                        draw_list:AddText(pos, printable and color_text or color_disabled, printable and char(c) or ".")
                        pos = ImVec2(pos.x + s.GlyphWidth, pos.y)
                        n, addr = n + 1, addr + 1
                    end
                end
            end
        end
        ImGui.PopStyleVar(2)
        local child_width = ImGui.GetWindowSize().x
        ImGui.EndChild()

        -- Notify the main window of our ideal child content size
        local backup_pos = ImGui.GetCursorScreenPos()
        ImGui.SetCursorPosX(s.WindowWidth)
        ImGui.Dummy(ImVec2(0.0, 0.0))
        ImGui.SetCursorScreenPos(backup_pos)

        if data_next and self.DataEditingAddr + 1 < mem_size then
            self.DataEditingAddr = self.DataEditingAddr + 1
            self.DataPreviewAddr = self.DataEditingAddr
            self.DataEditingTakeFocus = true
        elseif data_editing_addr_next ~= NONE then
            self.DataEditingAddr, self.DataPreviewAddr = data_editing_addr_next, data_editing_addr_next
            self.DataEditingTakeFocus = true
        end

        local lock_show_data_preview = self.OptShowDataPreview
        if self.OptShowOptions then
            ImGui.Separator()
            self:DrawOptionsLine(s, mem_data, mem_size, base_display_addr)
        end

        if lock_show_data_preview then
            ImGui.Separator()
            self:DrawPreviewLine(s, mem_data, mem_size, base_display_addr)
        end

        if self.GotoAddr ~= NONE then
            if self.GotoAddr >= 0 and self.GotoAddr < mem_size then
                ImGui.BeginChild("##scrolling")
                ImGui.SetScrollY(floor(self.GotoAddr / Cols) * ImGui.GetTextLineHeight() - avail_size.y * 0.5)
                ImGui.EndChild()
                self.DataEditingAddr, self.DataPreviewAddr = self.GotoAddr, self.GotoAddr
                self.DataEditingTakeFocus = true
            end
            self.GotoAddr = NONE
        end

        local contents_pos_end = ImVec2(contents_pos_start.x + child_width, ImGui.GetCursorScreenPos().y)
        if self.OptShowOptions then
            if ImGui.IsMouseHoveringRect(contents_pos_start, contents_pos_end) then
                if ImGui.IsWindowHovered(ImGuiHoveredFlags.ChildWindows) and ImGui.IsMouseReleased(1) then
                    ImGui.OpenPopup("OptionsPopup")
                end
            end
        end

        if ImGui.BeginPopup("OptionsPopup") then
            local changed, _
            ImGui.SetNextItemWidth(s.GlyphWidth * 7 + style.FramePadding.x * 2.0)
            self.Cols, changed = ImGui.DragInt("##cols", self.Cols, 0.2, 4, 32, "%d cols")
            if changed then self.ContentsWidthChanged = true; if self.Cols < 1 then self.Cols = 1 end end
            _, self.OptShowDataPreview = ImGui.Checkbox("Show Data Preview", self.OptShowDataPreview)
            _, self.OptShowHexII = ImGui.Checkbox("Show HexII", self.OptShowHexII)
            changed, self.OptShowAscii = ImGui.Checkbox("Show Ascii", self.OptShowAscii)
            if changed then self.ContentsWidthChanged = true end
            _, self.OptGreyOutZeroes = ImGui.Checkbox("Grey out zeroes", self.OptGreyOutZeroes)
            _, self.OptUpperCaseHex = ImGui.Checkbox("Uppercase Hex", self.OptUpperCaseHex)
            ImGui.EndPopup()
        end
    end

    function MemoryEditor:DrawOptionsLine(s, mem_data, mem_size, base_display_addr)
        local style = ImGui.GetStyle()
        local upper = self.OptUpperCaseHex

        -- Options menu
        if ImGui.Button("Options") then
            ImGui.OpenPopup("OptionsPopup")
        end

        ImGui.SameLine()
        ImGui.TextUnformatted("Range " .. Hex(upper, s.AddrDigitsCount, base_display_addr) .. ".." .. Hex(upper, s.AddrDigitsCount, base_display_addr + mem_size - 1))
        ImGui.SameLine()
        ImGui.SetNextItemWidth((s.AddrDigitsCount + 1) * s.GlyphWidth + style.FramePadding.x * 2.0)
        if ImGui.InputText("##addr", self.AddrInputBuf, 32, bor(ImGuiInputTextFlags.CharsHexadecimal, ImGuiInputTextFlags.EnterReturnsTrue)) then
            local hex = ImGui.TextBufferToString(self.AddrInputBuf):match("^%s*(%x+)")
            if hex then
                self.GotoAddr = tonumber(hex, 16) - base_display_addr
                self.HighlightMin, self.HighlightMax = NONE, NONE
            end
        end
    end

    local supported_data_types = { "S8", "U8", "S16", "U16", "S32", "U32", "S64", "U64", "Float", "Double" }

    function MemoryEditor:DrawPreviewLine(s, mem_data, mem_size, base_display_addr)
        local style = ImGui.GetStyle()
        ImGui.AlignTextToFramePadding()
        ImGui.TextUnformatted("Preview as:")
        ImGui.SameLine()
        ImGui.SetNextItemWidth((s.GlyphWidth * 10.0) + style.FramePadding.x * 2.0 + style.ItemInnerSpacing.x)

        if ImGui.BeginCombo("##combo_type", self:DataTypeGetDesc(self.PreviewDataType), ImGuiComboFlags.HeightLargest) then
            for n = 1, #supported_data_types do
                local data_type = ImGuiDataType[supported_data_types[n]]
                if ImGui.Selectable(self:DataTypeGetDesc(data_type), self.PreviewDataType == data_type) then
                    self.PreviewDataType = data_type
                end
            end
            ImGui.EndCombo()
        end
        ImGui.SameLine()
        ImGui.SetNextItemWidth((s.GlyphWidth * 6.0) + style.FramePadding.x * 2.0 + style.ItemInnerSpacing.x)
        self.PreviewEndianness = ImGui.Combo("##combo_endianness", self.PreviewEndianness, "LE\0BE\0\0")

        local x = s.GlyphWidth * 6.0
        local has_value = self.DataPreviewAddr ~= NONE
        local buf = has_value and self:DrawPreviewData(self.DataPreviewAddr, mem_data, mem_size, self.PreviewDataType, MemoryEditor.DataFormat_Dec)
        ImGui.TextUnformatted("Dec"); ImGui.SameLine(x); ImGui.TextUnformatted(has_value and buf or "N/A")
        buf = has_value and self:DrawPreviewData(self.DataPreviewAddr, mem_data, mem_size, self.PreviewDataType, MemoryEditor.DataFormat_Hex)
        ImGui.TextUnformatted("Hex"); ImGui.SameLine(x); ImGui.TextUnformatted(has_value and buf or "N/A")
        buf = has_value and self:DrawPreviewData(self.DataPreviewAddr, mem_data, mem_size, self.PreviewDataType, MemoryEditor.DataFormat_Bin)
        ImGui.TextUnformatted("Bin"); ImGui.SameLine(x); ImGui.TextUnformatted(has_value and buf or "N/A")
    end

    -- Utilities for Data Preview
    local descs = { "Int8", "Uint8", "Int16", "Uint16", "Int32", "Uint32", "Int64", "Uint64", "Float", "Double" }
    local sizes = { 1, 1, 2, 2, 4, 4, 8, 8, 4, 8 }
    function MemoryEditor:DataTypeGetDesc(data_type) return assert(descs[data_type + 1]) end
    function MemoryEditor:DataTypeGetSize(data_type) return assert(sizes[data_type + 1]) end
    function MemoryEditor:DataFormatGetDesc(data_format) return assert(({ "Bin", "Dec", "Hex" })[data_format + 1]) end

    -- [Port] bytes in little-endian value order (le[1] = least significant), 8 entries, zero padded
    local function FormatBinary(le, width)
        local out = {}
        for j = width / 8, 1, -1 do
            local b = le[j]
            for i = 7, 0, -1 do out[#out + 1] = (floor(b / 2 ^ i) % 2 == 1) and "1" or "0" end
            out[#out + 1] = " "
        end
        return table.concat(out)
    end

    local function UnsignedDec(le, n) -- exact decimal of an n-byte unsigned integer (Lua numbers stop at 2^53)
        local digits, bytes = {}, {}
        for i = 1, n do bytes[i] = le[i] end
        repeat
            local rem, nonzero = 0, false
            for i = n, 1, -1 do
                local cur = rem * 256 + bytes[i]
                bytes[i] = floor(cur / 10); rem = cur % 10
                if bytes[i] ~= 0 then nonzero = true end
            end
            table.insert(digits, 1, tostring(rem))
        until not nonzero
        return table.concat(digits)
    end

    local function SignedDec(le, n)
        if le[n] < 128 then return UnsignedDec(le, n) end
        local neg, carry = {}, 1 -- two's complement magnitude
        for i = 1, n do
            local v = (255 - le[i]) + carry
            neg[i] = v % 256; carry = floor(v / 256)
        end
        return "-" .. UnsignedDec(neg, n)
    end

    local function HexBytes(le, n)
        local t = {}
        for i = n, 1, -1 do t[#t + 1] = format("%02x", le[i]) end
        return table.concat(t)
    end

    local function DecodeFloat(le, double) -- IEEE 754 from bytes, platform independent
        local sign, exp, mant, mbits, bias
        if double then
            sign = le[8] >= 128
            exp = (le[8] % 128) * 16 + floor(le[7] / 16)
            mant = (le[7] % 16) * 2 ^ 48 + le[6] * 2 ^ 40 + le[5] * 2 ^ 32 + le[4] * 2 ^ 24 + le[3] * 2 ^ 16 + le[2] * 2 ^ 8 + le[1]
            mbits, bias = 52, 1023
        else
            sign = le[4] >= 128
            exp = (le[4] % 128) * 2 + floor(le[3] / 128)
            mant = (le[3] % 128) * 65536 + le[2] * 256 + le[1]
            mbits, bias = 23, 127
        end
        local v
        if exp == bias * 2 + 1 then
            v = mant == 0 and math.huge or 0 / 0
        elseif exp == 0 then
            v = mant * 2 ^ (1 - bias - mbits)
        else
            v = (1 + mant / 2 ^ mbits) * 2 ^ (exp - bias)
        end
        return sign and -v or v, sign
    end

    local function HexDigits52(f) -- 13 hex digits of a 52-bit fraction, trailing zeros trimmed
        local t = {}
        for i = 12, 0, -1 do t[#t + 1] = format("%x", floor(f / 16 ^ i) % 16) end
        return (table.concat(t):gsub("0+$", ""))
    end

    local function FormatHexFloat(v, sign) -- C "%a" (glibc) of a double
        local s = sign and "-" or ""
        if v ~= v then return s .. "nan" end
        v = math.abs(v)
        if v == math.huge then return s .. "inf" end
        if v == 0 then return s .. "0x0p+0" end
        if v < 2 ^ -1022 then -- double subnormal
            local h = HexDigits52(v / 2 ^ -1074)
            return s .. "0x0" .. (h ~= "" and "." .. h or "") .. "p-1022"
        end
        local m, e = math.frexp(v) -- v = m * 2^e, m in [0.5, 1)
        local h = HexDigits52((m * 2 - 1) * 2 ^ 52)
        return s .. "0x1" .. (h ~= "" and "." .. h or "") .. format("p%+d", e - 1)
    end

    -- [Internal] [Port] returns the string (C++ writes into out_buf)
    function MemoryEditor:DrawPreviewData(addr, mem_data, mem_size, data_type, data_format)
        local elem_size = self:DataTypeGetSize(data_type)
        local size = (addr + elem_size > mem_size) and mem_size - addr or elem_size
        local buf = {}
        if self.ReadFn then
            for i = 0, size - 1 do buf[i + 1] = self.ReadFn(mem_data, addr + i, self.UserData) end
        else
            local read = Access(mem_data)
            for i = 0, size - 1 do buf[i + 1] = read(addr + i) end
        end
        local le = {} -- EndiannessCopy: PreviewEndianness 0 = LE, 1 = BE
        for i = 1, 8 do
            if i > size then le[i] = 0
            elseif self.PreviewEndianness == 0 then le[i] = buf[i]
            else le[i] = buf[size - i + 1] end
        end

        if data_format == MemoryEditor.DataFormat_Bin then
            return FormatBinary(le, size * 8)
        end

        local DT, dec = ImGuiDataType, data_format == MemoryEditor.DataFormat_Dec
        if data_type == DT.S8 or data_type == DT.U8 then
            if dec then return data_type == DT.S8 and SignedDec(le, 1) or UnsignedDec(le, 1) end
            return "0x" .. HexBytes(le, 1)
        elseif data_type == DT.S16 or data_type == DT.U16 then
            if dec then return data_type == DT.S16 and SignedDec(le, 2) or UnsignedDec(le, 2) end
            return "0x" .. HexBytes(le, 2)
        elseif data_type == DT.S32 or data_type == DT.U32 then
            if dec then return data_type == DT.S32 and SignedDec(le, 4) or UnsignedDec(le, 4) end
            return "0x" .. HexBytes(le, 4)
        elseif data_type == DT.S64 or data_type == DT.U64 then
            if dec then return data_type == DT.S64 and SignedDec(le, 8) or UnsignedDec(le, 8) end
            return "0x" .. HexBytes(le, 8)
        elseif data_type == DT.Float or data_type == DT.Double then
            local v, sign = DecodeFloat(le, data_type == DT.Double)
            if dec then
                if v ~= v then return sign and "-nan" or "nan" end
                if v == math.huge then return "inf" elseif v == -math.huge then return "-inf" end
                return format("%f", v)
            end
            return FormatHexFloat(v, sign)
        end
        error("MemoryEditor: unsupported data type") -- Shouldn't reach
    end

    return MemoryEditor
end
