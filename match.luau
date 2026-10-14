--!strict
-- Pure logic for gpg-touch: which command lines sign with your key, and which
-- rule applies to a directory. It doesn't use `tern`, so tests run under the
-- plain `luau` CLI.

local M = {}

export type Settings = { toast: boolean, sound: boolean }
export type Rule = { path: string, toast: boolean?, sound: boolean? }
export type Config = {
	default: Settings,
	rules: { Rule },
	sound: { string },
	aliases: { string },
}

-- git subcommands that create commits or tags, and so sign under commit.gpgsign.
local SIGNING: { [string]: boolean } = {
	commit = true,
	tag = true,
	merge = true,
	rebase = true,
	["cherry-pick"] = true,
	revert = true,
	am = true,
}

-- git options whose value is the next word, as in `git -C repo commit`.
local GIT_VALUE_OPTS: { [string]: boolean } = {
	["-C"] = true,
	["-c"] = true,
	["--git-dir"] = true,
	["--work-tree"] = true,
	["--namespace"] = true,
}

-- Flags that mean nothing gets signed this time.
local NO_SIGN: { [string]: boolean } = {
	["--no-gpg-sign"] = true,
	["--abort"] = true,
	["--quit"] = true,
	["--ff-only"] = true,
	["--dry-run"] = true,
}

-- `git tag` only signs with one of these.
local TAG_SIGN: { [string]: boolean } = {
	["-s"] = true,
	["--sign"] = true,
	["-u"] = true,
	["--local-user"] = true,
}

-- gpg long options that use the secret key.
local GPG_LONG: { [string]: boolean } = {
	["--sign"] = true,
	["--clearsign"] = true,
	["--clear-sign"] = true,
	["--detach-sign"] = true,
	["--decrypt"] = true,
}

local function git_signs(words: { string }, from: number): boolean
	local i = from
	while i <= #words and string.sub(words[i], 1, 1) == "-" do
		i += if GIT_VALUE_OPTS[words[i]] then 2 else 1
	end
	local sub = words[i]
	if not sub or not SIGNING[sub] then
		return false
	end
	local tag_signed = false
	for j = i + 1, #words do
		local w = words[j]
		if NO_SIGN[w] then
			return false
		end
		if TAG_SIGN[w] or string.sub(w, 1, 13) == "--local-user=" then
			tag_signed = true
		end
	end
	return sub ~= "tag" or tag_signed
end

local function gpg_signs(words: { string }, from: number): boolean
	for i = from, #words do
		local w = words[i]
		if GPG_LONG[w] then
			return true
		end
		-- Short flags, alone or combined: -s, -b, -d, -bsa.
		if string.match(w, "^%-[^-]") and string.find(w, "[sbd]") then
			return true
		end
	end
	return false
end

function M.is_signing(line: string, aliases: { string }): boolean
	-- Blank out quoted text so `echo "git commit"` and commit messages don't count.
	local text = string.gsub(line, '"[^"]*"', '""')
	text = string.gsub(text, "'[^']*'", "''")
	-- Each piece between ; & | ( ) is its own command.
	for segment in string.gmatch(text, "[^;&|()\n]+") do
		local words = {}
		for w in string.gmatch(segment, "%S+") do
			table.insert(words, w)
		end
		-- Skip leading VAR=value assignments.
		local first = 1
		while words[first] and string.match(words[first], "^[%a_][%w_]*=") do
			first += 1
		end
		local cmd = words[first]
		if cmd then
			local name = string.match(cmd, "[^/]+$") or cmd
			if name == "git" and git_signs(words, first + 1) then
				return true
			end
			if name == "gpg" and gpg_signs(words, first + 1) then
				return true
			end
			if table.find(aliases, cmd) then
				return true
			end
		end
	end
	return false
end

local function expand(path: string, home: string?): string
	if home and (path == "~" or string.sub(path, 1, 2) == "~/") then
		path = home .. string.sub(path, 2)
	end
	if #path > 1 and string.sub(path, -1) == "/" then
		path = string.sub(path, 1, -2)
	end
	return path
end

-- True when `dir` is `root` or below it: ~/setare matches ~/setare/api, not ~/setare-old.
local function inside(dir: string, root: string): boolean
	return root == "/" or dir == root or string.sub(dir, 1, #root + 1) == root .. "/"
end

-- With no rules, `default` applies everywhere. With rules, they are an
-- allowlist: only folders inside one warn, and the longest matching rule wins.
-- What a rule leaves out comes from `default`.
function M.resolve(config: Config, cwd: string?, home: string?): Settings
	local best: Rule? = nil
	local best_len = -1
	if cwd then
		local dir = expand(cwd, home)
		for _, rule in config.rules do
			local root = expand(rule.path, home)
			if #root > best_len and inside(dir, root) then
				best, best_len = rule, #root
			end
		end
	end
	local d = config.default
	if not best then
		if #config.rules > 0 then
			return { toast = false, sound = false }
		end
		return { toast = d.toast, sound = d.sound }
	end
	return {
		toast = if best.toast == nil then d.toast else best.toast,
		sound = if best.sound == nil then d.sound else best.sound,
	}
end

function M.defaults(os: string): Config
	local sound: { string } = if os == "macos"
		then { "afplay", "/System/Library/Sounds/Funk.aiff" }
		elseif os == "linux" then { "paplay", "/usr/share/sounds/freedesktop/stereo/bell.oga" }
		elseif os == "windows" then { "powershell", "-NoProfile", "-Command", "[console]::beep(880,200)" }
		else {}
	return { default = { toast = true, sound = false }, rules = {}, sound = sound, aliases = {} }
end

local function bool(v: any, fallback: boolean): boolean
	return if type(v) == "boolean" then v else fallback
end

local function strings(v: any): { string }?
	if type(v) ~= "table" then
		return nil
	end
	local out = {}
	for _, s in ipairs(v) do
		if type(s) ~= "string" then
			return nil
		end
		table.insert(out, s)
	end
	return out
end

-- Turns decoded JSON into a Config, falling back to `base` for anything
-- missing or malformed. Returns the first problem found, if any.
function M.normalize(raw: any, base: Config): (Config, string?)
	if type(raw) ~= "table" then
		return base, "config.json must hold a JSON object"
	end
	local d = if type(raw.default) == "table" then raw.default else {}
	local cfg: Config = {
		default = { toast = bool(d.toast, base.default.toast), sound = bool(d.sound, base.default.sound) },
		rules = {},
		sound = strings(raw.sound) or base.sound,
		aliases = strings(raw.aliases) or base.aliases,
	}
	local problem: string? = nil
	if type(raw.rules) == "table" then
		for i, r: any in ipairs(raw.rules) do
			if type(r) == "table" and type(r.path) == "string" and r.path ~= "" then
				table.insert(cfg.rules, {
					path = r.path,
					toast = if type(r.toast) == "boolean" then r.toast else nil,
					sound = if type(r.sound) == "boolean" then r.sound else nil,
				})
			elseif not problem then
				problem = string.format('rules[%d] needs a "path" string; skipped', i)
			end
		end
	end
	return cfg, problem
end

return M
