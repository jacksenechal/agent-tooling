"""
Ingest LinkedIn data exports into ArcadeDB knowledge graph.

Run from your job-search repo root so relative paths to data/linkedin/ resolve:
    cd ~/workspace/job-search
    python3 ~/workspace/agent-tools/skills/job-search-kg/scripts/ingest_linkedin.py --me-name "Your Full Name"

Your full name must match how your name appears in LinkedIn message exports
(used to determine message direction: Inbound vs. Outbound).
"""

import argparse
import csv
import requests
import math
import os
import io
import subprocess
import sys
from datetime import datetime
from requests.auth import HTTPBasicAuth


def ensure_arcadedb():
    """Start the ArcadeDB container on demand and refresh its idle heartbeat."""
    ctl = os.path.join(os.path.dirname(os.path.abspath(__file__)), "arcadedb_ctl.sh")
    try:
        subprocess.run(["bash", ctl, "ensure"], check=True)
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        print(f"Warning: could not ensure ArcadeDB is running ({e}).", file=sys.stderr)

# ArcadeDB configuration
ARCADE_HOST = os.environ.get("ARCADE_HOST", "localhost")
ARCADE_PORT = int(os.environ.get("ARCADE_PORT", 2480))
ARCADE_USER = os.environ.get("ARCADE_USER", "root")
ARCADE_PASS = os.environ.get("ARCADE_PASS", "playwithdata")
DATABASE = os.environ.get("ARCADE_DATABASE", "KnowledgeGraph")

AUTH = HTTPBasicAuth(ARCADE_USER, ARCADE_PASS)
BASE_URL = f"http://{ARCADE_HOST}:{ARCADE_PORT}/api/v1"


def run_command(command, database=DATABASE, ignore_error=False):
    url = f"{BASE_URL}/command/{database}"
    payload = {"language": "sql", "command": command}
    response = requests.post(url, auth=AUTH, json=payload)
    if response.status_code != 200:
        if not ignore_error:
            print(f"Error running command: {command[:100]}...")
            print(f"Response: {response.text}")
        return None
    return response.json()


def run_batch(commands, database=DATABASE):
    url = f"{BASE_URL}/command/{database}"
    script = ";\n".join(commands)
    payload = {"language": "sqlscript", "command": script}
    response = requests.post(url, auth=AUTH, json=payload)
    if response.status_code != 200:
        print("Error running batch script")
        print(f"Response: {response.text}")
        return None
    return response.json()


def safe_sql(val):
    if val is None:
        return ""
    return str(val).replace('"', '\\"')


def setup_schema():
    print("Setting up schema...")
    run_command("CREATE VERTEX TYPE Person", ignore_error=True)
    run_command("CREATE PROPERTY Person.url STRING", ignore_error=True)
    run_command("CREATE PROPERTY Person.name STRING", ignore_error=True)
    run_command("CREATE PROPERTY Person.warmth_score DOUBLE", ignore_error=True)
    run_command("CREATE INDEX ON Person (url) UNIQUE", ignore_error=True)

    run_command("CREATE VERTEX TYPE Company", ignore_error=True)
    run_command("CREATE PROPERTY Company.name STRING", ignore_error=True)
    run_command("CREATE INDEX ON Company (name) UNIQUE", ignore_error=True)

    run_command("CREATE VERTEX TYPE School", ignore_error=True)
    run_command("CREATE PROPERTY School.name STRING", ignore_error=True)
    run_command("CREATE INDEX ON School (name) UNIQUE", ignore_error=True)

    run_command("CREATE EDGE TYPE CONNECTED_TO", ignore_error=True)
    run_command("CREATE EDGE TYPE WORKED_AT", ignore_error=True)
    run_command("CREATE EDGE TYPE MESSAGED", ignore_error=True)
    run_command("CREATE EDGE TYPE STUDIED_AT", ignore_error=True)


def clear_data():
    print("Clearing existing data...")
    run_command("DELETE FROM MESSAGED")
    run_command("DELETE FROM STUDIED_AT")
    run_command("DELETE FROM WORKED_AT")
    run_command("DELETE FROM CONNECTED_TO")
    run_command("DELETE FROM Person")
    run_command("DELETE FROM Company")
    run_command("DELETE FROM School")


