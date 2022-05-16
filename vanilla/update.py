#!/usr/bin/env python
import re
import json
import requests
from sys import stderr
from requests.exceptions import RequestException

manifest_hashes = {}

try:
    response = requests.get("https://launchermeta.mojang.com/mc/game/version_manifest.json")
    if response.status_code == 200:
        for version in response.json()["versions"]:
            v = version["id"]
            url = version["url"]
            print(f"URL: {url}")
            sha1_pattern = r"https://launchermeta.mojang.com/v1/packages/([^/]*)/.*.json"
            sha1 = re.match(sha1_pattern, url).group(1)
            manifest_hashes[v] = { 'url': url, 'sha1': sha1 }
        with open("manifests.json", 'w+') as f:
            json.dump(manifest_hashes, f, indent=2, sort_keys=True)
    else:
        raise RequestException(f"{response.status_code} returned from {url}.")
except RequestException as e:
    print(f"Update failed: {str(e)}", file=stderr)
