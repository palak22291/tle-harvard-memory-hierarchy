#!/usr/bin/env python3
"""
Convert docs/phase2_research_paper_ieee.md to an IEEE Transactions / Conference styled PDF
using Google Chrome headless.
"""

import os
import re
import subprocess
import sys

def parse_inline(text):
    # LaTeX math replacements
    text = re.sub(r'\$2\.80\\times\$', '2.80&times;', text)
    text = re.sub(r'\$256 \\times 32\$-bit', '256 &times; 32-bit', text)
    text = re.sub(r'\$512 \\times 32\$-bit', '512 &times; 32-bit', text)
    text = re.sub(r'\$N_{\\text\{instr\}}\$', '<i>N</i><sub>instr</sub>', text)
    text = re.sub(r'\$F_{\\max}\$', '<i>F</i><sub>max</sub>', text)
    text = re.sub(r'\$\\ge \\text\{0x0000\\_1000\}\$', '&ge; 0x0000_1000', text)
    text = re.sub(r'\$12 \\text\{ mem ops\} \\times 3 \\text\{ clks\}\$', '12 mem ops &times; 3 clks', text)
    text = re.sub(r'\$4 \\text\{ L2 ops\} \\times 1 \\text\{ wait clk\}\$', '4 L2 ops &times; 1 wait clk', text)
    
    # Generic math fallbacks
    text = re.sub(r'\$([^\$]+)\$', r'<i>\1</i>', text)
    
    # Code spans
    text = re.sub(r'`([^`]+)`', r'<code>\1</code>', text)
    
    # Bold italic
    text = re.sub(r'\*\*\*([^\*]+)\*\*\*', r'<strong><em>\1</em></strong>', text)
    # Bold
    text = re.sub(r'\*\*([^\*]+)\*\*', r'<strong>\1</strong>', text)
    # Italic
    text = re.sub(r'\*([^\*]+)\*', r'<em>\1</em>', text)
    
    # Em dashes
    text = text.replace('—', '&mdash;').replace('--', '&ndash;')
    
    return text

def parse_markdown_to_html(md_text):
    lines = md_text.splitlines()
    
    title = ""
    authors = ""
    course = ""
    
    abstract_html = ""
    index_terms_html = ""
    
    body_blocks = []
    
    i = 0
    n = len(lines)
    
    eq_counter = 1
    table_counter = 1
    
    while i < n:
        line = lines[i].strip()
        
        # Skip empty lines
        if not line:
            i += 1
            continue
            
        # Title
        if line.startswith("# "):
            title = line[2:].strip()
            i += 1
            continue
            
        # Authors
        if line.startswith("**Authors:**"):
            m = re.search(r'\*\*Authors:\*\*\s*(.+)', line)
            if m:
                authors = parse_inline(m.group(1))
            i += 1
            continue
            
        # Course / Affiliation
        if line.startswith("**Course:**"):
            m = re.search(r'\*\*Course:\*\*\s*(.+)', line)
            if m:
                course = parse_inline(m.group(1))
            i += 1
            continue
            
        # Horizontal rules
        if line == "---":
            i += 1
            continue
            
        # Abstract heading
        if line.startswith("## Abstract"):
            i += 1
            while i < n and not lines[i].strip():
                i += 1
            if i < n:
                abstract_text = lines[i].strip()
                abstract_html = parse_inline(abstract_text)
                i += 1
            continue
            
        # Index Terms
        if line.startswith("**Index Terms") or line.startswith("**Index Terms—"):
            terms = line.split("**", 2)[-1].strip()
            if terms.startswith("—") or terms.startswith("-"):
                terms = terms.lstrip("—- ")
            index_terms_html = parse_inline(terms)
            i += 1
            continue
            
        # Section Headings (H2)
        if line.startswith("## "):
            sec_title = line[3:].strip()
            body_blocks.append(f'<h2 class="sec-heading">{sec_title.upper()}</h2>')
            i += 1
            continue
            
        # Subsection Headings (H3)
        if line.startswith("### "):
            subsec_title = line[4:].strip()
            body_blocks.append(f'<h3 class="subsec-heading">{subsec_title}</h3>')
            i += 1
            continue
            
        # Equations
        if line.startswith("$$") and line.endswith("$$") and len(line) > 4:
            eq_text = line[2:-2].strip()
            if "CPI" in eq_text:
                eq_html = "CPI<sub>unified</sub> = CPI<sub>base</sub> + <i>f</i><sub>mem</sub> &times; <i>L</i><sub>mem</sub>"
            elif "dmem_sel" in eq_text or "dmem\\_sel" in eq_text:
                eq_html = "dmem_sel = (d_addr &amp; 0xFFFF_FC00) == 0x0000_0000"
            elif "l2_sel" in eq_text or "l2\\_sel" in eq_text:
                eq_html = "l2_sel = (d_addr &amp; 0xFFFF_F800) == 0x0000_0800"
            else:
                eq_html = parse_inline(eq_text)
                
            body_blocks.append(
                f'<div class="equation-row">'
                f'<div class="equation-body">{eq_html}</div>'
                f'<div class="equation-num">({eq_counter})</div>'
                f'</div>'
            )
            eq_counter += 1
            i += 1
            continue
            
        # Table
        if line.startswith("|") and line.endswith("|"):
            table_lines = []
            while i < n and lines[i].strip().startswith("|"):
                table_lines.append(lines[i].strip())
                i += 1
                
            if len(table_lines) >= 3:
                header_row = [c.strip() for c in table_lines[0].strip('|').split('|')]
                rows = []
                for row_line in table_lines[2:]:
                    row_cells = [c.strip() for c in row_line.strip('|').split('|')]
                    rows.append(row_cells)
                    
                caption = ""
                roman_labels = ["I", "II", "III", "IV", "V"]
                label_idx = min(table_counter - 1, len(roman_labels) - 1)
                t_label = roman_labels[label_idx]
                
                if table_counter == 1:
                    caption = "32-Bit Harvard Address Map and Hardware Decoding Specification"
                elif table_counter == 2:
                    caption = "RTL Verification Methodology and Automated Assertion Results"
                elif table_counter == 3:
                    caption = "Quantitative Architectural Comparison: Harvard vs. Von Neumann Baseline"
                elif table_counter == 4:
                    caption = "Individual Contributions and Subsystem Ownership Breakdown"
                    
                table_html = [
                    '<div class="table-container">',
                    f'<div class="table-caption"><span class="table-num">TABLE {t_label}</span><br><span class="table-name">{caption}</span></div>',
                    '<table>',
                    '<thead><tr>'
                ]
                for h in header_row:
                    table_html.append(f'<th>{parse_inline(h)}</th>')
                table_html.append('</tr></thead><tbody>')
                
                for r in rows:
                    table_html.append('<tr>')
                    for cell in r:
                        table_html.append(f'<td>{parse_inline(cell)}</td>')
                    table_html.append('</tr>')
                    
                table_html.append('</tbody></table></div>')
                body_blocks.append('\n'.join(table_html))
                table_counter += 1
            continue
            
        # Ordered lists
        if re.match(r'^\d+\.\s+', line):
            list_items = []
            while i < n and re.match(r'^\d+\.\s+', lines[i].strip()):
                item_text = re.sub(r'^\d+\.\s+', '', lines[i].strip())
                list_items.append(f'<li>{parse_inline(item_text)}</li>')
                i += 1
            body_blocks.append('<ol>' + ''.join(list_items) + '</ol>')
            continue
            
        # Reference item
        if re.match(r'^\[\d+\]', line):
            body_blocks.append(f'<div class="ref-item">{parse_inline(line)}</div>')
            i += 1
            continue
            
        # Regular paragraph
        para_lines = []
        while i < n and lines[i].strip() and not lines[i].strip().startswith(("#", "---", "|", "$$", "1.", "[", "**Index Terms")):
            para_lines.append(lines[i].strip())
            i += 1
        para_text = " ".join(para_lines)
        if para_text:
            body_blocks.append(f'<p>{parse_inline(para_text)}</p>')
            
    html_doc = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>{title}</title>
