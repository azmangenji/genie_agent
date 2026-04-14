#!/bin/bash
################################################################################
# Fusion Compiler Environment Setup
# Usage: source setup_fc.sh
################################################################################

# FC Version - 2023.12-SP5-6 (matching DSO permutons)
export FC_HOME=/tool/cbar/apps/fusioncompiler/2023.12-SP5-6-20250422

# Alternative: Use latest validated version
# export FC_HOME=/tool/cbar/apps/fusioncompiler/2023.12-SP5-VAL-20260107

# Add FC to PATH
export PATH=$FC_HOME/bin:$PATH

# Synopsys License (if needed)
# export SNPSLMD_LICENSE_FILE=<your_license_server>

echo "=============================================="
echo "Fusion Compiler Environment Setup Complete"
echo "=============================================="
echo "FC_HOME: $FC_HOME"
echo "Version: $(basename $FC_HOME)"
echo ""
echo "To start fc_shell, run:"
echo "  fc_shell"
echo "=============================================="
