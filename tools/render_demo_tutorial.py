"""Render the deployment guide as a standalone, printable HTML document.

Supports the Markdown constructs used in this guide; no external packages.
"""
import html
import re
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]


def inline(value):
    value=html.escape(value)
    value=re.sub(r'`([^`]+)`',r'<code>\1</code>',value)
    value=re.sub(r'\*\*([^*]+)\*\*',r'<strong>\1</strong>',value)
    value=re.sub(r'\[([^]]+)\]\(([^)]+)\)',r'<a href="\2">\1</a>',value)
    return value


def render(source):
    output=[]; paragraph=[]; code=[]; in_code=False; list_tag=None; table=[]
    def flush():
        if paragraph:
            output.append('<p>'+inline(' '.join(paragraph))+'</p>'); paragraph.clear()
    def end_table():
        if table:
            output.append('<table><thead><tr>'+''.join('<th>'+inline(c.strip())+'</th>' for c in table[0].strip('|').split('|'))+'</tr></thead><tbody>')
            for row in table[2:]:
                output.append('<tr>'+''.join('<td>'+inline(c.strip())+'</td>' for c in row.strip('|').split('|'))+'</tr>')
            output.append('</tbody></table>'); table.clear()
    for line in source.splitlines()+['']:
        if line.startswith('```'):
            flush(); end_table()
            if in_code:
                output.append('<pre><code>'+html.escape('\n'.join(code))+'</code></pre>'); code.clear()
            in_code=not in_code
            continue
        if in_code:
            code.append(line); continue
        if line.startswith('|'):
            flush(); table.append(line); continue
        end_table()
        heading=re.match(r'^(#{1,6}) (.*)',line)
        item=re.match(r'^(?:- |\d+\. )(.*)',line)
        if heading:
            flush()
            if list_tag: output.append(f'</li></{list_tag}>'); list_tag=None
            level=len(heading[1]); output.append(f'<h{level}>'+inline(heading[2])+f'</h{level}>')
        elif item:
            flush()
            desired='ol' if re.match(r'^\d+\.',line) else 'ul'
            if list_tag and list_tag!=desired:
                output.append(f'</li></{list_tag}>'); list_tag=None
            if not list_tag: output.append(f'<{desired}>'); list_tag=desired
            else: output.append('</li>')
            output.append('<li>'+inline(item[1]))
        elif not line.strip():
            flush()
            if list_tag: output.append(f'</li></{list_tag}>'); list_tag=None
        elif list_tag and (line.startswith('   ') or line.startswith('  ')):
            output.append(' '+inline(line.strip()))
        else:
            if list_tag: output.append(f'</li></{list_tag}>'); list_tag=None
            paragraph.append(line)
    return '\n'.join(output)


def main():
    source=ROOT/'ZYBO_Z7_10_DEMO_TUTORIAL.md'
    body=render(source.read_text(encoding='utf-8'))
    style='''body{font:17px/1.6 system-ui,sans-serif;color:#17212e;max-width:1050px;margin:40px auto;padding:0 24px}
    h1,h2{line-height:1.2;color:#123e62}h2{margin-top:2.2em;border-top:1px solid #ccd8e2;padding-top:.8em}
    code{font:14px Consolas,monospace;background:#eef3f7;padding:2px 4px}pre{padding:16px;background:#eef3f7;white-space:pre-wrap;overflow-wrap:anywhere}
    table{border-collapse:collapse;width:100%;font-size:15px}th,td{border:1px solid #cbd5df;padding:9px;text-align:left;vertical-align:top}th{background:#e7eff7}
    a{color:#125996}li{margin:.3em 0}@media print{body{font-size:11pt;margin:0;max-width:none}h2{break-after:avoid}pre,tr{break-inside:avoid}a{color:inherit}button{display:none}}'''
    document='<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Zybo Z7-10 SNN deployment tutorial</title><style>'+style+'</style></head><body>'
    document+='<button onclick="window.print()">Print / Save as PDF</button>'+body+'</body></html>'
    destination=ROOT/'ZYBO_Z7_10_DEMO_TUTORIAL.html'
    destination.write_text(document,encoding='utf-8',newline='\n')
    print(destination)


if __name__=='__main__': main()
