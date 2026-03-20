#!/usr/bin/env python3
"""
Intelligent Lint Waiver Generator
Parses violation details from email and generates proper XML waivers
Usage: python3 generate_lint_waivers_from_violations.py <xml_file> <violation_content_file> <author>
"""

import sys
import re

def parse_violation_table(content):
    """Parse violation table from email content"""
    violations = []
    
    lines = content.strip().split('\n')
    
    for line in lines:
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        
        # Try to parse table format: Code,Error,Type,Filename,Line,Message
        # Or simple format with | separators
        if '|' in line:
            fields = [f.strip() for f in line.split('|')]
        elif ',' in line:
            fields = [f.strip() for f in line.split(',')]
        else:
            # Try to parse free-form text
            violation = parse_freeform_violation(line)
            if violation:
                violations.append(violation)
            continue
        
        # Skip header rows
        if any(h in line.lower() for h in ['code', 'error', 'type', 'filename', 'message', 'line']):
            continue
        
        # Parse table row
        if len(fields) >= 4:
            violation = {
                'code': fields[0] if len(fields) > 0 else '',
                'error': fields[1] if len(fields) > 1 else '',
                'type': fields[2] if len(fields) > 2 else '',
                'filename': fields[3] if len(fields) > 3 else '',
                'line': fields[4] if len(fields) > 4 else '',
                'msg': fields[5] if len(fields) > 5 else ''
            }
            
            if violation['error'] and violation['filename']:
                violations.append(violation)
    
    return violations

def parse_freeform_violation(line):
    """Parse free-form violation text"""
    violation = {
        'code': '',
        'error': '',
        'type': '',
        'filename': '',
        'line': '',
        'msg': ''
    }
    
    # Extract error code (e.g., W164b, NTL_CON32)
    error_match = re.search(r'\b([A-Z]+[0-9]+[a-z]?|[A-Z_]+[0-9]+)\b', line)
    if error_match:
        violation['error'] = error_match.group(1)
    
    # Extract filename
    file_match = re.search(r'(rtl_\w+\.v|\w+\.v)', line)
    if file_match:
        violation['filename'] = file_match.group(1)
    
    # Extract line number
    line_match = re.search(r'line[:\s]+(\d+)', line, re.I)
    if line_match:
        violation['line'] = line_match.group(1)
    
    # Only return if we found at least error and filename
    if violation['error'] and violation['filename']:
        return violation
    
    return None

def generate_waiver_xml(violations, author='agent', reason='AI-generated waiver based on violation review'):
    """Generate XML waiver entries from violations"""
    xml_output = '\n<!-- AI-Generated Waivers from Violation Table -->\n'
    
    for v in violations:
        xml_output += '<waive_regexp>\n'
        xml_output += f'\t<error>{escape_xml(v["error"])}</error>\n'
        xml_output += f'\t<filename>{escape_xml(v["filename"])}</filename>\n'
        
        # Add code if available, otherwise use wildcard
        if v['code'] and v['code'] != '':
            xml_output += f'\t<code>{escape_xml(v["code"])}</code>\n'
        
        # Add message if available, otherwise use wildcard
        if v['msg'] and v['msg'] != '':
            xml_output += f'\t<msg>{escape_xml(v["msg"])}</msg>\n'
        
        # Add line if available
        if v['line'] and v['line'] != '':
            xml_output += f'\t<line>{escape_xml(v["line"])}</line>\n'
        
        xml_output += f'\t<reason>{escape_xml(reason)}</reason>\n'
        xml_output += f'\t<author>{escape_xml(author)}</author>\n'
        xml_output += '</waive_regexp>\n'
    
    return xml_output

def add_waivers_to_xml(xml_file, waiver_xml):
    """Add waiver XML to file before </block> tag"""
    with open(xml_file, 'r') as f:
        content = f.read()
    
    # Find the position before </block>
    block_end = content.rfind('</block>')
    if block_end == -1:
        print("ERROR: Could not find </block> tag in XML file")
        return False
    
    # Insert waivers before </block>
    new_content = content[:block_end] + waiver_xml + content[block_end:]
    
    # Write back to file
    with open(xml_file, 'w') as f:
        f.write(new_content)
    
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
    if len(sys.argv) < 3:
        print("Usage: python3 generate_lint_waivers_from_violations.py <xml_file> <violation_content_file> [author] [reason]")
        sys.exit(1)
    
    xml_file = sys.argv[1]
    content_file = sys.argv[2]
    author = sys.argv[3] if len(sys.argv) > 3 else 'agent'
    reason = sys.argv[4] if len(sys.argv) > 4 else 'AI-generated waiver based on violation review'
    
    # Read violation content
    with open(content_file, 'r') as f:
        content = f.read()
    
    # Parse violations
    violations = parse_violation_table(content)
    
    if not violations:
        print("WARNING: No valid violations found in content file")
        print("Expected format: Code,Error,Type,Filename,Line,Message")
        print("Or table with | separators")
        sys.exit(0)
    
    print(f"Found {len(violations)} violations to waive")
    
    # Generate waiver XML
    waiver_xml = generate_waiver_xml(violations, author, reason)
    
    # Add to XML file
    success = add_waivers_to_xml(xml_file, waiver_xml)
    
    if not success:
        sys.exit(1)
    
    print(f"Successfully added {len(violations)} waiver(s) to {xml_file}")
    
    # Print summary
    print("\nWaivers generated for:")
    for v in violations:
        print(f"  - {v['error']} in {v['filename']}" + (f" (line {v['line']})" if v['line'] else ""))

if __name__ == '__main__':
    main()
