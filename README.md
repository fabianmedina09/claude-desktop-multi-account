# Claude Desktop with multiple accounts on macOS

A guide and a script to run **two or more Claude Desktop accounts at the same time on a Mac**, each with:

- its own **name** (what you see in the Dock and the menu bar),
- its own **icon**, in a different colour,
- its own independent **session** (different email, different history).

> **Disclaimer:** community project, **unofficial** and not affiliated with Anthropic. "Claude" is a trademark of Anthropic. The script does not modify your original `Claude.app`: it works on a **copy** and signs it locally. Use it at your own risk and check Claude's terms of use.

---

## Contents

1. [Quick start](#quick-start)
2. [Usage and colours](#usage)
3. [Signing in to the second account (read this)](#signing-in-to-the-second-account-read-this)
4. [Opening the app later](#opening-the-app-later)
5. [Step by step: what the script does](#step-by-step-what-the-script-does)
6. [Why a single command is not enough](#why-a-single-command-is-not-enough)
7. [Updating, removing, more accounts](#updating-removing-more-accounts)
8. [Troubleshooting](#troubleshooting)

---

## Quick start

**Requirements**

- macOS with [Claude Desktop](https://claude.ai/download) installed at `/Applications/Claude.app`.
- Xcode Command Line Tools (for `swiftc` and `clang`): `xcode-select --install`.
- About 700 MB of free disk per account (the app copy is ~656 MB).

**Create the account**

```bash
git clone https://github.com/fabianmedina09/claude-desktop-multi-account.git
cd claude-desktop-multi-account
./create-account.sh "Claude Work"
```

That is all you need: just the name. It takes a couple of minutes. When it finishes you get `~/Applications/Claude Work.app`. Open it by double-clicking, then [sign in](#signing-in-to-the-second-account-read-this) with the other email.

## Usage

```
./create-account.sh  "NAME"  [COLOUR]
```

| Parameter | What it is for | If omitted |
|---|---|---|
| `NAME` | **Display name** of the app: what the Dock, the menu bar and the `.app` file show. | Required |
| `COLOUR` | **Icon colour** (optional). A name or any hex colour. | A colour is generated from the name |

### Colour examples

```bash
# 1. No colour: one is picked for you from the name (same name = same colour, always)
./create-account.sh "Claude Work"

# 2. A named colour: yellow, green, blue, purple, pink, red, teal
./create-account.sh "Claude Work" yellow

# 3. Any hex colour, 6 digits...
./create-account.sh "Claude Work" "#7C3AED"

# 4. ...or 3 digits, with or without the "#"
./create-account.sh "Claude Work" "#0af"
./create-account.sh "Claude Work" 0af
```

> Quote hex colours that start with `#` (`"#7C3AED"`), because the shell treats an unquoted `#` as a comment.

| You pass | You get |
|---|---|
| *(nothing)* | An automatic colour, always different from Claude's original orange |
| `yellow` `green` `blue` `purple` `pink` `red` `teal` | A ready-made colour |
| `"#F4B000"` | That exact colour (amber) |
| `"#1E3A8A"` | Dark navy (the white star stays white) |
| `"#7C3AED"` | Violet |
| `"#0af"` | Same as `#00AAFF` |

Only the orange background is recoloured: the white star, its glow and the shadow are left untouched, so any colour looks right, light or dark.

### Where the session lives (no parameter needed)

Each account keeps its own login in a folder derived from the name:

| Name | Session folder |
|---|---|
| `"Claude Work"` | `~/Library/Application Support/Claude-Work` |
| `"Claude Personal"` | `~/Library/Application Support/Claude-Personal` |

The name is only what you see; **the folder is what separates the sessions**. Two apps that shared a folder would share the account, so each name gets its own. You never have to type it.

Two optional environment variables, only if you need them:

```bash
# Put the app somewhere else (default: ~/Applications)
DEST=/Applications ./create-account.sh "Claude Work"

# Reuse an existing session folder (for example, one made with an older version of this script)
PROFILE=Claude-Old-Name ./create-account.sh "Claude Work"
```

The name `Claude` itself is rejected, because that is the main app's own session folder.

## Signing in to the second account (read this)

> **The second account does not let you sign in with Google.**
>
> When you click "Continue with Google", the browser tries to **open Claude** (through a `claude://…` link) and macOS hands it to **the main session**, the one that was already open, not to the second one. You end up in the original account instead of the new one.

**What works: sign in with email and a code**

1. In the second app's window, choose **continue with email** and type the email of the second account.
2. Claude sends a **code** to that email.
3. Open the email, **copy the code** from the browser/mail, and paste it into the app. (If the email also includes a link, do not use it: use the code.)
4. **At no point tell the browser to open Claude.** If a prompt like "Open Claude?" appears, cancel or close it. That prompt is exactly what sends the login to the main session.
5. Paste the code in the app. Once you do, authentication is complete.

You only do this once. The session is stored in the profile, so next time the app opens already signed in.

## Opening the app later

The app lives in `~/Applications` (or wherever you set `DEST`). If it is not in your Dock, you can open it with:

- **Spotlight:** `Cmd+Space`, then type the app's name.
- **Finder:** *Go → Go to Folder…* → `~/Applications`.
- **Terminal:** `open ~/Applications/"Claude Work.app"`.

To keep it in the Dock: open it, right-click its Dock icon → *Options* → *Keep in Dock*. The script also prints these hints when it finishes.

The app should also appear in the **Apps / Launchpad** view. That needs the launcher to have a bundle identifier, which the script sets (`local.multiaccount.<name>`). If you built an app with an older version of the script and it is missing there, re-run the script.

## Step by step: what the script does

`create-account.sh` does five things. If you want to understand it or do it by hand, here is each one and why it exists.

**1. A different-coloured icon.** It extracts the original icon (`electron.icns`), measures the colour of its orange background, and recolours only the saturated pixels to your target colour (hue, saturation and brightness), leaving the white star untouched. It produces a new `.icns`.

**2. A launcher.** It creates `~/Applications/<NAME>.app`, a tiny launcher (compiled AppleScript, via `osacompile`) with the same icon. This is what you double-click. It also gets its own bundle identifier so it shows up in the Apps view.

**3. A copy of Claude with its own identity.** It copies `/Applications/Claude.app` inside the launcher (`Contents/Resources/<NAME>.app`) and changes:

- the icon (`electron.icns`),
- `CFBundleIdentifier` → `com.anthropic.claudefordesktop.<name>` (so macOS treats it as a different app),
- `CFBundleDisplayName` → the display name,
- and it **deletes `CFBundleIconName`** from `Info.plist` (otherwise the Dock keeps showing the original icon, because it reads it from the `Assets.car` catalogue).

**4. A pinned profile.** It replaces the main executable with a tiny C launcher that runs the real binary (`Claude-bin`) **always** with `--user-data-dir=~/Library/Application Support/<PROFILE>`. This way, even if you open the copy from its Dock icon, it goes to its own profile and not the main one.

**5. Signing and refresh.** It signs the copy locally (`codesign --sign -`), registers it with Launch Services, and restarts the Dock so the new icon shows up.

Final structure:

```
~/Applications/<NAME>.app              ← launcher (what you open)
└── Contents/Resources/<NAME>.app      ← copy of Claude with its own identity
    └── Contents/MacOS/Claude          ← C launcher that pins the profile
        Contents/MacOS/Claude-bin      ← the real Claude binary
```

## Why a single command is not enough

The simplest approach is a launcher that runs:

```bash
open -n -a "Claude" --args --user-data-dir="$HOME/Library/Application Support/Claude-Work"
```

That **does open a second instance with a different session**, and it is enough if that is all you need. But it has limits:

- **It looks identical to the main one.** The Dock shows the program that is running (`Claude.app`), not the launcher. Both show "Claude" and the orange icon.
- **If you open it from the Dock** (because you pinned it), macOS launches the app without the profile argument and you land in the main session.
- **If you open the main app while the other is running**, macOS sometimes brings the existing window to the front, because both are "the same app".

That is why the script uses a copy with its own identifier and pins the profile inside the copy.

Things that were hard to discover (in case you do it by hand):

- Electron finds its helper processes (`Claude Helper.app`, etc.) using **`CFBundleName`**. If you change it, the app fails with `Unable to find helper app`. Leave it as `Claude` and change only `CFBundleDisplayName`.
- The main executable must be a real binary (Mach-O), not a shell script.
- You must **remove `CFBundleIconName`** for the Dock to respect your `.icns`.
- After touching the bundle you must sign it again. A stray file inside the `.app` breaks the signature (`unsealed contents present in the bundle root`).
- A launcher without a `CFBundleIdentifier` works, but does not show up in the Apps view / Launchpad.

## Updating, removing, more accounts

**When Claude Desktop updates**, the copy does **not** update itself. Run the same command again: it rebuilds the app and **keeps your session** (it lives in the profile, outside the app).

**Remove an account:** drag `~/Applications/<NAME>.app` to the Trash. To delete the session too:

```bash
rm -rf "$HOME/Library/Application Support/Claude-Work"   # for an app called "Claude Work"
```

**More than two accounts:** run the script again with another name (and, if you like, another colour). Each one is independent.

## Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| Signing in opens the main account | You used Google / let the browser open Claude | [Sign in with email and code](#signing-in-to-the-second-account-read-this) |
| The Dock shows the old icon or name | macOS cache | Quit the app, run `killall Dock`, open it again |
| App is not in Apps / Launchpad | Launcher has no bundle identifier (older script) | Re-run the script |
| `Unable to find helper app` | `CFBundleName` was changed | Keep it as `Claude` |
| Will not start, "incorrect executable format" | Broken signature or non-binary executable | Re-run the script |
| `swiftc` or `clang` not found | No Xcode Command Line Tools | `xcode-select --install` |
| App stopped working after a Claude update | The copy is out of date | Re-run the script |

## License

MIT. See [LICENSE](LICENSE).
