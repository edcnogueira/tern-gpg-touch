# tern-gpg-touch

A [Tern](https://stencil.so/tern) plugin that reminds you to touch your security key (YubiKey, Nitrokey, SoloKey…) when a command that signs with it starts. With `commit.gpgsign = true`, every commit waits for that touch, and it is easy to sit there wondering why `git commit` hangs.

When you run a signing command in a Tern pane, a toast appears at the bottom of the window:

> ⓘ **Touch your security key** · `git commit -m "fix parser"`

If the command then fails, a second toast says so, in case the signature was the reason. Per folder, you can also turn on a sound or turn the reminder off.

## Install

```sh
tern plugin install github.com/edcnogueira/tern-gpg-touch
```

It has only a host half, so install it on the machine whose shells you want covered. For a remote host, run the same command in a pane on that host.

## What triggers it

A command line typed in a pane, after quoted text is ignored and `;`, `&`, `|`, `(`, `)` split it into commands, where a command is:

| Command | Triggers when |
| --- | --- |
| `git commit`, `merge`, `rebase`, `cherry-pick`, `revert`, `am` | Always, unless it has `--no-gpg-sign`, `--abort`, `--quit`, `--ff-only` or `--dry-run` |
| `git tag` | Only with `-s`, `--sign`, `-u` or `--local-user` |
| `gpg` | With `--sign`, `--clearsign`, `--clear-sign`, `--detach-sign`, `--decrypt`, or a short flag holding `s`, `b` or `d` (`-bsa`) |
| One of your `aliases` | Always, when it is the command's first word |

Options before the git subcommand (`git -C repo commit`), a path to git (`/usr/bin/git`) and leading `VAR=value` assignments are understood. Commands that may or may not sign, such as a `git merge` that ends up fast-forwarding, still trigger: the plugin can't know in advance.

## Configuration

The plugin writes `config.json` into its data folder on first load. It reads the file again for every command, so edits apply at once, with no reload.

| OS | File |
| --- | --- |
| macOS | `~/Library/Application Support/Tern/plugin-data/gpg-touch/config.json` |
| Other | `<Tern state dir>/plugin-data/gpg-touch/config.json` |

```json
{
  "default": { "toast": true, "sound": false },
  "rules": [
    { "path": "~/work", "sound": true },
    { "path": "~/work/sandbox", "toast": false }
  ],
  "sound": ["afplay", "/System/Library/Sounds/Funk.aiff"],
  "aliases": ["gc"]
}
```

| Key | Meaning |
| --- | --- |
| `default` | `toast` and `sound` used when `rules` is empty, and for any field a rule leaves out |
| `rules` | Empty: the reminder works everywhere. Not empty: it works **only** in folders inside a rule (the folder itself and everything below it). The rule with the longest `path` wins, so a deeper rule can override a broader one. `~/work` covers `~/work/api` but not `~/work-old` |
| `sound` | The command that plays the sound, as an argument list (no shell). Defaults: `afplay` on macOS, `paplay` on Linux, a PowerShell beep on Windows |
| `aliases` | Words that count as signing commands, for shell aliases such as `gc` |

A malformed file, or a rule without `path`, shows one error toast and falls back to the defaults for what it can't read.

## Limits

- **Only commands typed at a shell prompt.** The plugin listens to Tern's shell integration. Commands that a coding agent runs through its own tools (omp's bash tool, for example) don't pass through the prompt, so they don't trigger it. Use the agent's own hooks for those.
- **The folder is where the line started.** In `cd ~/other && git commit`, the rules see the folder you were in before `cd`.
- **The failure toast can't see why it failed.** Tern reports the exit status, not the error output, so "nothing to commit" also shows it.
- **A toast lasts about five seconds.** If you take longer to touch the key, the toast is gone while git still waits; the sound helps there.

## What it runs, reads and writes

- **Runs** only the `sound` command from your config, and only when a rule enables the sound.
- **Reads and writes** only its own `config.json`.
- **Network:** none.

## Development

```sh
git clone https://github.com/edcnogueira/tern-gpg-touch
cd tern-gpg-touch
tern plugin link .          # load it from this checkout; saving reloads it
tern plugin types .         # tern.d.luau for luau-lsp (git-ignored)
luau tests/match.test.luau  # tests for the matching and rule logic
```

`match.luau` holds the logic and doesn't use `tern`, so its tests run under the plain [`luau`](https://luau.org) CLI. `host.luau` wires it to Tern's `command_started` and `command_finished` hooks.

## License

[MIT](LICENSE)