def ingest_data(me_name, data_dir):
    run_command(f'UPDATE Person SET name = "{safe_sql(me_name)}", url = "me" UPSERT WHERE url = "me"')

    my_companies = set()
    positions_path = os.path.join(data_dir, "Positions.csv")
    if os.path.exists(positions_path):
        print("Ingesting Positions...")
        with open(positions_path, mode="r", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            for row in reader:
                company_name = row["Company Name"]
                my_companies.add(company_name)
                s_company = safe_sql(company_name)
                run_command(f'UPDATE Company SET name = "{s_company}" UPSERT WHERE name = "{s_company}"')
                s_title = safe_sql(row["Title"])
                run_command(
                    f'CREATE EDGE WORKED_AT FROM (SELECT FROM Person WHERE url = "me") '
                    f'TO (SELECT FROM Company WHERE name = "{s_company}") '
                    f'SET title = "{s_title}", start_date = "{row["Started On"]}", end_date = "{row["Finished On"]}"'
                )

    education_path = os.path.join(data_dir, "Education.csv")
    if os.path.exists(education_path):
        print("Ingesting Education...")
        with open(education_path, mode="r", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            for row in reader:
                school_name = row.get("School Name", "").strip()
                if not school_name:
                    continue
                s_school = safe_sql(school_name)
                run_command(f'UPDATE School SET name = "{s_school}" UPSERT WHERE name = "{s_school}"')
                s_degree = safe_sql(row.get("Degree Name", ""))
                start = safe_sql(row.get("Start Date", ""))
                end = safe_sql(row.get("End Date", ""))
                run_command(
                    f'CREATE EDGE STUDIED_AT FROM (SELECT FROM Person WHERE url = "me") '
                    f'TO (SELECT FROM School WHERE name = "{s_school}") '
                    f'SET degree = "{s_degree}", start_date = "{start}", end_date = "{end}"'
                )

    connections_path = os.path.join(data_dir, "Connections.csv")
    connections_by_name = {}
    connections_by_url = {}
    if os.path.exists(connections_path):
        print("Ingesting Connections...")
        with open(connections_path, mode="r", encoding="utf-8") as f:
            lines = f.readlines()
            header_line_idx = 0
            for i, line in enumerate(lines):
                if "First Name" in line:
                    header_line_idx = i
                    break

            content = "".join(lines[header_line_idx:])
            reader = csv.DictReader(io.StringIO(content))

            for row in reader:
                if not row.get("First Name"):
                    continue
                name = f"{row['First Name']} {row['Last Name']}".strip()
                url = row["URL"]
                company = row["Company"]
                position = row["Position"]
                connected_on = row["Connected On"]

                connections_by_url[url] = {
                    "name": name,
                    "company": company,
                    "position": position,
                    "connected_on": connected_on,
                    "msg_count": 0,
                    "last_msg_date": None,
                }
                if name in connections_by_name:
                    connections_by_name[name] = None  # ambiguous — skip in message matching
                else:
                    connections_by_name[name] = url

                s_name = safe_sql(name)
                s_position = safe_sql(position)
                s_url = safe_sql(url)
                run_command(
                    f'UPDATE Person SET name = "{s_name}", url = "{s_url}", '
                    f'current_title = "{s_position}", connection_date = "{connected_on}" '
                    f'UPSERT WHERE url = "{s_url}"'
                )

                if company:
                    s_company = safe_sql(company)
                    run_command(f'UPDATE Company SET name = "{s_company}" UPSERT WHERE name = "{s_company}"')
                    run_command(
                        f'CREATE EDGE WORKED_AT FROM (SELECT FROM Person WHERE url = "{s_url}") '
                        f'TO (SELECT FROM Company WHERE name = "{s_company}") '
                        f'SET title = "{s_position}", is_current = true'
                    )

                run_command(
                    f'CREATE EDGE CONNECTED_TO FROM (SELECT FROM Person WHERE url = "me") '
                    f'TO (SELECT FROM Person WHERE url = "{s_url}") '
                    f'SET source = "LinkedIn", date = "{connected_on}"'
                )

    messages_path = os.path.join(data_dir, "Messages.csv")
    if os.path.exists(messages_path):
        print("Ingesting Messages (this may take a while)...")
        with open(messages_path, mode="r", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            batch_commands = []
            count = 0
            for row in reader:
                sender = row["FROM"]
                receiver = row["TO"]
                date_str = row["DATE"].replace(" UTC", "")
                connection_name = sender if sender != me_name else receiver

                target_url = connections_by_name.get(connection_name)
                if target_url:
                    cdata = connections_by_url[target_url]
                    cdata["msg_count"] += 1
                    try:
                        msg_date = datetime.strptime(date_str, "%Y-%m-%d %H:%M:%S")
                        if not cdata["last_msg_date"] or msg_date > cdata["last_msg_date"]:
                            cdata["last_msg_date"] = msg_date
                    except ValueError:
                        pass

                    s_target_url = safe_sql(target_url)
                    direction = "Inbound" if sender != me_name else "Outbound"
                    batch_commands.append(
                        f'CREATE EDGE MESSAGED FROM (SELECT FROM Person WHERE url = "me") '
                        f'TO (SELECT FROM Person WHERE url = "{s_target_url}") '
                        f'SET timestamp = "{date_str}", direction = "{direction}"'
                    )
                    count += 1

                    if len(batch_commands) >= 100:
                        if run_batch(batch_commands) is None:
                            print(f"  Warning: batch failed near message {count}")
                        batch_commands = []
                        if count % 500 == 0:
                            print(f"  Ingested {count} messages...")

            if batch_commands:
                run_batch(batch_commands)
            if count:
                print(f"  Total: {count} messages ingested.")

    print("Calculating warmth scores...")
    now = datetime.now()
    for url, cdata in connections_by_url.items():
        warmth = 0
        msg_score = math.log(cdata["msg_count"] + 1) * 20
        warmth += msg_score

        if cdata["company"] in my_companies:
            warmth += 15

        if cdata["last_msg_date"]:
            months_since = (now.year - cdata["last_msg_date"].year) * 12 + (
                now.month - cdata["last_msg_date"].month
            )
            decay = math.pow(0.9, max(0, months_since))
            warmth += 20 * decay

        try:
            conn_date = datetime.strptime(cdata["connected_on"], "%d %b %Y")
            years = now.year - conn_date.year
            warmth += max(0, years)
        except ValueError:
            pass

        s_url = safe_sql(url)
        run_command(f'UPDATE Person SET warmth_score = {warmth} WHERE url = "{s_url}"')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Ingest LinkedIn CSV exports into ArcadeDB knowledge graph."
    )
    parser.add_argument(
        "--me-name",
        required=True,
        help='Your full name as it appears in LinkedIn messages (e.g., "Jane Smith")',
    )
    parser.add_argument(
        "--data-dir",
        default="data/linkedin",
        help="Directory containing LinkedIn CSV exports (default: data/linkedin)",
    )
    args = parser.parse_args()

    ensure_arcadedb()
    setup_schema()
    clear_data()
    ingest_data(args.me_name, args.data_dir)
    print("Ingestion complete.")
