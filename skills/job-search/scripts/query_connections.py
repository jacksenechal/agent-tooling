"""
Query LinkedIn connections at a company from the ArcadeDB knowledge graph.

Usage:
    python3 query_connections.py "Company Name"

Run from your job-search repo root (or any directory — no relative paths needed).
"""

import os
import requests
import subprocess
import sys
from requests.auth import HTTPBasicAuth


def ensure_arcadedb():
    """Start the ArcadeDB container on demand and refresh its idle heartbeat."""
    ctl = os.path.join(os.path.dirname(os.path.abspath(__file__)), "arcadedb_ctl.sh")
    try:
        subprocess.run(["bash", ctl, "ensure"], check=True)
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        print(f"Warning: could not ensure ArcadeDB is running ({e}).", file=sys.stderr)


ARCADE_HOST = os.environ.get("ARCADE_HOST", "localhost")
ARCADE_PORT = int(os.environ.get("ARCADE_PORT", 2480))
ARCADE_USER = os.environ.get("ARCADE_USER", "root")
ARCADE_PASS = os.environ.get("ARCADE_PASS", "playwithdata")
DATABASE = os.environ.get("ARCADE_DATABASE", "KnowledgeGraph")

AUTH = HTTPBasicAuth(ARCADE_USER, ARCADE_PASS)
BASE_URL = f"http://{ARCADE_HOST}:{ARCADE_PORT}/api/v1"


def query_company(company_name):
    query = f"""
    MATCH (target:Company {{name: "{company_name}"}})<-[r:WORKED_AT]-(p:Person)
    MATCH (me:Person {{url: "me"}})-[c:CONNECTED_TO]->(p)
    RETURN DISTINCT p.name as name, p.current_title as title, p.warmth_score as score, p.url as url
    ORDER BY p.warmth_score DESC
    """

    url = f"{BASE_URL}/command/{DATABASE}"
    payload = {"language": "cypher", "command": query}

    response = requests.post(url, auth=AUTH, json=payload)
    if response.status_code != 200:
        print(f"Error running query for {company_name}")
        print(f"Response: {response.text}")
        return None

    return response.json().get("result", [])


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 query_connections.py <CompanyName>")
        sys.exit(1)

    company = sys.argv[1]
    ensure_arcadedb()
    results = query_company(company)

    if results:
        print(f"\nTop Connections at {company}:")
        print("-" * 90)
        print(f"{'Name':<25} | {'Score':<6} | {'Title':<35} | URL")
        print("-" * 90)
        for r in results:
            print(f"{r['name']:<25} | {r['score']:<6.1f} | {r.get('title', ''):<35} | {r.get('url', '')}")
    else:
        print(f"No connections found at {company}.")
