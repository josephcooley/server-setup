Joseph prefers simple, working solutions over complex architectures — will push back when you over-engineer. Values "it just works" over elegance. Doesn't want to modify existing output files to make things work. Communicates casually and directly.
§
Joseph's camping prefs: tent-only. Output: markdown table, name=link, Type=area+distance, Available=#/# total.
§
Joseph values simplicity. Prefers existing Docker projects. Don't modify his existing output files. Start simple (nginx/apache for serving, bash for indexing). Summarize before deleting — he wants confirmation before destructive actions.
§
Dynamic updates: HTML dashboards live in /workspace/dashboards/. Joseph serves them via Apache httpd:2.4 in Docker (bind-mount read-only, writable host volumes for logs/run). Also generate-index.sh rebuilds a landing page linking all sub-dashboards.
§
Joseph asks to review before deleting files. When he says "summarize what will be deleted," he expects confirmation before action — don't just nuke things.
§
Joseph's rule: NEVER delete or modify any file without explicit permission first. Always ask before taking destructive action on existing files.
§
When showing YAML files, always show raw text — never as a tree/diagram/format that obscures the actual content.