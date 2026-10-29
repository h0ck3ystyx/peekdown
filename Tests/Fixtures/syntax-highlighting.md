# Syntax highlighting

Native highlighting stays offline. Comments, strings, keywords, numbers, and
selected types, properties, and variables receive colors without changing text.

```swift
// Swift: types, strings, numbers, and nested comments
struct Greeting {
    let message: String = "Hello, 👋"
    func show() async throws {
        /* outer /* inner */ done */
        print(message, 42)
    }
}
```

```bash
#!/bin/bash
# Shell: quoted strings and variables
export DEST="$HOME/Applications"
if test -d "$DEST"; then
    echo 'Ready to preview Markdown'
fi
printf '%s\n' ${DEST}
```

```json
{"enabled": true, "count": 42, "url": "https://example.org"}
```

```yaml
# YAML: simple mapping keys and scalar tokens
app-name: Peekdown
enabled: true
retries: 3
message: "Hello, world"
```

```python
# Python: multiline strings remain literal
class Preview:
    def render(self, count=3):
        message = """Hello
# this is part of the string
world"""
        return message if count > 0 else None
```

```javascript
// JavaScript: URLs inside strings are not comments or active links
const url = "https://example.org";
async function preview() {
    return `Preview ${url}`;
}
```

```typescript
interface Preview {
    title: string;
    enabled: boolean;
}
const count: number = 3;
```

```unknown
let this_stays_plain = "Unknown language";
```

    let indented_stays_plain = "No language hint"

`let inline_stays_plain = true`
