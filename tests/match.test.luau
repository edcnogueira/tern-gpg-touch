local match = require("../match")

local failures = 0
local function check(name: string, got: any, want: any)
	if got ~= want then
		failures += 1
		print(string.format("FAIL %s: got %s, want %s", name, tostring(got), tostring(want)))
	end
end

local signs = {
	"git commit -m x",
	"git -C repo commit --amend",
	"git add . && git commit -m x",
	"/usr/bin/git merge main",
	"GIT_EDITOR=true git rebase --continue",
	"git tag -s v1",
	"git tag --local-user=ABC v1",
	"gpg --clearsign notes.txt",
	"gpg -bsa notes.txt",
}
for _, line in signs do
	check(line, match.is_signing(line, {}), true)
end

local quiet = {
	"git status",
	"git log --grep commit",
	"git pull",
	"git tag",
	"git tag -l",
	"git commit --no-gpg-sign -m x",
	"git rebase --abort",
	"git merge --ff-only main",
	'echo "git commit"',
	"gpg --list-keys",
	"rg commit",
}
for _, line in quiet do
	check(line, match.is_signing(line, {}), false)
end

check("alias", match.is_signing("gc -m x", { "gc" }), true)
check("alias is a whole word", match.is_signing("gcc main.c", { "gc" }), false)

local cfg: match.Config = {
	default = { toast = true, sound = false },
	rules = {
		{ path = "~/setare", toast = true, sound = true },
		{ path = "~/kodacoda", toast = false, sound = false },
		{ path = "~/setare/legacy", sound = false },
	},
	sound = {},
	aliases = {},
}
local function at(cwd: string?): match.Settings
	return match.resolve(cfg, cwd, "/Users/me")
end

check("inside a rule", at("/Users/me/setare/api").sound, true)
check("the rule's own folder", at("/Users/me/setare").sound, true)
check("sibling folder is not inside", at("/Users/me/setare-old").toast, false)
check("rule turns toast off", at("/Users/me/kodacoda/web").toast, false)
check("longest rule wins", at("/Users/me/setare/legacy/x").sound, false)
check("missing field comes from default", at("/Users/me/setare/legacy/x").toast, true)
check("outside every rule stays quiet", at("/tmp").toast, false)
check("unknown cwd stays quiet when rules exist", at(nil).toast, false)

local open: match.Config = { default = { toast = true, sound = false }, rules = {}, sound = {}, aliases = {} }
check("no rules: default everywhere", match.resolve(open, "/tmp", "/Users/me").toast, true)
check("no rules, unknown cwd: default", match.resolve(open, nil, "/Users/me").toast, true)

local _, problem = match.normalize({ rules = { { toast = false } } }, cfg)
check("rule without path is reported", problem ~= nil, true)

if failures > 0 then
	error(failures .. " test(s) failed")
end
print("all tests passed")
