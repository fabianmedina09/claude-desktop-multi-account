# Claude Desktop with multiple accounts on macOS

A guide and a script to run **two or more Claude Desktop accounts at the same time on a Mac**, each with:

- its own **name** (what you see in the Dock and the menu bar),
- its own **icon**, in a different colour,
- its own independent **session** (different email, different history).

> **Disclaimer:** community project, **unofficial** and not affiliated with Anthropic. "Claude" is a trademark of Anthropic. The script does not modify your original `Claude.app`: it works on a **copy** and signs it locally. Use it at your own risk and check Claude's terms of use.

---

## Contents

1. [Quick start](#quick-start)
2. [What each parameter means](#what-each-parameter-means)
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
./create-account.sh "Claude Work" Claude-Work yellow
```

It takes a couple of minutes. When it finishes you get `~/Applications/Claude Work.app`. Open it by double-clicking, then [sign in](#signing-in-to-the-second-account-read-this) with the other email.

## What each parameter means

```
./create-account.sh  "NAME"  PROFILE  COLOUR
```

| Parameter | What it is for | Example | If omitted |
|---|---|---|---|
| `NAME` | **Display name** of the app: what the Dock, the menu bar and the `.app` file show. | `"Claude Work"` | Required |
| `PROFILE` | **Folder where the session is stored** (cookies, login, history), at `~/Library/Application Support/<PROFILE>`. Two accounts = two different profiles. | `Claude-Work` | The name with dashes instead of spaces |
| `COLOUR` | **Icon colour.** Derived from the original Claude icon by shifting its hue. | `yellow` | `yellow` |

Do not mix up the name and the profile. **The name is only what you see. The profile is what separates the sessions:** if two apps share a profile, they share the account.

**Available colours:** `yellow`, `green`, `blue`, `purple`, `pink`, or a custom `ANGLE:EXPOSURE` in radians (for example `1.8:0.3`). **Yellow, green and blue** have been checked visually; purple and pink are untested hue calculations. If you do not like one, use the custom format.

Changing the colour means changing the **icon**: the angle is the hue shift (0 = unchanged orange) and the exposure lightens or darkens it. Yellow needs more exposure (0.75) because a yellow with the same brightness as the original orange looks dark mustard.

Other option: `DEST=/some/folder ./create-account.sh …` puts the app somewhere other than `~/Applications`.

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

**1. A different-coloured icon.** It extracts the original icon (`electron.icns`) and changes its hue and exposure with CoreImage, producing a new `.icns`.

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
rm -rf "$HOME/Library/Application Support/<PROFILE>"
```

**More than two accounts:** run the script again with another `NAME`, another `PROFILE` and another `COLOUR`. Each one is independent.

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
