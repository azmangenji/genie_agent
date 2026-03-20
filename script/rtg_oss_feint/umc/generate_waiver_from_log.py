#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Smart Lint Waiver Generator from Log
Searches lint report log for violations matching user-provided code/error and generates waivers
Usage: python generate_waiver_from_log.py <lint_log> <xml_file> <violation_hints_file> <author> <reason>
"""

from __future__ import print_function
import sys
import re

def parse_leda_log(log_file):
    """Parse LEDA leda_waiver.log and extract all violations"""
    violations = []
    
    with open(log_file, 'r') as f:
        content = f.read()
    
    # Find the Unwaived section
    unwaived_match = re.search(r'Unwaived\s*\n(.*?)(?:Unused Waivers|Waived|$)', content, re.DOTALL)
    if not unwaived_match:
        print("WARNING: Could not find Unwaived section in log")
        return violations
    
    unwaived_section = unwaived_match.group(1)
    
    # Parse table rows: | Code | Error | Type | Filename | Line | Message |
    for line in unwaived_section.split('\n'):
        if re.search(r'\s+\|\s+.*\|\s+.*\|\s+.*\|\s+\d+\s+\|', line):
            fields = [f.strip() for f in line.split('|')]
            
            # Remove empty first/last fields from split
            fields = [f for f in fields if f]
            
            if len(fields) >= 6:
                # Fields are in order: code, error, type, filename, line, msg
                # Code may contain | so take everything except last 5 fields
                code = ' | '.join(fields[:-5]) if len(fields) > 6 else fields[0]
                error = fields[-5]
                vtype = fields[-4]
                filename = fields[-3]
                line_num = fields[-2]
                msg = fields[-1]
                
                violation = {
                    'code': code.strip(),
                    'error': error.strip(),
                    'type': vtype.strip(),
                    'filename': filename.strip(),
                    'line': line_num.strip(),
                    'msg': msg.strip()
                }
                
                violations.append(violation)
    
    return violations

def find_matching_violations(violations, hints):
    """Find violations matching user hints (code snippet and/or error code)"""
    matches = []
    
    # Parse hints into waiver blocks
    waiver_blocks = []
    current_block = {'error': None, 'code': None, 'reason': None, 'author': None}
    
    for hint in hints:
        hint = hint.strip()
        if not hint:
            continue
        
        # Parse fields from line (supports multiple fields on same line)
        # Extract all field:value pairs from the line
        error_match = re.search(r'error:\s*([^:]+?)(?:\s+(?:code|reason|author):|$)', hint, re.I)
        code_match = re.search(r'code:\s*(.+?)(?:\s+(?:reason|author):|$)', hint, re.I)
        reason_match = re.search(r'reason:\s*(.+?)(?:\s+author:|$)', hint, re.I)
        author_match = re.search(r'author:\s*(.+?)$', hint, re.I)
        
        # Start new block only if we see error: AND current block already has error
        # This allows error/code/reason/author to accumulate in same block
        if hint.lower().startswith('error:') and current_block['error'] is not None:
            # Save previous block
            waiver_blocks.append(current_block)
            # Start new block
            current_block = {'error': None, 'code': None, 'reason': None, 'author': None}
        
        # Extract fields from current line and add to current block
        if error_match:
            current_block['error'] = error_match.group(1).strip()
        if code_match:
            current_block['code'] = code_match.group(1).strip()
        if reason_match:
            current_block['reason'] = reason_match.group(1).strip()
        if author_match:
            current_block['author'] = author_match.group(1).strip()
    
    # Don't forget the last block
    if current_block['error'] or current_block['code']:
        waiver_blocks.append(current_block)
    
    # Now search for each waiver block
    for block in waiver_blocks:
        error_code = block['error']
        code_snippet = block['code']
        
        if code_snippet:
            code_preview = code_snippet[:50] + "..."
        else:
            code_preview = "None"
        print("Searching for: error={}, code_snippet={}".format(error_code, code_preview))
        
        for v in violations:
            match = False
            
            # Normalize whitespace for matching (remove extra spaces)
            normalized_code_snippet = re.sub(r'\s+', ' ', code_snippet).strip() if code_snippet else None
            normalized_v_code = re.sub(r'\s+', ' ', v['code']).strip()
            
            # Match by error code and code snippet
            if error_code and normalized_code_snippet:
                if v['error'] == error_code and normalized_code_snippet.lower() in normalized_v_code.lower():
                    match = True
            # Match by error code only
            elif error_code:
                if v['error'] == error_code:
                    match = True
            # Match by code snippet only
            elif normalized_code_snippet:
                if normalized_code_snippet.lower() in normalized_v_code.lower():
                    match = True
            
            if match:
                # Add violation with custom reason/author if provided
                v_copy = v.copy()
                if block['reason']:
                    v_copy['custom_reason'] = block['reason']
                if block['author']:
                    v_copy['custom_author'] = block['author']
                
                if v_copy not in matches:
                    matches.append(v_copy)
                    print("  Found: {} in {} line {}".format(v['error'], v['filename'], v['line']))
    
    return matches

def generate_waiver_xml(violations, default_author, default_reason):
    """Generate XML waiver entries"""
    xml_output = '\n<!-- AI-Generated Waivers from Log Search -->\n'
    
    # Deduplicate violations with same simplified pattern
    seen = set()
    
    for v in violations:
        # Use custom reason/author from email if provided, otherwise use defaults
        reason = v.get('custom_reason', default_reason)
        author = v.get('custom_author', default_author)
        
        # Simplify code and msg for regex matching
        simplified_code = simplify_for_regex(v["code"])
        simplified_msg = simplify_for_regex(v["msg"])
        
        # Create unique key for deduplication
        unique_key = (v["error"], v["filename"], simplified_code, simplified_msg, v["line"])
        
        # Skip if we've already added this waiver
        if unique_key in seen:
            continue
        seen.add(unique_key)
        
        # Use waive_regexp format with simplified patterns
        xml_output += '<waive_regexp>\n'
        xml_output += '   <error>{}</error>\n'.format(escape_xml(v["error"]))
        xml_output += '   <filename>{}</filename>\n'.format(escape_xml(v["filename"]))
        xml_output += '   <code>{}</code>\n'.format(escape_xml(simplified_code))
        xml_output += '   <msg>{}</msg>\n'.format(escape_xml(simplified_msg))
        xml_output += '   <line>{}</line>\n'.format(escape_xml(v["line"]))
        xml_output += '   <column>.*</column>\n'
        xml_output += '   <reason>{}</reason>\n'.format(escape_xml(reason))
        xml_output += '   <author>{}</author>\n'.format(escape_xml(author))
        xml_output += '</waive_regexp>\n'
    
    return xml_output

def add_waivers_to_xml(xml_file, waiver_xml):
    """Add waiver XML to file before </block> tag"""
    with open(xml_file, 'r') as f:
        content = f.read()
    
    block_end = content.rfind('</block>')
    if block_end == -1:
        print("ERROR: Could not find </block> tag in XML file")
        return False
    
    new_content = content[:block_end] + waiver_xml + content[block_end:]
    
    with open(xml_file, 'w') as f:
        f.write(new_content)
    
    return True

def simplify_for_regex(text):
    """Extract only words (signal names, keywords) - omit numbers and special characters"""
    if not text:
        return ''
    
    # Ensure text is unicode for Python 2/3 compatibility
    if sys.version_info[0] < 3:
        if isinstance(text, str):
            text = text.decode('utf-8', errors='ignore')
    else:
        text = str(text)
    
    # Extract all words (alphanumeric + underscore)
    words = re.findall(r'[a-zA-Z_]\w*', text)
    
    # Join with .* to create flexible pattern
    if words:
        # Keep first few important words, use .* for rest
        pattern = '.*'.join(words[:3]) + '.*'
    else:
        pattern = '.*'
    
    # Convert back to str for Python 2
    if sys.version_info[0] < 3:
        pattern = pattern.encode('utf-8')
    
    return pattern

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

def escape_regex_for_xml(text):
    """Escape regex special characters AND XML characters for waive_regexp"""
    if not text:
        return ''
    text = str(text)
    
    # First escape XML special characters (but NOT backslash yet)
    text = text.replace('&', '&amp;')
    text = text.replace('<', '&lt;')
    text = text.replace('>', '&gt;')
    text = text.replace('"', '&quot;')
    text = text.replace("'", '&apos;')
    
    # Then escape regex special characters so they're treated as literals
    # Do this AFTER XML escaping to avoid double-escaping backslashes
    regex_special = r'\.^$*+?{}[]()|\\'
    for char in regex_special:
        text = text.replace(char, '\\' + char)
    
    return text

def main():
    if len(sys.argv) < 4:
        print("Usage: python3 generate_waiver_from_log.py <lint_log> <xml_file> <hints_file> [author] [reason]")
        sys.exit(1)
    
    lint_log = sys.argv[1]
    xml_file = sys.argv[2]
    hints_file = sys.argv[3]
    author = sys.argv[4] if len(sys.argv) > 4 else 'agent'
    reason = sys.argv[5] if len(sys.argv) > 5 else 'reviewed, waived'
    
    # Parse lint log
    print("Parsing lint log: {}".format(lint_log))
    violations = parse_leda_log(lint_log)
    print("Found {} total violations in log".format(len(violations)))
    
    # Read user hints
    with open(hints_file, 'r') as f:
        hints = f.readlines()
    
    # Find matching violations
    matches = find_matching_violations(violations, hints)
    
    if not matches:
        print("ERROR: No violations found matching your hints")
        print("Please check your code snippet and error code")
        sys.exit(1)
    
    print("\nMatched {} violation(s)".format(len(matches)))
    
    # Generate waiver XML
    waiver_xml = generate_waiver_xml(matches, author, reason)
    
    # Add to XML file
    success = add_waivers_to_xml(xml_file, waiver_xml)
    
    if not success:
        sys.exit(1)
    
    print("\nSuccessfully added {} waiver(s) to {}".format(len(matches), xml_file))
    print("\nWaivers generated for:")
    for v in matches:
        print("  - {} in {} line {}".format(v['error'], v['filename'], v['line']))
        # Don't print code snippet to avoid tcsh parsing issues with special characters

if __name__ == '__main__':
    main()
