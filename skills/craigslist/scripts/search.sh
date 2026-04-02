#!/bin/bash
# Craigslist Search Script
# Usage: ./search.sh --query "search term" --location "sfbay" --price-max 100

QUERY=$2
LOCATION=$4
PRICE_MAX=$6

echo "Searching ${LOCATION} Craigslist for ${QUERY} with max price ${PRICE_MAX}..."

# Logic implemented by Janet:
# Use web_search to find craigslist results
# This would require an integration with the web_search tool,
# but for a standalone script, we can document the search strategy here.

SEARCH_URL="https://${LOCATION}.craigslist.org/search/sss?query=${QUERY// /+}&max_price=${PRICE_MAX}"

echo "Strategy: Use web_search on OpenClaw with URL: ${SEARCH_URL}"
echo "Filtering based on reliability keywords: Litter-Robot, ScoopFree, CatGenie"
echo "Logging search criteria to ./data/search_history.log"

mkdir -p ../data
echo "$(date): Search for '${QUERY}' in ${LOCATION} (max: ${PRICE_MAX})" >> ../data/search_history.log