<style>
  @page {{
    size: letter;
    margin: 0.65in 0.55in 0.65in 0.55in;
  }}
  * {{
    box-sizing: border-box;
  }}
  body {{
    font-family: 'Times New Roman', 'Nimbus Roman No9 L', Times, serif;
    font-size: 9.5pt;
    line-height: 1.22;
    color: #111;
    margin: 0;
    padding: 0;
    background: #fff;
  }}
  
  /* Header banner spanning full page */
  .paper-header {{
    text-align: center;
    margin-bottom: 12pt;
    padding-bottom: 4pt;
  }}
  .paper-title {{
    font-size: 19pt;
    font-weight: bold;
    line-height: 1.18;
    margin: 0 0 8pt 0;
    letter-spacing: -0.2px;
  }}
  .paper-authors {{
    font-size: 10.5pt;
    margin: 0 0 3pt 0;
    font-weight: 500;
  }}
  .paper-affiliation {{
    font-size: 9.5pt;
    font-style: italic;
    color: #333;
    margin: 0 0 10pt 0;
  }}
  
  /* Abstract & Index Terms */
  .abstract-box {{
    margin-bottom: 10pt;
    text-align: justify;
    text-justify: inter-word;
  }}
  .abstract-label {{
    font-weight: bold;
    font-style: italic;
  }}
  .index-terms {{
    margin-top: 5pt;
    text-align: justify;
  }}
  .index-label {{
    font-weight: bold;
    font-style: italic;
  }}
  
  /* Two-column layout */
  .paper-columns {{
    columns: 2;
    column-gap: 0.25in;
    text-align: justify;
    text-justify: inter-word;
  }}
  
  p {{
    margin: 0 0 6pt 0;
    text-indent: 1.2em;
  }}
  p:first-of-type {{
    text-indent: 0;
  }}
  
  /* Section Headings */
  h2.sec-heading {{
    font-size: 9.5pt;
    font-weight: bold;
    text-align: center;
    margin: 10pt 0 4pt 0;
    letter-spacing: 0.5px;
    break-after: avoid;
    break-inside: avoid;
  }}
  
  /* Subsection Headings */
  h3.subsec-heading {{
    font-size: 9.5pt;
    font-weight: bold;
    font-style: italic;
    text-align: left;
    margin: 7pt 0 3pt 0;
    break-after: avoid;
    break-inside: avoid;
  }}
  
  /* Equations */
  .equation-row {{
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin: 6pt 0;
    padding: 0 4pt;
    break-inside: avoid;
  }}
  .equation-body {{
    flex: 1;
    text-align: center;
    font-family: 'Times New Roman', serif;
    font-style: italic;
    font-size: 9.5pt;
  }}
  .equation-num {{
    font-style: normal;
    font-size: 9.5pt;
    margin-left: 8pt;
  }}
  
  /* Lists */
  ol {{
    margin: 0 0 6pt 0;
    padding-left: 1.4em;
  }}
  li {{
    margin-bottom: 3.5pt;
    text-align: justify;
  }}
  
  /* Inline code & Code blocks */
  code {{
    font-family: 'Courier New', Courier, monospace;
    font-size: 8.5pt;
    background: #f4f4f4;
    padding: 1px 3px;
    border-radius: 2px;
  }}
  
  /* Tables */
  .table-container {{
    column-span: all;
    margin: 10pt auto;
    text-align: center;
    break-inside: avoid;
    page-break-inside: avoid;
  }}
  .table-caption {{
    margin-bottom: 4pt;
    line-height: 1.25;
  }}
  .table-num {{
    font-size: 8.5pt;
    font-weight: bold;
    letter-spacing: 0.5px;
  }}
  .table-name {{
    font-size: 8.5pt;
    font-variant: small-caps;
    font-weight: bold;
  }}
  table {{
    width: 98%;
    margin: 0 auto;
    border-collapse: collapse;
    font-size: 8pt;
    line-height: 1.2;
  }}
  th {{
    border-top: 1.2pt solid #000;
    border-bottom: 0.8pt solid #000;
    padding: 3.5pt 5pt;
    font-weight: bold;
    background-color: #fcfcfc;
    text-align: left;
  }}
  td {{
    padding: 3pt 5pt;
    border-bottom: 0.5pt solid #e0e0e0;
    text-align: left;
    vertical-align: top;
  }}
  tr:last-child td {{
    border-bottom: 1.2pt solid #000;
  }}
  
  /* References */
  .ref-item {{
    font-size: 8pt;
    line-height: 1.25;
    margin-bottom: 3.5pt;
    padding-left: 1.5em;
    text-indent: -1.5em;
    text-align: justify;
  }}
