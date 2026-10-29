# Native Markdown additions

Visit https://github.com/h0ck3ystyx/peekdown, <https://example.org/a_b> or www.example.org.
Contact reader@example.org or <reader@example.org>. An [explicit URL label](https://example.org/explicit) keeps its destination.

An early reference[^later], **a formatted reference[^first]**, a repeated reference[^later], and an undefined one[^missing].

> [!NOTE]
> Read the **important details** at https://example.org/note.[^first]
>
> A second paragraph with `literal code`.

> [!TIP]
> Select a Markdown file and press Space.

> [!IMPORTANT]
> Keep the app installed.

> [!WARNING]
> Avoid keeping duplicate app copies.

> [!CAUTION]
> A final callout with ~~old advice~~.

> [!UNKNOWN]
> This remains an ordinary quote.

| Source | Reference |
| --- | --- |
| https://example.org/table | [^table] |
| `https://example.org/code` | `[^missing]` |

```markdown
https://example.org/fenced
[^fenced]: Not a definition
> [!WARNING]
```

    https://example.org/indented
    [^indented]: Also not a definition

Escaped: \[^first], \<https://example.org/escaped>, and \*literal\*.

[^first]: This is the second numbered note, with *italic text*.
[^later]: This is the first numbered note.
    An indented continuation with https://example.org/note-body.

    Another paragraph.
[^table]: A note referenced in a table.
[^unused]: This note should not appear.
