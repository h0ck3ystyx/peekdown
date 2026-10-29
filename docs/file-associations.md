# Markdown file associations

Peekdown provides Quick Look previews and thumbnails. The host app is a setup
screen, so its Markdown document role and handler rank are both `None`.
It imports `net.daringfireball.markdown` instead of claiming ownership of the type.
The preview and thumbnail extensions continue to accept this identifier and
`public.markdown`.

This follows Apple's guidance for [using an existing type identifier](https://developer.apple.com/documentation/uniformtypeidentifiers/defining-file-and-data-types-for-your-app)
and its [handler rank definitions](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CoreFoundationKeys.html).

## Local regression check

Run `./build.sh`, then `./scripts/test-file-associations.sh` in a logged-in macOS
session. The check registers an isolated host-app copy with a unique identifier,
compares the current opener for each supported extension before and after registration, unregisters the
copy, and compares again. It never sets a default application or registers the
copied extensions. This tests Launch Services behavior rather than a complete
signed installer/uninstaller or Finder extension selection.

## Finder acceptance checks

On a test Mac with another Markdown editor (such as Xcode, VS Code, or Obsidian):

1. Choose that editor as the default for `.md` using Get Info → Open with →
   Change All. Record the existing default for the other supported extensions
   (`.markdown`, `.mdown`, `.mkd`, `.mkdn`) as well.
2. Install the signed Peekdown release into `~/Applications`. Confirm double-click
   still opens the selected editor and Finder's Open with menu retains it.
3. Press Space on representative files. Confirm Peekdown renders the preview and
   Finder thumbnails still appear.
4. Repeat with another Markdown Quick Look extension installed. Record which
   provider macOS selects; Peekdown does not force priority over other providers.
5. Remove Peekdown and verify the recorded editor choices remain. Repeat with an
   all-users installation on a test account that can authorize it.

An older Peekdown installation may already have become the default editor. A
metadata update does not restore a previous choice automatically; use Get Info →
Open with → your preferred editor → Change All. Peekdown does not rewrite the
user's Launch Services preferences during installation or removal.

## Verification recorded on October 29, 2026

The universal build and strict signatures passed with imported type declarations.
The isolated registration/removal check preserved all five current default openers.
This Mac has Xcode, VS Code, and Obsidian installed, but its existing Markdown
associations point to the older installed Peekdown for `.md`/`.markdown` and
Cursor for `.mdown`/`.mkd`/`.mkdn`. No user defaults were
changed by this check. No competing third-party Markdown Quick Look provider was
registered, so the competing-provider and signed-install/removal acceptance matrix
above remains a manual release check.
