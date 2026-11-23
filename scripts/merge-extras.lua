-- Keeps languages the person enabled when an update replaces lazyvim.json.
-- Usage: nvim --clean -l merge-extras.lua <old lazyvim.json> <new lazyvim.json>
local function read(path)
  local fd = assert(io.open(path, "r"))
  local data = vim.json.decode(fd:read("*a"))
  fd:close()
  return data
end

local old, new = read(arg[1]), read(arg[2])
local seen = {}
for _, extra in ipairs(new.extras or {}) do
  seen[extra] = true
end
new.extras = new.extras or {}
for _, extra in ipairs(old.extras or {}) do
  if not seen[extra] then
    table.insert(new.extras, extra)
  end
end
table.sort(new.extras)

local fd = assert(io.open(arg[2], "w"))
fd:write(vim.json.encode(new), "\n")
fd:close()
