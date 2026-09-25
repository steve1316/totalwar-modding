"""Content-addressed cache for `rpfm_cli pack extract` results.

Every extraction is keyed by the SHA-256 of the source pack plus the rpfm toolchain (schema + exe) and the extract arguments. An unchanged pack is served
from `extract_cache/` with a file copy instead of an rpfm subprocess. Pack hashes are remembered in a manifest so a pack is only rehashed when its size or
mtime changes.

Set the `EXTRACT_CACHE=0` environment variable to bypass reading and writing cache entries. When `DELTA_ACCESS_LOG` is set, every extraction is appended to
that file as a JSON line so `delta.py` can later tell which packs and tables a script actually depended on.
"""

import hashlib
import json
import logging
import os
import shutil
import subprocess
import threading
import uuid
from typing import Any, Dict, List, Optional


CACHE_ROOT = "./extract_cache"
OBJECTS_ROOT = f"{CACHE_ROOT}/objects"
STAGING_ROOT = f"{CACHE_ROOT}/staging"
MANIFEST_PATH = f"{CACHE_ROOT}/pack_hashes.json"
RPFM_CLI_PATH = "./rpfm_cli.exe"
SCHEMA_RON_PATH = "./schemas/schema_wh3.ron"

_LOCK = threading.Lock()
_MANIFEST: Optional[Dict[str, Dict[str, Any]]] = None
_RUN_MEMO: Dict[str, str] = {}
_TOOLCHAIN_HASH: Optional[str] = None


def cache_enabled() -> bool:
    """Return whether cache entries may be read and written for this process.

    Returns:
        False when the `EXTRACT_CACHE` environment variable is `0`, True otherwise.
    """
    return os.environ.get("EXTRACT_CACHE", "1") != "0"


def normalize_path(path: str) -> str:
    """Normalize a filesystem path so the same pack always maps to the same manifest key.

    Args:
        path (str): Any absolute or relative path, with either slash style.

    Returns:
        The absolute, case-normalized path.
    """
    return os.path.normcase(os.path.abspath(path))


def file_sha256(path: str) -> str:
    """Hash a file's bytes with SHA-256.

    Args:
        path (str): Path to the file.

    Returns:
        The hex digest.
    """
    with open(path, "rb") as f:
        return hashlib.file_digest(f, "sha256").hexdigest()


def tree_sha256(path: str) -> str:
    """Hash a file or a directory tree (relative paths plus file bytes) with SHA-256.

    Args:
        path (str): A file or directory. A missing path hashes to the digest of the string `missing`.

    Returns:
        The hex digest.
    """
    digest = hashlib.sha256()
    if not os.path.exists(path):
        digest.update(b"missing")
    elif os.path.isfile(path):
        digest.update(file_sha256(path).encode())
    else:
        for root, dirs, files in os.walk(path):
            dirs.sort()
            for name in sorted(files):
                file_path = os.path.join(root, name)
                digest.update(os.path.relpath(file_path, path).replace("\\", "/").encode("utf-8"))
                digest.update(b"\0")
                digest.update(file_sha256(file_path).encode())
                digest.update(b"\0")
    return digest.hexdigest()


def _load_manifest() -> Dict[str, Dict[str, Any]]:
    """Load the pack hash manifest from disk once per process. Must be called with `_LOCK` held.

    Returns:
        The manifest dict mapping normalized pack path to `{size, mtime_ns, sha256}`.
    """
    global _MANIFEST
    if _MANIFEST is None:
        try:
            with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
                _MANIFEST = json.load(f)
        except (FileNotFoundError, json.JSONDecodeError):
            _MANIFEST = {}
    return _MANIFEST


def _save_manifest() -> None:
    """Atomically write the in-memory manifest back to disk. Must be called with `_LOCK` held."""
    os.makedirs(CACHE_ROOT, exist_ok=True)
    tmp_path = f"{MANIFEST_PATH}.{uuid.uuid4().hex}.tmp"
    with open(tmp_path, "w", encoding="utf-8") as f:
        json.dump(_MANIFEST, f, indent=1, sort_keys=True)
    os.replace(tmp_path, MANIFEST_PATH)


