#!/usr/bin/env python3
"""Update nix/sources.json to the latest ArtCraft releases on GitHub.

    nix run .#update                    # every app in nix/apps.nix
    nix run .#update -- photocraft      # only some
    nix run .#update -- --force         # re-pin even when the version is unchanged

Run it from a checkout of this flake (it edits nix/sources.json in the working tree and builds
`.#<app>-source.cargoDeps` to learn each cargoHash). For each app whose latest release differs
from the pinned one it records:

  * the release tag, its commit and date;
  * the x86_64/aarch64 AppImages (hashes from the GitHub release asset digests);
  * the source tarball hash and the Cargo vendor hash;
  * the craft-fonts / craft-i18n revisions the release workflow builds with;
  * files the Linux packaging downloads (ATTRIBUTION.toml `[[fetched]]` models), so the
    sandboxed source build can serve them offline.

Needs python3 (3.11+), nix and git. Set GITHUB_TOKEN to lift the API rate limit. Prints one line
per updated app and exits non-zero if any app failed (its previous pin is kept).
"""

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import tomllib
import urllib.request
from pathlib import Path

OWNER = "storytold"
SYSTEMS = {"x86_64-linux": "x86_64", "aarch64-linux": "aarch64"}
FAKE_HASH = "sha256-" + "A" * 43 + "="
# Apps whose release.yml sets no craft-fonts-ref build with the suite default declared here.
COMMON_RELEASE_WORKFLOW = f"repos/{OWNER}/craft-common-actions/contents/.github/workflows/release.yml"
NIX = ["nix", "--extra-experimental-features", "nix-command flakes"]


def log(msg: str) -> None:
    print(msg, file=sys.stderr, flush=True)


def run(cmd: list[str], **kwargs) -> str:
    return subprocess.run(cmd, check=True, text=True, stdout=subprocess.PIPE, **kwargs).stdout


