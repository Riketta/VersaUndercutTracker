-- luacheck: globals assert
-- Minimal busted-compatible harness shim so the specs run with any plain
-- Lua 5.1 interpreter without native rocks. CI runs real busted; this exists
-- for quick local verification.
--
-- Busted parity: spec files are only LOADED first (collection phase), tests
-- run after ALL files are loaded with _G shared across files; use
-- before_each/after_each for stubs.
--
-- Usage: lua scripts/run_tests.lua spec/*_spec.lua

local passed, failures = 0, 0

package.path = "./?.lua;./?/init.lua;" .. package.path

if not arg or #arg == 0 then
    io.stderr:write("usage: lua scripts/run_tests.lua <spec file> [...]")
    os.exit(1)
end

local hookStack = { { before = {}, after = {} } }
local queue = {}

function describe(name, fn)
    print(name)
    local frame = { before = {}, after = {} }
    hookStack[#hookStack + 1] = frame
    fn()
    hookStack[#hookStack] = nil
end

function before_each(fn)
    hookStack[#hookStack].before[#hookStack[#hookStack].before + 1] = fn
end

function after_each(fn)
    hookStack[#hookStack].after[#hookStack[#hookStack].after + 1] = fn
end

function it(name, fn)
    local chain = {}
    for i = 1, #hookStack do
        chain[i] = hookStack[i]
    end
    queue[#queue + 1] = { name = name, fn = fn, chain = chain }
end

local shim = {}

function shim.equals(actual, expected)
    if actual ~= expected then
        error(("expected %s, got %s"):format(tostring(expected), tostring(actual)), 2)
    end
end

function shim.is_true(value)
    if value ~= true then
        error("expected true, got " .. tostring(value), 2)
    end
end

function shim.is_false(value)
    if value ~= false then
        error("expected false, got " .. tostring(value), 2)
    end
end

function shim.is_nil(value)
    if value ~= nil then
        error("expected nil, got " .. tostring(value), 2)
    end
end

function shim.is_not_nil(value)
    if value == nil then
        error("expected a value other than nil, got nil", 2)
    end
end

function shim.not_equals(actual, expected)
    if actual == expected then
        error(("expected any value but %s"):format(tostring(actual)), 2)
    end
end

assert = setmetatable({}, {
    __call = function(_, value, message)
        if not value then
            error(message or "assertion failed", 2)
        end
        return value
    end,
    __index = shim,
})

for _, path in ipairs(arg) do
    local chunk, err = loadfile(path)
    if not chunk then
        failures = failures + 1
        print("[FAIL] loading " .. path .. " -> " .. tostring(err))
    else
        chunk()
    end
end

for _, case in ipairs(queue) do
    local ok, err = pcall(function()
        for i = 1, #case.chain do
            for _, hook in ipairs(case.chain[i].before) do
                hook()
            end
        end
        case.fn()
        for i = #case.chain, 1, -1 do
            for _, hook in ipairs(case.chain[i].after) do
                hook()
            end
        end
    end)
    if ok then
        passed = passed + 1
        print("  [ok]   " .. case.name)
    else
        failures = failures + 1
        print("  [FAIL] " .. case.name .. " -> " .. tostring(err))
    end
end

print(("\n%d passed, %d failed"):format(passed, failures))
os.exit(failures > 0 and 1 or 0)
