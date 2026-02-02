#!/bin/bash

# Quick module search script
# Usage: ./tools/search-modules.sh [domain|feature|risk] [value]

if [ $# -ne 2 ]; then
    echo "Usage: $0 [domain|feature|risk] [value]"
    echo "Examples:"
    echo "  $0 domain pricing"  
    echo "  $0 feature bulk-price"
    echo "  $0 risk HIGH"
    exit 1
fi

SEARCH_TYPE=$1
SEARCH_VALUE=$2

case $SEARCH_TYPE in
    "domain")
        echo "🔍 Searching modules by domain: $SEARCH_VALUE"
        grep -r "@domain.*$SEARCH_VALUE" --include="*.js" --include="*.php" . | head -10
        ;;
    "feature") 
        echo "🔍 Searching modules by feature: $SEARCH_VALUE"
        grep -r "@feature.*$SEARCH_VALUE" --include="*.js" --include="*.php" . | head -10
        ;;
    "risk")
        echo "🔍 Searching modules by risk: $SEARCH_VALUE" 
        grep -r "@risk.*$SEARCH_VALUE" --include="*.js" --include="*.php" . | head -10
        ;;
    *)
        echo "Invalid search type. Use: domain, feature, or risk"
        exit 1
        ;;
esac