def pack_sha256(pack_path: str) -> Optional[str]:
    """Return the SHA-256 of a pack, reusing the manifest entry when the file's size and mtime are unchanged.

    Args:
        pack_path (str): Path to the `.pack` file.

    Returns:
        The hex digest, or None if the file does not exist.
    """
    if not pack_path or not os.path.isfile(pack_path):
        return None
    key = normalize_path(pack_path)
    stat = os.stat(pack_path)
    with _LOCK:
        manifest = _load_manifest()
        memo = _RUN_MEMO.get(key)
        entry = manifest.get(key)
        if entry and entry["size"] == stat.st_size and entry["mtime_ns"] == stat.st_mtime_ns:
            if memo is None or memo == entry["sha256"]:
                _RUN_MEMO[key] = entry["sha256"]
                return entry["sha256"]

    logging.info(f"Hashing {os.path.basename(pack_path)} ({round(stat.st_size / 1e6, 1)} MB)...")
    sha = file_sha256(pack_path)
    with _LOCK:
        manifest = _load_manifest()
        manifest[key] = {"size": stat.st_size, "mtime_ns": stat.st_mtime_ns, "sha256": sha}
        _RUN_MEMO[key] = sha
        _save_manifest()
    return sha


def toolchain_hash() -> str:
    """Hash the rpfm schema and executable so a schema or rpfm update invalidates every cache entry.

    Returns:
        The hex digest, memoized for the process.
    """
    global _TOOLCHAIN_HASH
    if _TOOLCHAIN_HASH is None:
        digest = hashlib.sha256()
        for path in (SCHEMA_RON_PATH, RPFM_CLI_PATH):
            digest.update(file_sha256(path).encode() if os.path.exists(path) else b"missing")
        _TOOLCHAIN_HASH = digest.hexdigest()
    return _TOOLCHAIN_HASH


def _entry_dir(pack_sha: str, source_kind: str, source: str, tables_as_tsv: bool) -> str:
    """Build the cache entry directory for one extraction.

    Args:
        pack_sha (str): SHA-256 of the source pack.
        source_kind (str): `folder` or `file`, matching rpfm's `--folder-path` / `--file-path`.
        source (str): Pack-relative path being extracted.
        tables_as_tsv (bool): Whether tables are converted to TSV.

    Returns:
        Path of the entry directory, grouped by pack hash so stale packs can be pruned as a unit.
    """
    arg_key = hashlib.sha256(json.dumps([toolchain_hash(), source_kind, source, tables_as_tsv]).encode()).hexdigest()
    return f"{OBJECTS_ROOT}/{pack_sha[:24]}/{arg_key[:24]}"


def _run_extract(pack_path: str, source_kind: str, source: str, tables_as_tsv: bool, staging: str, capture_output: bool) -> int:
    """Run one rpfm extraction into a staging directory.

    Args:
        pack_path (str): Path to the `.pack` file.
        source_kind (str): `folder` or `file`.
        source (str): Pack-relative path being extracted.
        tables_as_tsv (bool): Whether tables are converted to TSV.
        staging (str): Relative destination directory. rpfm cannot parse drive-letter paths after the `;` separator.
        capture_output (bool): Capture rpfm's stdout/stderr instead of inheriting them.

    Returns:
        The rpfm exit code.
    """
    args = [RPFM_CLI_PATH, "--game", "warhammer_3", "pack", "extract", "--pack-path", pack_path]
    if tables_as_tsv:
        args += ["--tables-as-tsv", SCHEMA_RON_PATH]
    args += [f"--{source_kind}-path", f"{source};{staging}"]
    return subprocess.run(args, capture_output=capture_output).returncode


def _record_access(record: Dict[str, Any]) -> None:
    """Append one extraction record to the `DELTA_ACCESS_LOG` file when that variable is set.

    Args:
        record (Dict[str, Any]): JSON-serializable description of the extraction.
    """
    log_path = os.environ.get("DELTA_ACCESS_LOG")
    if not log_path:
        return
    with _LOCK:
        with open(log_path, "a", encoding="utf-8") as f:
            f.write(json.dumps(record, sort_keys=True) + "\n")


