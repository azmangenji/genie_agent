#!/usr/bin/env python3
"""
Lint Waiver XML Updater
Adds waiver entries to LEDA lint waiver XML file
Usage: python3 update_lint_waiver.py <xml_file> <waiver_content_file>
"""

import sys
import re
import xml.etree.ElementTree as ET
from xml.dom import minidom

def parse_waiver_content(content_file):
    """Parse waiver content from AI-extracted file"""
    waivers = []
    
    with open(content_file, 'r') as f:
        content = f.read()
    
    # Split by waiver blocks (looking for error codes or waive keywords)
    # Support both exact waivers and regexp waivers
    
    # Try to detect if it's a structured waiver or free-form text
    lines = content.strip().split('\n')
    
    for line in lines:
        line = line.strip()
        if not line or line.startswith('#'):
            continue
            
        # Parse different waiver formats
        waiver = parse_waiver_line(line)
        if waiver:
            waivers.append(waiver)
    
    return waivers

def parse_waiver_line(line):
    """Parse a single waiver line into structured format"""
    waiver = {
        'type': 'waive_regexp',  # Default to regexp for flexibility
        'error': '',
        'filename': '',
        'code': '.*',
        'msg': '.*',
        'line': '.*',
        'column': '.*',
        'reason': 'AI-generated waiver',
        'author': 'agent'
    }
    
    # Try to extract error code (e.g., W164b, NTL_CON32)
    error_match = re.search(r'\b([A-Z]+[0-9]+[a-z]?|[A-Z_]+[0-9]+)\b', line)
    if error_match:
        waiver['error'] = error_match.group(1)
    
    # Try to extract filename
    file_match = re.search(r'(rtl_\w+\.v|\w+\.v)', line)
    if file_match:
        waiver['filename'] = file_match.group(1)
    
    # Try to extract reason
    reason_match = re.search(r'reason[:\s]+(.+?)(?:$|author)', line, re.I)
    if reason_match:
        waiver['reason'] = reason_match.group(1).strip()
    
    # Try to extract author
    author_match = re.search(r'author[:\s]+(\w+)', line, re.I)
    if author_match:
        waiver['author'] = author_match.group(1)
    
    # If line contains specific code pattern, extract it
    code_match = re.search(r'code[:\s]+(.+?)(?:msg|reason|$)', line, re.I)
    if code_match:
        waiver['code'] = code_match.group(1).strip()
    
    # If line contains specific message pattern, extract it
    msg_match = re.search(r'msg[:\s]+(.+?)(?:reason|author|$)', line, re.I)
    if msg_match:
        waiver['msg'] = msg_match.group(1).strip()
    
    # Only return waiver if we found at least an error code
    if waiver['error']:
        return waiver
    
    return None

def add_waivers_to_xml(xml_file, waivers):
    """Add waiver entries to XML file before closing </block> tag"""
    
    # Read the XML file
    with open(xml_file, 'r') as f:
        content = f.read()
    
    # Find the position before </block>
    block_end = content.rfind('</block>')
    if block_end == -1:
        print("ERROR: Could not find </block> tag in XML file")
        return False
    
    # Generate waiver XML entries
    waiver_xml = '\n<!-- AI-Generated Waivers -->\n'
    
    for waiver in waivers:
        if waiver['type'] == 'waive_regexp':
            waiver_xml += '<waive_regexp>\n'
            waiver_xml += f'\t<error>{escape_xml(waiver["error"])}</error>\n'
            waiver_xml += f'\t<filename>{escape_xml(waiver["filename"])}</filename>\n'
            
            if waiver['code'] != '.*':
                waiver_xml += f'\t<code>{escape_xml(waiver["code"])}</code>\n'
            
            if waiver['msg'] != '.*':
                waiver_xml += f'\t<msg>{escape_xml(waiver["msg"])}</msg>\n'
            
            if waiver['line'] != '.*':
                waiver_xml += f'\t<line>{escape_xml(waiver["line"])}</line>\n'
            
            if waiver['column'] != '.*':
                waiver_xml += f'\t<column>{escape_xml(waiver["column"])}</column>\n'
            
            waiver_xml += f'\t<reason>{escape_xml(waiver["reason"])}</reason>\n'
            waiver_xml += f'\t<author>{escape_xml(waiver["author"])}</author>\n'
            waiver_xml += '</waive_regexp>\n'
        else:
            # Exact waiver
            waiver_xml += '<waive>\n'
            waiver_xml += f'\t<error>{escape_xml(waiver["error"])}</error>\n'
            waiver_xml += f'\t<filename>{escape_xml(waiver["filename"])}</filename>\n'
            waiver_xml += f'\t<code>{escape_xml(waiver["code"])}</code>\n'
            waiver_xml += f'\t<msg>{escape_xml(waiver["msg"])}</msg>\n'
            waiver_xml += f'\t<line>{escape_xml(waiver["line"])}</line>\n'
            waiver_xml += f'\t<column>{escape_xml(waiver["column"])}</column>\n'
            waiver_xml += f'\t<reason>{escape_xml(waiver["reason"])}</reason>\n'
            waiver_xml += f'\t<author>{escape_xml(waiver["author"])}</author>\n'
            waiver_xml += '</waive>\n'
    
    # Insert waivers before </block>
    new_content = content[:block_end] + waiver_xml + content[block_end:]
    
    # Write back to file
    with open(xml_file, 'w') as f:
        f.write(new_content)
    
    print(f"Successfully added {len(waivers)} waiver(s) to {xml_file}")
    return True

def escape_xml(text):
    """Escape special XML characters"""
    if not text:
        return ''
    text = str(text)
    text = text.replace('&', '&amp;')
    text = text.replace('<', '&lt;')
    text = text.replace('>', '&gt;')
    text = text.replace('"', '&quot;')
    text = text.replace("'", '&apos;')
    return text

def main():
    if len(sys.argv) != 3:
        print("Usage: python3 update_lint_waiver.py <xml_file> <waiver_content_file>")
        sys.exit(1)
    
    xml_file = sys.argv[1]
    content_file = sys.argv[2]
    
    # Parse waiver content
    waivers = parse_waiver_content(content_file)
    
    if not waivers:
        print("WARNING: No valid waivers found in content file")
        sys.exit(0)
    
    # Add waivers to XML
    success = add_waivers_to_xml(xml_file, waivers)
    
    if not success:
        sys.exit(1)
    
    print("Lint waiver update completed successfully")

if __name__ == '__main__':
    main()
