#!/usr/bin/env bash
# Runs every tests/t_*.luau against the core (tools/core submodule) in the Roblox mock, the Roblox example,
# and (if nix-shell is available) the LÖVE checks under LuaJIT.
cd "$(dirname "$0")/.."
fail=0
run() { python3 tools/core/tools/test/run.py --module MemoryEditor=MemoryEditor.lua --roblox "$@" 2>&1; }
for t in tests/t_*.luau; do
    out=$(run --main "$t" --quiet)
    if echo "$out" | grep -q "^OK"; then echo "PASS $t"; else echo "FAIL $t"; echo "$out" | tail -20; fail=1; fi
done
# example LocalScript: 400 frames of random input (mock drives Stepped, not RenderStepped)
ex=$(mktemp --suffix=.luau); sed 's/RenderStepped/Stepped/' examples/roblox/main.client.luau > "$ex"
out=$(run --main "$ex")
rm -f "$ex"
if echo "$out" | grep -q "^avg frame"; then echo "PASS example"; else echo "FAIL example"; echo "$out" | tail -20; fail=1; fi
if command -v nix-shell >/dev/null; then
    out=$(nix-shell -p luajit --run "luajit tests/love.lua" 2>&1)
    if echo "$out" | grep -q "^OK"; then echo "PASS love"; else echo "FAIL love"; echo "$out" | tail -20; fail=1; fi
fi
exit $fail