def ensure_extracted(pack_path: str, source: str, source_kind: str = "folder", tables_as_tsv: bool = True, capture_output: bool = False) -> Optional[Dict[str, Any]]:
    """Make sure an extraction exists in the cache and return its metadata, running rpfm only on a cache miss.

    Args:
        pack_path (str): Path to the `.pack` file.
        source (str): Pack-relative path being extracted, e.g. `db/land_units_tables`.
        source_kind (str): `folder` or `file`. Defaults to `folder`.
        tables_as_tsv (bool): Whether tables are converted to TSV. Defaults to True.
        capture_output (bool): Capture rpfm's stdout/stderr. Defaults to False.

    Returns:
        A dict with `pack_sha`, `content_sha`, `produced` (whether rpfm created the destination) and `tree` (cached tree path, or None when the result
        was not cached because caching is disabled or rpfm failed). Returns None if the pack does not exist.
    """
    pack_sha = pack_sha256(pack_path)
    if pack_sha is None:
        return None

    entry = _entry_dir(pack_sha, source_kind, source, tables_as_tsv)
    meta_path = f"{entry}/meta.json"
    if cache_enabled() and os.path.exists(meta_path):
        with open(meta_path, "r", encoding="utf-8") as f:
            meta = json.load(f)
        return {"pack_sha": pack_sha, "content_sha": meta["content_sha"], "produced": meta["produced"], "tree": f"{entry}/tree"}

    staging = f"{STAGING_ROOT}/{uuid.uuid4().hex}"
    os.makedirs(STAGING_ROOT, exist_ok=True)
    return_code = _run_extract(pack_path, source_kind, source, tables_as_tsv, staging, capture_output)
    produced = os.path.exists(staging)
    result = {"pack_sha": pack_sha, "content_sha": tree_sha256(staging), "produced": produced, "tree": None, "staging": staging}

    if cache_enabled() and return_code == 0:
        tree = f"{entry}/tree"
        with _LOCK:
            os.makedirs(entry, exist_ok=True)
            if not os.path.exists(meta_path):
                if os.path.exists(tree):
                    shutil.rmtree(tree)
                if produced:
                    os.replace(staging, tree)
                with open(meta_path, "w", encoding="utf-8") as f:
                    json.dump({"content_sha": result["content_sha"], "produced": produced, "pack": normalize_path(pack_path), "source": source}, f)
            else:
                shutil.rmtree(staging, ignore_errors=True)
        result["tree"] = tree
        result.pop("staging")
    elif return_code != 0:
        logging.warning(f"rpfm exited with {return_code} extracting {source} from {os.path.basename(pack_path)}. The result was not cached.")
    return result


def cached_pack_extract(pack_path: str, source: str, dest: str, source_kind: str = "folder", tables_as_tsv: bool = True, capture_output: bool = False) -> None:
    """Drop-in replacement for `rpfm_cli pack extract` that serves unchanged packs from the cache.

    The result in `dest` matches what rpfm would have produced: files are merged into `dest`, and `dest` is not created when the pack has nothing at `source`.

    Args:
        pack_path (str): Path to the `.pack` file.
        source (str): Pack-relative path being extracted, e.g. `db/land_units_tables` or `db/land_units_tables/data__`.
        dest (str): Local destination directory.
        source_kind (str): `folder` or `file`. Defaults to `folder`.
        tables_as_tsv (bool): Whether tables are converted to TSV. Defaults to True.
        capture_output (bool): Capture rpfm's stdout/stderr on a cache miss. Defaults to False.
    """
    access = {"pack": normalize_path(pack_path) if pack_path else "", "source": source, "source_kind": source_kind, "tables_as_tsv": tables_as_tsv}
    result = ensure_extracted(pack_path, source, source_kind, tables_as_tsv, capture_output)
    if result is None:
        _record_access({**access, "missing": True})
        return
    _record_access({**access, "pack_sha": result["pack_sha"], "content_sha": result["content_sha"]})

    # rpfm leaves no destination folder when the pack has nothing at `source`, and callers rely on that to detect missing tables.
    if not result["produced"]:
        return
    if result["tree"] is not None:
        shutil.copytree(result["tree"], dest, dirs_exist_ok=True)
    else:
        shutil.copytree(result["staging"], dest, dirs_exist_ok=True)
        shutil.rmtree(result["staging"], ignore_errors=True)


def prune_cache(keep_pack_shas: List[str]) -> int:
    """Delete cached extractions for packs whose hash is no longer referenced.

    Args:
        keep_pack_shas (List[str]): Full pack SHA-256 digests that are still in use.

    Returns:
        The number of pack groups removed.
    """
    if not os.path.exists(OBJECTS_ROOT):
        return 0
    keep = {sha[:24] for sha in keep_pack_shas}
    removed = 0
    for name in os.listdir(OBJECTS_ROOT):
        if name not in keep:
            shutil.rmtree(f"{OBJECTS_ROOT}/{name}", ignore_errors=True)
            removed += 1
    shutil.rmtree(STAGING_ROOT, ignore_errors=True)
    return removed
