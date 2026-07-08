#!/bin/bash
# /workspace/dashboards/generate-index.sh
# Scans /workspace/dashboards for directories containing index.html and creates a landing page

DASHBOARDS="/workspace/dashboards"
OUTPUT="$DASHBOARDS/index.html"

cat > "$OUTPUT" << 'HEADER'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Dashboards</title>
<style>
body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    background: #0d1117;
    color: #c9d1d9;
    max-width: 800px;
    margin: 0 auto;
    padding: 32px;
}
h1 { color: #58a6ff; margin-bottom: 24px; }
ul { list-style: none; padding: 0; }
li { margin-bottom: 12px; }
a {
    color: #58a6ff;
    text-decoration: none;
    font-size: 1.05rem;
}
a:hover { text-decoration: underline; }
.meta { color: #6e7681; font-size: 0.8rem; margin-top: 4px; }
</style>
</head>
<body>
<h1>Dashboards</h1>
<ul>
HEADER

# Find all directories containing index.html under dashboards/
find "$DASHBOARDS" -name "index.html" -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "$DASHBOARDS/index.html" | sort | while read -r filepath; do
    dir=$(dirname "$filepath")
    relpath="${filepath#$DASHBOARDS/}"
    display=$(basename "$dir")
    echo "    <li><a href=\"$relpath\">$display</a><div class=\"meta\">$relpath</div></li>" >> "$OUTPUT"
done

cat >> "$OUTPUT" << 'FOOTER'
</ul>
</body>
</html>
FOOTER

echo "Generated index with $(grep -c '<li>' "$OUTPUT") entries at $OUTPUT"