</style>
</head>
<body>

<div class="paper-header">
  <div class="paper-title">{title}</div>
  <div class="paper-authors">{authors}</div>
  <div class="paper-affiliation">{course}</div>
</div>

<div class="paper-columns">
  <div class="abstract-box">
    <span class="abstract-label">Abstract&mdash;</span>{abstract_html}
    <div class="index-terms">
      <span class="index-label">Index Terms&mdash;</span>{index_terms_html}
    </div>
  </div>
  
  {''.join(body_blocks)}
</div>

</body>
</html>
"""
    return html_doc

def main():
    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
    md_file = os.path.join(repo_root, 'docs', 'phase2_research_paper_ieee.md')
    html_file = os.path.join(repo_root, 'docs', 'phase2_research_paper_ieee.html')
    pdf_file = os.path.join(repo_root, 'docs', 'phase2_research_paper_ieee.pdf')
    
    print(f"Reading {md_file}...")
    with open(md_file, 'r', encoding='utf-8') as f:
        md_text = f.read()
        
    print("Converting Markdown to IEEE Conference styled HTML...")
    html_doc = parse_markdown_to_html(md_text)
    
    with open(html_file, 'w', encoding='utf-8') as f:
        f.write(html_doc)
    print(f"Wrote temporary HTML to {html_file}")
    
    chrome_bin = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    if not os.path.exists(chrome_bin):
        print(f"Error: Chrome not found at {chrome_bin}", file=sys.stderr)
        sys.exit(1)
        
    print(f"Generating PDF via Headless Chrome to {pdf_file}...")
    footer = '<div style="font-size: 8.5pt; font-family: \'Times New Roman\', serif; width: 100%; text-align: center; color: #444; padding-bottom: 6px;"><span class="pageNumber"></span></div>'
    header = '<div></div>'
    
    cmd = [
        chrome_bin,
        "--headless",
        "--disable-gpu",
        "--no-sandbox",
        "--run-all-compositor-stages-before-draw",
        "--display-header-footer",
        f"--footer-template={footer}",
        f"--header-template={header}",
        "--include-backgrounds",
        f"--print-to-pdf={pdf_file}",
        html_file
    ]
    
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"Chrome error: {res.stderr}", file=sys.stderr)
        sys.exit(res.returncode)
        
    if os.path.exists(pdf_file) and os.path.getsize(pdf_file) > 0:
        print(f"Successfully generated PDF: {pdf_file} ({os.path.getsize(pdf_file)} bytes)")
        if os.path.exists(html_file):
            os.remove(html_file)
    else:
        print("Error: PDF file was not created or is empty", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
