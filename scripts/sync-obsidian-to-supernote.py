#!/usr/bin/env python3

import argparse
import base64
import hashlib
import json
import mimetypes
import os
import re
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path, PurePosixPath


class Cloud:
    def __init__(self):
        self.base = os.environ.get("SUPERNOTE_API_BASE", "http://supernote-service:8080/api").rstrip("/")
        self.account = os.environ["SUPERNOTE_ACCOUNT"]
        self.password = base64.b64decode(os.environ["SUPERNOTE_PASSWORD_B64"]).decode()
        self.country = os.environ.get("SUPERNOTE_COUNTRY_CODE", "1")
        self.token = None

    def post(self, path, payload=None, body=None, content_type="application/json", timeout=120):
        if body is None:
            body = json.dumps(payload or {}).encode()
        headers = {"Content-Type": content_type, "User-Agent": "obsidian-supernote-bridge"}
        if self.token:
            headers["x-access-token"] = self.token
        request = urllib.request.Request(self.base + path, data=body, headers=headers, method="POST")
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            detail = error.read().decode(errors="replace")
            raise RuntimeError(f"http {error.code}: {detail[:300]}") from error

    def login(self):
        random_code = self.post("/official/user/query/random/code", {
            "countryCode": self.country,
            "account": self.account,
        })
        if not random_code.get("success"):
            raise RuntimeError(f"login setup failed: {random_code.get('errorCode')}")

        first_hash = hashlib.md5(self.password.encode()).hexdigest()
        password = hashlib.sha256(
            (first_hash + random_code["randomCode"]).encode()
        ).hexdigest()
        result = self.post("/official/user/account/login/new", {
            "countryCode": self.country,
            "account": self.account,
            "password": password,
            "browser": "unknown",
            "equipment": "1",
            "loginMethod": "1",
            "timestamp": random_code["timestamp"],
            "language": "en",
        })
        if result.get("mfaRequired"):
            raise RuntimeError("MFA is enabled; the bridge needs a dedicated app token")
        if not result.get("success") or not result.get("token"):
            raise RuntimeError(f"login failed: {result.get('errorCode') or result.get('errorMsg')}")
        self.token = result["token"]

    def list_dir(self, directory_id):
        result = self.post("/file/list/query", {
            "directoryId": directory_id,
            "pageNo": 1,
            "pageSize": 1000,
            "sequence": "asc",
            "order": "time",
        })
        if not result.get("success"):
            raise RuntimeError(f"folder listing failed: {result.get('errorCode')}")
        return result.get("userFileVOList", [])

    @staticmethod
    def is_folder(item):
        return item.get("isFolder") == "Y"

    def find_note_folder(self):
        queue = [(0, 0)]
        seen = set()
        while queue:
            directory_id, depth = queue.pop(0)
            if directory_id in seen:
                continue
            seen.add(directory_id)
            children = self.list_dir(directory_id)
            for item in children:
                if self.is_folder(item) and item.get("fileName") == "Note":
                    return item["id"]
            if depth < 2:
                queue.extend(
                    (item["id"], depth + 1)
                    for item in children
                    if self.is_folder(item)
                )
        raise RuntimeError("could not find the Supernote/Note folder")

    def ensure_dir(self, parent_id, name):
        children = self.list_dir(parent_id)
        for item in children:
            if item.get("fileName") == name:
                if not self.is_folder(item):
                    raise RuntimeError(f"remote path is a file: {name}")
                return item["id"]

        result = self.post("/file/folder/add", {"fileName": name, "directoryId": parent_id})
        if not result.get("success"):
            raise RuntimeError(f"folder create failed for {name}: {result.get('errorCode')}")
        for item in self.list_dir(parent_id):
            if item.get("fileName") == name and self.is_folder(item):
                return item["id"]
        raise RuntimeError(f"folder was created but not found: {name}")

    def upload(self, directory_id, name, data):
        md5 = hashlib.md5(data).hexdigest()
        result = self.post("/file/upload/apply", {
            "size": len(data),
            "fileName": name,
            "directoryId": directory_id,
            "md5": md5,
        })
        if result.get("errorCode") != "E0310":
            if not result.get("success"):
                raise RuntimeError(f"upload apply failed for {name}: {result.get('errorCode')}")
            self.upload_data(result["fullUploadUrl"], name, data)

        finish = self.post("/file/upload/finish", {
            "directoryId": directory_id,
            "fileName": name,
            "fileSize": len(data),
            "innerName": result["innerName"],
            "md5": md5,
        })
        if not finish.get("success"):
            raise RuntimeError(f"upload finish failed for {name}: {finish.get('errorCode')}")

    def upload_data(self, upload_url, name, data):
        match = re.search(r"/oss/upload\?.*", upload_url)
        if not match:
            raise RuntimeError("bad upload URL from Private Cloud")
        boundary = "----supernote-" + uuid.uuid4().hex
        safe_name = name.replace('"', "")
        mime = mimetypes.guess_type(name)[0] or "application/octet-stream"
        body = (
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="file"; filename="{safe_name}"\r\n'
            f"Content-Type: {mime}\r\n\r\n"
        ).encode() + data + f"\r\n--{boundary}--\r\n".encode()
        result = self.post(
            match.group(0),
            body=body,
            content_type=f"multipart/form-data; boundary={boundary}",
            timeout=1200,
        )
        if not result.get("success"):
            raise RuntimeError(f"data upload failed for {name}: {result.get('errorCode')}")


