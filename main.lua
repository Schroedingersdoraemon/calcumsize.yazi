--- @since 26.9.1
--- @sync entry
---
--- Show the cumulative size of files/directories in the linemode column on demand
--- (`d c`), using `fs.calc_size()` — the same chunked walker behind `spot`.
---
--- Installation is just: clone into ~/.config/yazi/plugins and bind
--- `{ on = [ "d", "c" ], run = "plugin calcumsize" }`. No init.lua, no setup call:
--- the first `d c` installs the `calcumsize` linemode through the `lua` action,
--- switches to it, and measures the marked entries (or the hovered one). Results are
--- written into the folder's `entries.sizes` exactly like `spot`, so they stay
--- attached to their rows while the cursor moves and survive until Yazi exits.
---
--- The column renders `File:size()` only: files show their size, directories show
--- their measured cumulative size, and anything not measured stays blank — it never
--- falls back to the entry count.

local M = {}

--- Installed into Yazi's UI Lua state via `app:lua` when the plugin runs.
local RENDER = [[
Linemode.calcumsize = function(self)
	local f = self._file
	if not f.in_current then
		return ""
	end

	local size = f:size()
	return size and ya.readable_size(size) or ""
end
]]

--- URL + kind of every entry this invocation should measure.
local get_targets = ya.sync(function()
	local out = {}

	for _, f in pairs(cx.active.selected) do
		local st = f.stat or f.cha
		out[#out + 1] = { url = f.url, dir = st and st.is_dir or false }
	end

	if #out == 0 then
		local h = cx.active.current.hovered
		if h then
			local st = h.stat or h.cha
			out[1] = { url = h.url, dir = st and st.is_dir or false }
		end
	end

	return out
end)

--- Hand a finished size to the folder, then repaint the list.
local function commit(url, size)
	ya.emit("update_files", {
		op = fs.op("size", { url = url.trail, sizes = { [url.key] = size } }),
	})
	ui.render()
	ya.emit("watch", {})
end

local function measure(url)
	local it = fs.calc_size(url)
	if not it then
		return nil
	end

	local size = 0
	while true do
		local n, err = it:recv()
		if err then
			return nil
		elseif not n then
			return size
		end
		size = size + n
	end
end

function M:entry()
	-- Register the linemode in the UI Lua state, then switch to it.
	ya.emit("lua", { code = RENDER })
	ya.emit("linemode", { new = "calcumsize" })

	local targets = get_targets()

	ya.async(function()
		for _, t in ipairs(targets) do
			-- Files already carry their own size, only directories are walked.
			if t.dir then
				local size = measure(t.url)
				if size then
					commit(t.url, size)
				end
			end
		end
	end)
end

--- Optional: for users who prefer `require("calcumsize"):setup()` in init.lua.
function M:setup() assert(load(RENDER))() end

return M
