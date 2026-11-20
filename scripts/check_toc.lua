-- CI guard, two directions:
--   1. every Lua file in the addon folder must be listed in the TOC;
--   2. every .lua file listed in the TOC must exist on disk.
-- The directory walk uses io.popen with `find` (Unix) and falls back to
-- `cmd /c dir /s /b` (Windows); on a platform without either, direction 1
-- is a silent no-op and only direction 2 guards (CI runs Linux).

local tocPath = assert(arg and arg[1], "usage: lua scripts/check_toc.lua <Addon.toc>")
local srcRoot = (arg and arg[2]) or "."

local file = assert(io.open(tocPath, "r"), "cannot open TOC: " .. tocPath)
local listed = {}
local tocEntries = {}
for line in file:lines() do
    local entry = line:match("^(%S+%.lua)%s*$")
    if entry then
        listed[entry:gsub("/", "\\")] = true
        listed[entry] = true
        tocEntries[#tocEntries + 1] = entry
    end
end
file:close()

local missing = {}
local walked = {}
local handles = {
    io.popen(("find %s -name \"*.lua\" 2>/dev/null"):format(srcRoot)),
}
for _, handle in ipairs(handles) do
    if handle then
        for path in handle:lines() do
            path = path:gsub("^%./", ""):gsub("\\", "/")
            walked[#walked + 1] = path
            if not listed[path] and not listed[path:gsub("/", "\\")] then
                missing[#missing + 1] = path
            end
        end
        handle:close()
    end
end
if #walked == 0 then
    local handle = io.popen(("cmd /c \"dir /s /b \"%s\\*.lua\"\""):format(srcRoot))
    if handle then
        for path in handle:lines() do
            path = path:gsub("\r", ""):gsub("\\", "/")
            local rel = path:match(srcRoot:gsub("\\", "/") .. "/(.+)$")
            if rel then
                if not listed[rel] then
                    missing[#missing + 1] = rel
                end
            end
        end
        handle:close()
    end
end

if #missing > 0 then
    io.stderr:write("lua files present under " .. srcRoot .. " but missing from the TOC:\n")
    for _, path in ipairs(missing) do
        io.stderr:write("  " .. path .. "\n")
    end
    os.exit(1)
end

local tocDir = tocPath:match("^(.*)[/\\][^/\\]+$") or "."
local absent = {}
for _, entry in ipairs(tocEntries) do
    local handle = io.open(tocDir .. "/" .. entry, "r")
    if handle then
        handle:close()
    else
        absent[#absent + 1] = entry
    end
end

if #absent > 0 then
    io.stderr:write("files listed in " .. tocPath .. " but missing on disk:\n")
    for _, path in ipairs(absent) do
        io.stderr:write("  " .. path .. "\n")
    end
    os.exit(1)
end

print(("toc coverage ok: %d lua files, every TOC entry exists"):format(#tocEntries))
