#!/bin/bash
# Craigslist Search Script
# Usage: ./search.sh --query "search term" --location "eby/nby" --price-max 100

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --query) QUERY="$2"; shift ;;
        --location) LOCATION="$2"; shift ;;
        --price-max) PRICE_MAX="$2"; shift ;;
    esac
    shift
done

# Split location (expected "nby" or "eby")
IFS=',' read -ra LOCS <<< "$LOCATION"

for LOC in "${LOCS[@]}"; do
    echo "Searching ${LOC} Craigslist for ${QUERY} with max price ${PRICE_MAX}..."
    # Switch to 'sss' for "all sale items" which is usually more inclusive than just 'for'
    SEARCH_URL="https://sfbay.craigslist.org/search/${LOC}/sss?query=${QUERY// /+}&max_price=${PRICE_MAX}"
    
    echo "Strategy: Use web_search on OpenClaw with URL: ${SEARCH_URL}"
done

# Logging
mkdir -p ../data
echo "$(date): Search for '${QUERY}' in ${LOCATION} (max: ${PRICE_MAX})" >> ../data/search_history.log
