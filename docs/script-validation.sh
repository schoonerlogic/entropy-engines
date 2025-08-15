#!/bin/bash
# validate-terraform-templates.sh
# Validation script to check all Terraform template fixes

echo "🔍 Validating Terraform Template Fixes..."
echo "========================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ERRORS_FOUND=0

# Function to check for forbidden patterns
check_forbidden() {
    local pattern="$1"
    local description="$2"
    
    echo -n "Checking for $description... "
    
    local matches=$(grep -rn "$pattern" *.tftpl 2>/dev/null | wc -l)
    if [ $matches -gt 0 ]; then
        echo -e "${RED}FAILED${NC} ($matches found)"
        echo "  Found forbidden pattern '$pattern' in:"
        grep -rn "$pattern" *.tftpl 2>/dev/null | sed 's/^/    /'
        ERRORS_FOUND=$((ERRORS_FOUND + 1))
    else
        echo -e "${GREEN}PASSED${NC}"
    fi
}

# Function to check for required patterns
check_required() {
    local pattern="$1"
    local description="$2"
    local min_expected="$3"
    
    echo -n "Checking for $description... "
    
    local matches=$(grep -rn "$pattern" *.tftpl 2>/dev/null | wc -l)
    if [ $matches -lt $min_expected ]; then
        echo -e "${RED}FAILED${NC} ($matches found, expected at least $min_expected)"
        ERRORS_FOUND=$((ERRORS_FOUND + 1))
    else
        echo -e "${GREEN}PASSED${NC} ($matches found)"
    fi
}

echo "🚨 Checking for FORBIDDEN patterns (should be 0):"
echo "================================================"

# Check for parameter expansion patterns
check_forbidden '\${[^}]*:-' "parameter expansion with :-"
check_forbidden '\${[^}]*:=' "parameter expansion with :="
check_forbidden '\${[^}]*:+' "parameter expansion with :+"
check_forbidden '\${[^}]*\?' "parameter expansion with ?"

# Check for double bracket syntax
check_forbidden '\[\[' "double bracket syntax [[]]"

# Check for unquoted script dir
check_forbidden 'SCRIPT_DIR=\${script_dir}' "unquoted SCRIPT_DIR assignment"

# Check for typos
check_forbidden '\$[0-9]\{' "dollar-digit-brace typos"

echo ""
echo "✅ Checking for REQUIRED patterns (should exist):"
echo "================================================="

# Check for properly quoted script dir
check_required 'SCRIPT_DIR="\${script_dir}"' "quoted SCRIPT_DIR assignment" 5

# Check for escaped bash variables
check_required '\$\$\{' "escaped bash variables" 10

echo ""
echo "📊 Summary Report:"
echo "=================="

# Count files
local total_files=$(ls *.tftpl 2>/dev/null | wc -l)
echo "Total template files: $total_files"

# Count specific patterns
local escaped_vars=$(grep -rn '\$\$\{' *.tftpl 2>/dev/null | wc -l)
local quoted_dirs=$(grep -rn 'SCRIPT_DIR="\${script_dir}"' *.tftpl 2>/dev/null | wc -l)

echo "Escaped bash variables: $escaped_vars"
echo "Properly quoted SCRIPT_DIR: $quoted_dirs"

echo ""

if [ $ERRORS_FOUND -eq 0 ]; then
    echo -e "${GREEN}🎉 All validation checks PASSED!${NC}"
    echo -e "${GREEN}✅ Templates are ready for terraform plan${NC}"
    exit 0
else
    echo -e "${RED}❌ $ERRORS_FOUND validation errors found${NC}"
    echo -e "${RED}🚨 Fix the issues above before running terraform plan${NC}"
    exit 1
fi
