#!/usr/bin/env python
import re
import json
import shutil
import requests
import os
import hashlib
from sys import stderr
from requests.exceptions import RequestException


def fetch_manifest():
    manifest_hashes = {}
    manifest_url = "https://launchermeta.mojang.com/mc/game/version_manifest.json"
    print(f"fetching '{manifest_url}'...")
    response = get(manifest_url)
    for version in response.json()["versions"]:
        v = version["id"]
        url = version["url"]
        sha1_pattern = r"https://launchermeta.mojang.com/v1/packages/([^/]*)/.*.json"
        sha1 = re.match(sha1_pattern, url).group(1)
        manifest_hashes[v] = {"url": url, "sha1": sha1, "type": version["type"]}
    return manifest_hashes


def maintain_prefetched_files(directory, raw_prefetch_list):
    prefetch_list = normalize_prefetch_list(raw_prefetch_list)

    downloaded_filenames = os.listdir(directory)
    download_sha1_pattern = re.compile("(\w*)\.json")
    downloaded = [
        *map(
            lambda f: {"filename": f, "sha1": download_sha1_pattern.match(f).group(1)},
            downloaded_filenames,
        )
    ]
    for d in downloaded:
        path = os.path.join(directory, d["filename"])
        if sha1sum(path) != d["sha1"]:
            print(f"delete broken file '{path}'")
            downloaded.remove(d)
            os.remove(path)

    to_delete = []
    to_download = []

    hashes = set(map(lambda v: v["sha1"], prefetch_list))
    downloaded_hashes = set(map(lambda v: v["sha1"], downloaded))
    for d in downloaded:
        if d["sha1"] not in hashes:
            to_delete.append(d["filename"])
    for info in prefetch_list:
        if info["sha1"] not in downloaded_hashes:
            to_download.append(info)

    for hash in to_delete:
        path = os.path.join(directory, hash)
        print(f"delete '{path}'")
        os.remove(path)
    for info in to_download:
        path = os.path.join(directory, f"{info['sha1']}.json")
        url = info["url"]
        print(f"fetching '{path}' from '{url}'...")
        with get(url, stream=True) as r:
            with open(path, "wb") as f:
                shutil.copyfileobj(r.raw, f)
        if sha1sum(path) != info["sha1"]:
            raise RequestException(f"invalid content hash from {url}")


def get_prefetch_asset_indices(directory):
    assets_indices = []
    files = os.listdir(directory)
    for filename in files:
        path = os.path.join(directory, filename)
        with open(path, "r") as f:
            info = json.load(f)
            assets_indices.append(info["assetIndex"])
    return assets_indices


def get(url, *args, **kwargs):
    response = requests.get(url, *args, **kwargs)
    if response.status_code != 200:
        raise RequestException(f"{response.status_code} returned from {url}.")
    return response


def sha1sum(path):
    h = hashlib.sha1()
    with open(path, "rb") as file:
        while True:
            chunk = file.read(h.block_size)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def prefetch_filter(info):
    return info["type"] == "release"


def normalize_prefetch_list(prefetch_list):
    normalized = []
    for raw in prefetch_list:
        item = {
            'url': raw['url'],
            'sha1': raw['sha1']
        }
        if item not in normalized:
            normalized.append(item)
    return normalized

def main():
    try:
        manifest_hashes = fetch_manifest()
        with open("manifests.json", "w+") as f:
            json.dump(manifest_hashes, f, indent=2, sort_keys=True)

        versions_to_prefetch = [*filter(prefetch_filter, manifest_hashes.values())]
        maintain_prefetched_files("versions", versions_to_prefetch)
        asset_indices_to_prefetch = get_prefetch_asset_indices("versions")
        maintain_prefetched_files("asset_indices", asset_indices_to_prefetch)

    except RequestException as e:
        print(f"Update failed: {str(e)}", file=stderr)


if __name__ == "__main__":
    main()
