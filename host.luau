--!strict
-- gpg-touch: when a command that signs with your key starts, show a toast
-- (and optionally play a sound). Rules in config.json decide where.

local match = require("./match")

local CONFIG = tern.plugin.data .. "/config.json"
local BASE = match.defaults(tern.runtime.os)
local HOME = tern.getenv("HOME")

-- Write a starting config on first load, so there is a file to edit.
if not tern.fs.exists(CONFIG) then
	if not tern.fs.exists(tern.plugin.data) then
		tern.fs.mkdir(tern.plugin.data)
	end
	tern.fs.write(CONFIG, string.format(
		'{\n  "default": { "toast": true, "sound": false },\n  "rules": [],\n  "sound": %s,\n  "aliases": []\n}\n',
		tern.json.encode(BASE.sound)
	))
end

-- Read on every command, so edits apply without a reload. A problem is
-- toasted once, not on every command.
local last_problem: string? = nil
local function load(cx: EffectCx): match.Config
	local ok, raw = pcall(function()
		return tern.json.decode(tern.fs.read(CONFIG, 65536))
	end)
	local cfg, problem
	if ok then
		cfg, problem = match.normalize(raw, BASE)
	else
		cfg, problem = BASE, "can't read config.json: " .. tostring(raw)
	end
	if problem and problem ~= last_problem then
		cx:toast("error", "GPG Touch: " .. problem, CONFIG)
	end
	last_problem = problem
	return cfg
end

-- Panes whose signing command we toasted, so a failure can be reported.
local pending: { [number]: boolean } = {}

tern.on("command_started", function(ev: CommandStartedEvent, cx: EffectCx)
	local cfg = load(cx)
	if not match.is_signing(ev.line, cfg.aliases) then
		return
	end
	local want = match.resolve(cfg, ev.cwd, HOME)
	if want.toast then
		cx:toast("info", "Touch your security key", ev.line)
		pending[ev.pane] = true
	end
	if want.sound and #cfg.sound > 0 then
		local ok, err = pcall(tern.process.run, cfg.sound, function(_result, _cx) end)
		if not ok then
			cx:toast("error", "GPG Touch: can't play the sound", tostring(err))
		end
	end
end)

tern.on("command_finished", function(ev: CommandFinishedEvent, cx: EffectCx)
	if not pending[ev.pane] then
		return
	end
	pending[ev.pane] = nil
	if ev.status ~= 0 then
		cx:toast("error", "Command failed — if it was signing, check your key", ev.line)
	end
end)
