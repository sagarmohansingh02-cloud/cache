# Privacy & Terms

Cache is a clipboard manager. It sees everything you copy, so the burden is on it
to be explicit about what happens to that. This document is that statement.

---

## The short version

- **Passwords are never saved.**
- **Everything stays on your Mac.** No server, no account, no sync.
- **No network access at all.** Cache makes no requests of any kind.
- **No keystroke monitoring.** It does not watch you type.
- **You can delete all of it**, at any time, permanently.

---

## Passwords are never saved

Password managers mark what they put on the clipboard as *concealed*, using the
pasteboard types `org.nspasteboard.ConcealedType` and
`org.nspasteboard.TransientType`.

Cache checks for those markers **before reading a single byte of content**. If
either is present the item is skipped entirely and never touches the database.
1Password, Bitwarden, Keychain, Dashlane and anything else that follows the
convention are all covered.

This check has been in the app since its first commit, and it is verified by
test: a clipboard item marked concealed produces no database row and no trace in
the store files.

**The honest limitation:** this relies on the source app marking the item. If you
manually select a password out of a plain text file and copy it, nothing marks it
as secret and Cache cannot know. Use **Settings → Rules** to ignore specific apps
or content types, or **Pause capture**, if you handle secrets that way.

---

## Everything is local

| What | Where |
|---|---|
| Clipboard history | `~/Library/Application Support/com.sagarmohansingh.supaclip/` |
| Images and screenshots | `.../Clips/` in that same folder |
| Settings | macOS user defaults |

That is the complete list. Nothing is uploaded, backed up to a service, or shared
between machines. There is no account to create and no telemetry.

To remove everything: **Settings → Clear all clips**, or delete the folder above.

---

## No network access

Cache makes no network requests. It has no analytics, no crash reporting, no
update check, and no remote configuration. You can verify this — run it behind
Little Snitch or check with `nettop`, and you will see nothing.

Text recognition on screenshots runs entirely on-device using Apple's Vision
framework. Images are never uploaded anywhere.

---

## No keystroke monitoring

Clipboard history comes from polling the system pasteboard's change counter,
which is unprivileged and tells us nothing about what you type. Cache does not
request Accessibility or Input Monitoring permission, and does not need them.

---

## Permissions

Cache requests nothing at launch. See [PERMISSIONS.md](PERMISSIONS.md) for the
full detail. In short:

- **Desktop / screenshot folder** — only if you turn *Save screenshots* on
- **Notifications** — only if you set a reminder on a clip

Both are optional. The app is fully usable without granting either.

---

## Terms

Cache is provided free and as-is, under the MIT licence. There is no warranty. It
is a local utility that stores data on your machine, and you are responsible for
that data the same way you are responsible for any other file on your Mac.

Because everything is local, there is no data controller, no processor, and
nothing to make a subject access request against. Your clipboard history is a
file on your disk.

If you find a security problem, please open an issue.
