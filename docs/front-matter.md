# Optional front-matter metadata

Development feature for the next release after v1.1.1.

Open Peekdown and enable **Show front-matter metadata**, then close and reopen
Quick Look. The default remains off: front matter is hidden so the preview starts
with the document body. The setting is shared with the preview extension through
the existing App Group.

A front-matter block starts with `---` on the first line and ends with `---` or
`...` on a line of its own. Line endings are normalized. An unterminated block
is treated as ordinary Markdown rather than stripping the document.

When enabled, a **Metadata** section shows literal YAML key/value source with
syntax colors, preserving ordering, nested structure, and Unicode. Empty blocks
show a short empty-state message. Malformed or over-nested YAML stays plain
source with a label. Nothing in the metadata becomes a Markdown link, image,
footnote, component, or equation. Tags and aliases are never resolved and values
are not instantiated as objects. This is a source-oriented metadata panel, not a
full YAML object viewer or table.

The section displays at most 16,384 UTF-16 units and marks truncated input.
Structural validation uses the existing YAML parser's 128-node nesting limit;
only the bounded, non-truncated input is validated/highlighted. The document body
renders independently. No new parser dependency or network access is added.

Use `Tests/Fixtures/front-matter.md` in Finder. Also check malformed, empty,
unterminated, nested, Unicode, and oversized inputs with `./scripts/test.sh`.

## Saving the experiment demo

Development builds replace **Show experiment demo in Finder** with **Save
experiment demo…**. Choose a destination in the standard Save dialog; Peekdown
writes the bundled demo there and selects it in Finder. Press Space to preview.
Cancel leaves files unchanged, and save failures produce a visible error. Only
the host gains user-selected read/write access; both extensions remain read-only.
Signed desktop validation of this new Save workflow is still pending.
