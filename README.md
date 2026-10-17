# imgui-memory-editor-luau

Hex/memory editor widget for imgui-luau: view and edit a Roblox `buffer`, a LÖVE `ByteData` or a table of bytes.

Luau port of [imgui_memory_editor](https://github.com/ocornut/imgui_club) (imgui_club, v0.59) for [imgui-luau](https://git.bug.tools/bug/imgui-luau) ([GitHub](https://github.com/4DBug/imgui-luau)).
Mirrors: [git.bug.tools](https://git.bug.tools/bug/imgui-memory-editor-luau) / [GitHub](https://github.com/4DBug/imgui-memory-editor-luau).

## Usage

```lua
local G = require(ReplicatedStorage.ImGui)
local MemoryEditor = require(ReplicatedStorage.MemoryEditor)(G)

local data = buffer.create(0x10000)
local mem_edit = MemoryEditor.new()            -- C++: static MemoryEditor mem_edit;

-- each frame:
mem_edit:DrawWindow("Memory Editor", data)     -- size defaults to the data's length
-- or inside your own window:
mem_edit:DrawContents(data, 0x100, 0x8000)     -- mem_size, base_display_addr
```

The API is upstream's: same fields (`Cols`, `ReadOnly`, `OptShowDataPreview`, `OptShowAscii`, `OptMidColsCount`,
`HighlightColor`, `MouseHovered`, `MouseHoveredAddr`, ...), `GotoAddrAndHighlight(min, max)`, and the handlers
`ReadFn(mem, off, user_data)`, `WriteFn(mem, off, d, user_data)`, `HighlightFn(mem, off, user_data)`,
`BgColorFn(mem, off, user_data)` with `UserData`. Offsets and addresses are 0-based like upstream; "none" (C++ `(size_t)-1`) is `-1`.

`[Port]` differences:
- `mem_data` (C++ `void*`) is any of: Roblox `buffer`; LÖVE `Data` (`ByteData`, `ImageData`, ...; writable through
  `getFFIPointer()`, read-only via `getString()` without FFI); a Lua table of bytes (index 1 = offset 0); a string (read-only).
  `mem_size` is optional and defaults to the data's length.
- `DrawPreviewData` returns the string instead of writing into `out_buf`. 64-bit values are decoded exactly from the
  bytes (Lua numbers stop at 2^53); `%a` is formatted like glibc.

On LÖVE, load the file with `loadfile("MemoryEditor.lua")()(G)` (plain Lua 5.1 syntax). Examples:
`examples/roblox/main.client.luau`, `examples/love` (`love examples/love`).

## Development

```sh
git clone --recursive https://git.bug.tools/bug/imgui-memory-editor-luau.git
bash tools/test.sh   # tests/t_*.luau in the core's Roblox mock, the Roblox example, and tests/love.lua under LuaJIT (nix-shell)
```

Upstream source (pinned) is in `tools/upstream/`; port-specific comments are tagged `[Port]`.

## License

MIT, see LICENSE (upstream copyright kept).
