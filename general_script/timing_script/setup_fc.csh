#!/bin/csh
################################################################################
# Fusion Compiler Environment Setup (csh/tcsh)
# Usage: source setup_fc.csh
################################################################################

# FC Version - 2025.06-SP3 (compatible with current system libraries)
# Note: Your design used V-2023.12-SP5-6 but that version has library issues on this host
setenv FC_HOME /tool/cbar/apps/fusioncompiler/2025.06-SP3-DEV-20251215

# Alternative versions (may have library compatibility issues on this host):
# setenv FC_HOME /tool/cbar/apps/fusioncompiler/2023.12-SP5-6-20250422

# Add FC to PATH
setenv PATH ${FC_HOME}/bin:${PATH}

# Synopsys License (if needed)
# setenv SNPSLMD_LICENSE_FILE <your_license_server>

echo "=============================================="
echo "Fusion Compiler Environment Setup Complete"
echo "=============================================="
echo "FC_HOME: $FC_HOME"
echo ""
echo "To start fc_shell, run:"
echo "  fc_shell"
echo "=============================================="
