# ColonEmoji

Type `:` and an emoji name anywhere on your Mac (`:fire`, `:tada`), then pick from the popup. Works like the emoji picker in Slack, everywhere.

- ↑ / ↓ to choose, Return or Tab to insert, Esc to dismiss, or click a row
- Typing a full code with the closing colon (`:fire:`) converts instantly
- Emoji you use often float to the top
- Slang works too: `:lmao` → 😂 🤣 💀, `:idk` → 🤷, `:ty` → 🙏 (edit `Sources/ColonEmoji/Slang.swift`)
- Turn it off per app or per site from the `:)` menu (e.g. Slack, or `app.slack.com` in a browser)

## Install

1. Unzip `ColonEmoji.zip` and drag `ColonEmoji.app` into Applications.
2. Open it. macOS will block it because it isn't from the App Store or a registered developer.
   Go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway**.
3. When asked, allow **Accessibility** (System Settings → Privacy & Security → Accessibility → ColonEmoji on).
   It needs this to see what you type and to insert the emoji.
4. Click the `:)` in the menu bar and turn on **Launch at Login**.

If you also use Rocket, quit it, or both apps will react to `:`.

## Build from source

Needs the Xcode Command Line Tools (`xcode-select --install`).

```sh
./scripts/build_app.sh   # builds, installs to ~/Applications, writes dist/ColonEmoji.zip
```

Signing uses a keychain certificate named "ColonEmoji Local Signing" when one exists, so Accessibility
permission survives rebuilds. Without it the app is ad-hoc signed and permission must be re-granted after
each build.

Emoji data comes from `@emoji-mart/data` (MIT; see THIRD_PARTY_NOTICES.md). Regenerate it with
`python3 scripts/build_emoji_data.py <path to @emoji-mart/data/sets/15/native.json>`.
The icon is drawn by `swift scripts/render_icon.swift`.

## License

MIT. See LICENSE.