def github(path: str, raw: bool = False):
    req = urllib.request.Request(f"https://api.github.com/{path}")
    req.add_header("Accept", "application/vnd.github.raw" if raw else "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    if token := os.environ.get("GITHUB_TOKEN"):
        req.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(req, timeout=60) as resp:
        body = resp.read().decode()
    return body if raw else json.loads(body)


def sri_from_hex(digest: str) -> str:
    return "sha256-" + base64.b64encode(bytes.fromhex(digest)).decode()


def to_sri(nix_hash: str) -> str:
    return run(NIX + ["hash", "convert", "--hash-algo", "sha256", "--to", "sri", nix_hash]).strip()


def prefetch_url(url: str, unpack: bool = False) -> tuple[str, Path]:
    """Hash as fetchurl (or fetchzip/fetchFromGitHub with unpack) computes it, plus the store path."""
    cmd = ["nix-prefetch-url", "--type", "sha256", "--print-path"] + (["--unpack"] if unpack else []) + [url]
    nix_hash, path = run(cmd, stderr=subprocess.DEVNULL).split()
    return to_sri(nix_hash), Path(path)


def prefetch_github(repo: str, rev: str) -> tuple[dict, Path]:
    sri, path = prefetch_url(f"https://github.com/{OWNER}/{repo}/archive/{rev}.tar.gz", unpack=True)
    return {"rev": rev, "hash": sri}, path


class Updater:
    def __init__(self, root: Path):
        self.root = root
        self.sources_path = root / "nix" / "sources.json"
        self.sources = json.loads(self.sources_path.read_text()) if self.sources_path.exists() else {}
        self.sources.setdefault("apps", {})
        self._pins: dict[tuple[str, str], dict] = {}
        self._suite_fonts_ref: str | None = None

    def save(self) -> None:
        self.sources_path.write_text(json.dumps(self.sources, indent=2, sort_keys=True) + "\n")

    def pin(self, repo: str, rev: str) -> dict:
        """fetchFromGitHub pin for a helper repository, reusing hashes already in sources.json."""
        if (repo, rev) not in self._pins:
            key = {"craft-fonts": "craftFonts", "craft-i18n": "craftI18n"}[repo]
            known = [a[key] for a in self.sources["apps"].values() if a.get(key) and a[key]["rev"] == rev]
            self._pins[(repo, rev)] = known[0] if known else prefetch_github(repo, rev)[0]
        return self._pins[(repo, rev)]

    def suite_fonts_ref(self) -> str | None:
        if self._suite_fonts_ref is None:
            workflow = github(COMMON_RELEASE_WORKFLOW, raw=True)
            self._suite_fonts_ref = workflow_default(workflow, "craft-fonts-ref") or ""
        return self._suite_fonts_ref or None

    def fonts_ref(self, src: Path) -> str | None:
        release = src / ".github" / "workflows" / "release.yml"
        text = release.read_text() if release.exists() else ""
        match = re.search(r"^\s+craft-fonts-ref:[ \t]*(\S*)", text, re.M)
        if not match:
            return self.suite_fonts_ref()
        value = match.group(1).strip("'\"")
        return value or None

    def update_app(self, app: str, force: bool) -> str | None:
        old = self.sources["apps"].get(app)
        release = github(f"repos/{OWNER}/{app}/releases/latest")
        tag = release["tag_name"]
        version = tag.removeprefix("v")
        if old and old["version"] == version and not force:
            return None
        log(f"{app}: pinning {tag}")
        rev = github(f"repos/{OWNER}/{app}/commits/{tag}")["sha"]
        src, src_path = prefetch_github(app, rev)
        del src["rev"]

        appimage = {}
        assets = {a["name"]: a for a in release["assets"]}
        for system, arch in SYSTEMS.items():
            asset = assets.get(f"{app}-{version}-linux-{arch}.AppImage")
            if asset is None:
                log(f"{app}: release {tag} has no {arch} AppImage")
                continue
            url = asset["browser_download_url"]
            digest = asset.get("digest") or ""
            hash_ = sri_from_hex(digest.removeprefix("sha256:")) if digest.startswith("sha256:") else prefetch_url(url)[0]
            appimage[system] = {"url": url, "hash": hash_}

        fonts = self.fonts_ref(src_path)
        i18n_file = src_path / "craft-i18n.rev"
        i18n = i18n_file.read_text().strip() if i18n_file.exists() else None

        entry = {
            "version": version,
            "tag": tag,
            "date": release["published_at"][:10],
            "src": {"rev": rev, **src},
            "cargoHash": FAKE_HASH,
            "appimage": appimage,
            "craftFonts": self.pin("craft-fonts", fonts) if fonts else None,
            "craftI18n": self.pin("craft-i18n", i18n) if i18n else None,
            "fetched": fetched_files(src_path),
        }
        self.sources["apps"][app] = entry
        self.save()
        entry["cargoHash"] = self.cargo_hash(app)
        self.save()
        return f"{app}: {old['version'] if old else '(new)'} -> {version}"

    def cargo_hash(self, app: str) -> str:
        """Build the vendor directory with a fake hash; Nix reports the real one."""
        proc = subprocess.run(
            NIX + ["build", "--no-link", f"{self.root}#{app}-source.cargoDeps"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        match = re.search(r"got:\s+(sha256-[A-Za-z0-9+/]+=*)", proc.stderr)
        if not match:
            raise RuntimeError(f"could not determine the cargoHash of {app}:\n{proc.stderr[-4000:]}")
        return match.group(1)


def workflow_default(workflow: str, name: str) -> str | None:
    """`default:` of a workflow_call input, e.g. craft-fonts-ref's pinned commit."""
    lines = workflow.splitlines()
    for i, line in enumerate(lines):
        if re.match(rf"^\s+{re.escape(name)}:\s*$", line):
            indent = len(line) - len(line.lstrip())
            for following in lines[i + 1 :]:
                if following.strip() and len(following) - len(following.lstrip()) <= indent:
                    break
                if match := re.match(r"^\s+default:\s*['\"]?([^'\"\s]*)", following):
                    return match.group(1)
    return None


def fetched_files(src: Path) -> list[dict]:
    """Models (and their licences) package.sh downloads via `cargo xtask models`."""
    manifest = src / "ATTRIBUTION.toml"
    if not manifest.exists():
        return []
    files = {}
    for entry in tomllib.loads(manifest.read_text()).get("fetched", []):
        if entry.get("kind") != "model":
            continue
        files[entry["url"]] = sri_from_hex(entry["sha256"])
        files[entry["licence_url"]] = sri_from_hex(entry["licence_sha256"])
    return [{"url": url, "hash": hash_} for url, hash_ in sorted(files.items())]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("apps", nargs="*", help="apps to update (default: all in nix/apps.nix)")
    parser.add_argument("--force", action="store_true", help="re-pin apps whose version is unchanged")
    args = parser.parse_args()

    root = Path(run(["git", "rev-parse", "--show-toplevel"]).strip())
    known = json.loads(run(NIX + ["eval", "--json", "--file", str(root / "nix" / "apps.nix"), "--apply", "builtins.attrNames"]))
    unknown = sorted(set(args.apps) - set(known))
    if unknown:
        parser.error(f"unknown app(s): {', '.join(unknown)}; known: {', '.join(known)}")

    updater = Updater(root)
    changes, failures = [], []
    for app in args.apps or known:
        previous = updater.sources["apps"].get(app)
        try:
            if change := updater.update_app(app, args.force):
                changes.append(change)
        except Exception as err:  # keep going: one broken release must not block the others
            log(f"{app}: update failed: {err}")
            failures.append(app)
            if previous is None:
                updater.sources["apps"].pop(app, None)
            else:
                updater.sources["apps"][app] = previous
            updater.save()

    print("\n".join(changes) if changes else "everything is up to date")
    if failures:
        log(f"failed: {', '.join(failures)}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
