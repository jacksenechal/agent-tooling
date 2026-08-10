# Craigslist Skill

A generic skill for searching and (future) posting on Craigslist.

## Capability
- Search: Allows searching for items with specific keywords, geography, and price filters.
- Monitor: Can be used to set up recurring cron-based searches.

## Self-Improvement
This skill is designed to be self-improving. If a search yields results, the parameters and findings are logged in `data/search_history.log`. Whenever a search yields refined parameters, new reliable keywords, or a better way to filter out spam, update the logic in `scripts/search.sh` and document the learning here.

## How I Accomplish Searching
Searching is currently handled via the `web_search` tool mapped to Craigslist URLs (e.g., `https://${LOCATION}.craigslist.org/search/sss?query=${QUERY}&max_price=${PRICE_MAX}`). 
Reliability keywords (e.g., "Litter-Robot", "ScoopFree") are applied as filters on the results page to filter out irrelevant items.

## Improving Me (Placeholder)
- Roadmap: Add a "Posting" capability to automate creating Craigslist listings.

## Usage
- Search: `./scripts/search.sh --query "litter robot" --location "sfbay" --price-max 100`

---
*Maintained by Janet*