def markdown_pdf(path, vault):
    with tempfile.NamedTemporaryFile(suffix=".pdf") as output:
        subprocess.run([
            "pandoc",
            str(path),
            "--from=gfm",
            "--standalone",
            "--pdf-engine=weasyprint",
            f"--resource-path={path.parent}:{vault}",
            "--metadata",
            f"title={path.stem}",
            "--css=/app/markdown.css",
            "--output",
            output.name,
        ], check=True)
        return Path(output.name).read_bytes()


def remote_inventory(cloud, note_id):
    files = {}
    roots = {}
    seen = set()

    def walk(directory_id, prefix):
        if directory_id in seen:
            return
        seen.add(directory_id)
        for item in cloud.list_dir(directory_id):
            name = item.get("fileName", "")
            if not name or name in (".", "..") or "/" in name or "\\" in name:
                raise RuntimeError(f"unsafe remote name: {name!r}")
            path = prefix / name
            if cloud.is_folder(item):
                walk(item["id"], path)
            elif not name.lower().endswith(".mark"):
                files[str(path)] = {
                    "id": item["id"],
                    "md5": item.get("md5"),
                }

    for top in ("Classes", "Lab"):
        roots[top] = cloud.ensure_dir(note_id, top)
        walk(roots[top], PurePosixPath(top))
    return files, roots


def load_state(path):
    if not path.exists():
        return None
    state = json.loads(path.read_text())
    if state.get("version") != 1 or not isinstance(state.get("files"), dict):
        raise RuntimeError("bad deletion state")
    return state


def save_state(path, files):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(f"{path.name}.tmp.{os.getpid()}")
    temp.write_text(json.dumps({"version": 1, "files": files}, indent=2, sort_keys=True) + "\n")
    os.replace(temp, path)


def safe_local_path(vault, relative):
    path = PurePosixPath(relative)
    if path.is_absolute() or ".." in path.parts or not path.parts or path.parts[0] not in ("Classes", "Lab"):
        raise RuntimeError(f"unsafe local path: {relative}")
    return vault.joinpath(*path.parts)


def infer_source(vault, remote_path):
    remote = PurePosixPath(remote_path)
    exact = safe_local_path(vault, remote_path)
    if exact.exists():
        return str(remote)
    if remote.suffix.lower() == ".pdf":
        markdown = exact.with_suffix(".md")
        if markdown.exists():
            return str(remote.with_suffix(".md"))
    return None


