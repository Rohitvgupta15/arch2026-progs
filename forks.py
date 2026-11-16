"""List the forks of a GitHub repository into a CSV.

Usage:
    export GITHUB_TOKEN=ghp_...     # optional, raises the limit to 5000 req/h
    python3 forks.py
"""
import csv
import os
import time

import requests

REPO = "sysprog21/minirubik"
OUT = "minirubik_forks.csv"

session = requests.Session()
session.headers.update({
    "Accept": "application/vnd.github+json",
    "User-Agent": "fork-lister",
})
token = os.environ.get("GITHUB_TOKEN")
if token:
    session.headers["Authorization"] = f"Bearer {token}"


def get(url, **params):
    """GET with a wait-and-retry when the rate limit is hit."""
    while True:
        r = session.get(url, params=params, timeout=30)
        if r.status_code in (403, 429) and r.headers.get("X-RateLimit-Remaining") == "0":
            reset = int(r.headers.get("X-RateLimit-Reset", time.time() + 60))
            wait = max(reset - int(time.time()), 1) + 1
            print(f"Rate limited, waiting {wait}s ...")
            time.sleep(wait)
            continue
        r.raise_for_status()
        return r


forks = []
url = f"https://api.github.com/repos/{REPO}/forks"
params = {"per_page": 100, "sort": "oldest"}
while url:
    r = get(url, **params)
    forks.extend(r.json())
    url = r.links.get("next", {}).get("url")  # follow pagination
    params = {}  # the "next" URL already carries the query string

with open(OUT, "w", newline="", encoding="utf-8-sig") as f:
    w = csv.writer(f)
    w.writerow(["Username", "Fork", "Created", "Last push", "Stars"])
    for fk in forks:
        w.writerow([
            fk["owner"]["login"],
            fk["html_url"],
            fk["created_at"],
            fk["pushed_at"],
            fk["stargazers_count"],
        ])

print("Total forks:", len(forks))
print("CSV generated:", OUT)
