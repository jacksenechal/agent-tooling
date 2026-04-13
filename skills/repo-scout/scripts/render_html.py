#!/usr/bin/env python3
"""Render a markdown file to HTML with Mermaid diagram support.

Usage: render_html.py <markdown-file> [output-html]

Uses marked.js (CDN) for markdown rendering and mermaid.js (CDN) for diagrams.
No Python dependencies beyond stdlib.
"""
import json
import sys
from pathlib import Path

HTML_TEMPLATE = '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<style>
  body {{
    max-width: 960px; margin: 0 auto; padding: 2rem 1.5rem;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
    line-height: 1.65; color: #1a1a2e; background: #fafafa;
  }}
  h1 {{ border-bottom: 2px solid #333; padding-bottom: 0.3em; margin-top: 0; }}
  h2 {{ border-bottom: 1px solid #ddd; padding-bottom: 0.2em; margin-top: 2.5em; color: #2c3e50; }}
  h3 {{ margin-top: 1.8em; color: #34495e; }}
  blockquote {{
    border-left: 3px solid #7f8c8d; margin: 1em 0; padding: 0.5em 1em;
    background: #f0f0f0; color: #555; font-size: 0.95em;
  }}
  table {{ border-collapse: collapse; width: 100%; margin: 1em 0; font-size: 0.92em; }}
  th, td {{ border: 1px solid #ddd; padding: 0.5em 0.75em; text-align: left; }}
  th {{ background: #ecf0f1; font-weight: 600; }}
  tr:nth-child(even) {{ background: #f9f9f9; }}
  code {{
    background: #eef; padding: 0.15em 0.4em; border-radius: 3px;
    font-size: 0.88em; font-family: "SF Mono", "Fira Code", "Cascadia Code", monospace;
  }}
  pre {{ background: #2d2d2d; color: #ccc; padding: 1em 1.2em; border-radius: 6px; overflow-x: auto; }}
  pre code {{ background: none; padding: 0; color: inherit; font-size: 0.85em; }}
  .mermaid-wrapper {{
    position: relative; margin: 1.5em 0;
  }}
  .mermaid {{
    text-align: center; background: #fff;
    padding: 1em; border-radius: 8px; border: 1px solid #e0e0e0;
  }}
  .expand-btn {{
    position: absolute; top: 0.4em; right: 0.4em; z-index: 1;
    background: #fff; border: 1px solid #ccc; border-radius: 4px;
    padding: 0.25em 0.5em; cursor: pointer; font-size: 0.8em; color: #555;
    opacity: 0.6; transition: opacity 0.15s;
  }}
  .expand-btn:hover {{ opacity: 1; }}
  .diagram-overlay {{
    display: none; position: fixed; inset: 0; z-index: 9999;
    background: rgba(255,255,255,0.97); overflow: auto;
    justify-content: center; align-items: center; padding: 2rem;
  }}
  .diagram-overlay.active {{ display: flex; }}
  .diagram-overlay .overlay-content {{
    width: 100%; height: 100%;
    display: flex; justify-content: center; align-items: center;
  }}
  .diagram-overlay .mermaid {{
    width: 95vw; height: 90vh; max-width: none;
    display: flex; justify-content: center; align-items: center;
    padding: 1em;
  }}
  .diagram-overlay .mermaid svg {{
    width: 100% !important; height: 100% !important;
    max-width: 100% !important; max-height: 100% !important;
  }}
  .diagram-overlay .close-btn {{
    position: fixed; top: 1rem; right: 1.5rem; z-index: 10000;
    background: #333; color: #fff; border: none; border-radius: 4px;
    padding: 0.4em 0.8em; cursor: pointer; font-size: 1em;
  }}
  .diagram-overlay .close-btn:hover {{ background: #555; }}
  dl {{ margin: 1em 0; }}
  dt {{ font-weight: 600; margin-top: 0.75em; }}
  dd {{ margin-left: 1.5em; margin-bottom: 0.25em; color: #444; }}
  hr {{ border: none; border-top: 1px solid #ddd; margin: 2em 0; }}
  a {{ color: #2980b9; text-decoration: none; }}
  a:hover {{ text-decoration: underline; }}
  @media print {{
    body {{ max-width: none; padding: 1cm; }}
    .mermaid {{ break-inside: avoid; }}
    h2 {{ page-break-before: always; }}
    h2:first-of-type {{ page-break-before: avoid; }}
  }}
</style>
</head>
<body>
<div id="content"></div>
<script src="https://cdn.jsdelivr.net/npm/marked@15/marked.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>
<script>
const md = {markdown_json};

const renderer = new marked.Renderer();
const origCode = renderer.code.bind(renderer);
renderer.code = function(token) {{
  const text = typeof token === 'object' ? token.text : token;
  const lang = typeof token === 'object' ? token.lang : arguments[1];
  if (lang === 'mermaid') {{
    return '<div class="mermaid">' + text + '</div>';
  }}
  return origCode(token);
}};
marked.setOptions({{ renderer: renderer }});

document.getElementById('content').innerHTML = marked.parse(md);

// Wrap each .mermaid in a wrapper with an expand button
document.querySelectorAll('.mermaid').forEach(el => {{
  const wrapper = document.createElement('div');
  wrapper.className = 'mermaid-wrapper';
  el.parentNode.insertBefore(wrapper, el);
  wrapper.appendChild(el);

  const btn = document.createElement('button');
  btn.className = 'expand-btn';
  btn.textContent = 'Expand';
  btn.onclick = () => openOverlay(el);
  wrapper.appendChild(btn);
}});

// Create the fullscreen overlay (once)
const overlay = document.createElement('div');
overlay.className = 'diagram-overlay';
overlay.innerHTML = '<button class="close-btn">Close</button><div class="overlay-content"></div>';
document.body.appendChild(overlay);
overlay.querySelector('.close-btn').onclick = () => overlay.classList.remove('active');
overlay.addEventListener('click', e => {{ if (e.target === overlay) overlay.classList.remove('active'); }});
document.addEventListener('keydown', e => {{ if (e.key === 'Escape') overlay.classList.remove('active'); }});

function openOverlay(mermaidEl) {{
  const content = overlay.querySelector('.overlay-content');
  content.innerHTML = '';
  const clone = mermaidEl.cloneNode(true);
  // Strip the old rendered id so mermaid re-renders at full size
  clone.removeAttribute('data-processed');
  clone.innerHTML = mermaidEl.getAttribute('data-original') || mermaidEl.textContent;
  content.appendChild(clone);
  overlay.classList.add('active');
  mermaid.run({{ nodes: [clone] }});
}}

// Stash the original mermaid source before mermaid renders it into SVG
document.querySelectorAll('.mermaid').forEach(el => {{
  el.setAttribute('data-original', el.textContent);
}});

mermaid.initialize({{ startOnLoad: true, theme: 'neutral', securityLevel: 'loose' }});
</script>
</body>
</html>'''


def main():
    if len(sys.argv) < 2:
        print("Usage: render_html.py <markdown-file> [output-html]", file=sys.stderr)
        sys.exit(1)

    md_path = Path(sys.argv[1])
    html_path = Path(sys.argv[2]) if len(sys.argv) > 2 else md_path.with_suffix(".html")

    if not md_path.exists():
        print(f"Error: {md_path} not found", file=sys.stderr)
        sys.exit(1)

    content = md_path.read_text(encoding="utf-8")

    title = "Repo Scout Report"
    for line in content.splitlines():
        if line.startswith("# "):
            title = line.lstrip("# ").strip()
            break

    html = HTML_TEMPLATE.format(title=title, markdown_json=json.dumps(content))
    html_path.write_text(html, encoding="utf-8")
    print(f"Rendered: {html_path}")


if __name__ == "__main__":
    main()