def trash_local(vault, relative):
    source = safe_local_path(vault, relative)
    if not source.exists():
        return False
    stamp = time.strftime("%Y%m%d-%H%M%S")
    target = vault / ".trash" / "supernote" / stamp / PurePosixPath(relative)
    counter = 1
    while target.exists():
        target = target.with_name(f"{target.stem}-{counter}{target.suffix}")
        counter += 1
    target.parent.mkdir(parents=True, exist_ok=True)
    os.replace(source, target)
    print(f"delete: {relative} -> {target.relative_to(vault)}", flush=True)
    return True


def sync_once():
    vault = Path(os.environ.get("OBSIDIAN_VAULT_DIR", "/obsidian-vault"))
    state_path = Path(os.environ.get("SUPERNOTE_STATE_PATH", "/state/remote-files.json"))
    cloud = Cloud()
    cloud.login()
    note_id = cloud.find_note_folder()
    remote, roots = remote_inventory(cloud, note_id)
    saved = load_state(state_path)
    entries = saved["files"] if saved else {}
    uploaded = 0
    existing = 0
    deleted = 0

    if saved:
        for path in list(entries):
            entry = entries[path]
            if path in remote:
                entry.update(remote[path])
                entry["missing"] = 0
                if not entry.get("source"):
                    entry["source"] = infer_source(vault, path)
                continue
            entry["missing"] = int(entry.get("missing", 0)) + 1
            if entry["missing"] < 1:
                continue
            source = entry.get("source") or infer_source(vault, path)
            if source and trash_local(vault, source):
                deleted += 1
            entries.pop(path)
    else:
        print(f"baseline: {len(remote)} remote files", flush=True)

    local_sources = {}

    for top in ("Classes", "Lab"):
        local_root = vault / top
        if not local_root.is_dir():
            continue
        top_id = roots[top]
        directory_cache = {Path(): top_id}

        files = sorted(list(local_root.rglob("*.pdf")) + list(local_root.rglob("*.md")))
        for source in files:
            relative = source.relative_to(local_root)
            local_path = str(PurePosixPath(top, *relative.parts))
            remote_path = str(PurePosixPath(top, *relative.with_suffix(".pdf").parts))
            if remote_path in local_sources:
                continue
            local_sources[remote_path] = local_path
            entry = entries.get(remote_path)
            if entry and entry.get("missing", 0):
                continue
            parent = relative.parent
            if parent not in directory_cache:
                current_path = Path()
                current_id = top_id
                for part in parent.parts:
                    current_path /= part
                    if current_path not in directory_cache:
                        directory_cache[current_path] = cloud.ensure_dir(current_id, part)
                    current_id = directory_cache[current_path]

            directory_id = directory_cache[parent]
            remote_name = relative.with_suffix(".pdf").name
            if remote_path in remote:
                existing += 1
                continue

            data = markdown_pdf(source, vault) if source.suffix.lower() == ".md" else source.read_bytes()
            cloud.upload(directory_id, remote_name, data)
            print(f"upload: {top}/{relative} -> {remote_name}", flush=True)
            uploaded += 1

    remote, _ = remote_inventory(cloud, note_id)
    next_entries = {}
    for path, item in remote.items():
        old = entries.get(path, {})
        next_entries[path] = {
            **item,
            "missing": 0,
            "source": old.get("source") or local_sources.get(path) or infer_source(vault, path),
        }
    for path, entry in entries.items():
        if path not in remote and entry.get("missing", 0):
            next_entries[path] = entry
    save_state(state_path, next_entries)
    print(f"ok: {uploaded} uploaded, {existing} existing, {deleted} deleted", flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--loop", type=int)
    args = parser.parse_args()
    if not args.loop:
        sync_once()
        return

    while True:
        try:
            sync_once()
        except Exception as error:
            print(f"error: {error}", flush=True)
        time.sleep(args.loop)


if __name__ == "__main__":
    main()
