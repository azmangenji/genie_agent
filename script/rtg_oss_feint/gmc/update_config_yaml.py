#!/usr/bin/env python
"""
Update CDC YAML config file with proper indentation preservation
Usage: update_config_yaml.py <yaml_file> <config_file>
"""

import sys
import re

def update_yaml_config(yaml_file, config_file):
    """Update YAML file with config variables, preserving indentation"""
    
    # Read the YAML file
    with open(yaml_file, 'r') as f:
        yaml_lines = f.readlines()
    
    # Read the config updates
    with open(config_file, 'r') as f:
        config_updates = f.readlines()
    
    # Process each config update
    for config_line in config_updates:
        config_line = config_line.strip()
        if not config_line or ':' not in config_line:
            continue
            
        # Extract variable name and value
        var_name = config_line.split(':', 1)[0].strip()
        var_value = config_line.split(':', 1)[1].strip()
        
        # Find and replace in YAML
        found = False
        for i, line in enumerate(yaml_lines):
            # Match lines with whitespace + variable name + colon
            match = re.match(r'^(\s+)' + re.escape(var_name) + r':', line)
            if match:
                # Preserve the original indentation
                indent = match.group(1)
                yaml_lines[i] = "{0}{1}: {2}\n".format(indent, var_name, var_value)
                print("# Replaced {0} with value: {1}".format(var_name, var_value))
                found = True
                break
        
        if not found:
            # Variable doesn't exist - insert after FLOW_SETTINGS:
            for i, line in enumerate(yaml_lines):
                if line.strip() == 'FLOW_SETTINGS:':
                    # Insert with proper indentation (1 space)
                    yaml_lines.insert(i + 1, " {0}: {1}\n".format(var_name, var_value))
                    print("# Inserted {0} after FLOW_SETTINGS:".format(var_name))
                    break
    
    # Write back the updated YAML
    with open(yaml_file, 'w') as f:
        f.writelines(yaml_lines)
    
    print("# YAML config updated successfully")

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: update_config_yaml.py <yaml_file> <config_file>")
        sys.exit(1)
    
    yaml_file = sys.argv[1]
    config_file = sys.argv[2]
    
    update_yaml_config(yaml_file, config_file)
