"""
The phone owns the data; the server is stateless. This checks the hard rules of mobile_api:

  1. it never imports database / JsonDatabase or any module that imports it (static, transitive)
  2. it never refers to the data/ folder
  3. it never unpickles anything (no pickle / marshal / shelve / dill / joblib.load / numpy allow_pickle)
  4. at runtime - a full pairing + upload + analyze round trip in a fresh interpreter - `database`
     is never imported and data/ is byte-identical afterwards (and is not created if absent)

Standalone script (repo convention): prints PASS/FAIL and exits 1 on failure.
The runtime check needs the packages in requirements_mobile_api.txt; the static ones do not.

    venv\\Scripts\\python.exe test_mobile_stateless.py
"""

import ast
import hashlib
import json
import subprocess
import sys
import tempfile
import traceback
from pathlib import Path

HERE = Path(__file__).resolve().parent
PKG = HERE / "mobile_api"
DATA = HERE / "data"

_TESTS = []


def test(fn):
    _TESTS.append(fn)
    return fn


def check(cond, msg):
    if not cond:
        raise AssertionError(msg)


# --------------------------------------------------------------------------- static analysis helpers

def package_sources():
    return sorted(p for p in PKG.rglob("*.py") if "contract" not in p.relative_to(PKG).parts)


def imports_in(tree, module_level_only=False):
    """Top-level module names imported anywhere in `tree` (or only outside functions/classes bodies)."""
    found = set()

    def visit(node, depth):
        for child in ast.iter_child_nodes(node):
            in_func = depth or isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef))
            if isinstance(child, ast.Import):
                if not (module_level_only and depth):
                    found.update(a.name.split(".")[0] for a in child.names)
            elif isinstance(child, ast.ImportFrom):
                if not (module_level_only and depth) and child.level == 0 and child.module:
                    found.add(child.module.split(".")[0])
            visit(child, 1 if in_func else depth)

    visit(tree, 0)
    return found


def local_module(name):
    p = HERE / f"{name}.py"
    return p if p.is_file() else None


def reaches_database(module, seen=None):
    """Does importing `module` (module-level imports, transitively through the app's own files) load database.py?"""
    seen = seen if seen is not None else set()
    if module in seen:
        return False
    seen.add(module)
    if module == "database":
        return True
    path = local_module(module)
    if path is None:
        return False
    tree = ast.parse(path.read_text(encoding="utf-8"))
    return any(reaches_database(m, seen) for m in imports_in(tree, module_level_only=True))


# --------------------------------------------------------------------------- static tests

@test
def test_mobile_api_never_imports_the_database_even_indirectly():
    offenders = []
    checked = 0
    for src in package_sources():
        tree = ast.parse(src.read_text(encoding="utf-8"))
        for mod in imports_in(tree):  # every import, including the lazy ones inside functions
            if local_module(mod) is None and mod != "mobile_api":
                continue
            checked += 1
            if mod != "mobile_api" and reaches_database(mod):
                offenders.append(f"{src.relative_to(HERE)} imports {mod}, which loads database.py")
    check(checked > 5, f"scanned too little ({checked} app-module imports) - is the scanner broken?")
    check(not offenders, "; ".join(offenders))


@test
def test_the_scanner_detects_a_database_import_when_there_is_one():
    """Guard against a vacuous pass: the same analysis must flag modules that really do load database."""
    check(reaches_database("library_scanner"), "library_scanner imports database - the analysis must see that")
    check(reaches_database("gallery_grouping"), "gallery_grouping imports database - the analysis must see that")
    check(not reaches_database("analysis") and not reaches_database("person_linking"), "pure modules are clean")
    tree = ast.parse("def f():\n    from database import JsonDatabase\n")
    check("database" in imports_in(tree) and "database" not in imports_in(tree, module_level_only=True),
          "lazy imports inside functions are seen by the all-imports scan")


@test
def test_mobile_api_never_refers_to_the_data_folder():
    offenders = []
    for src in package_sources():
        tree = ast.parse(src.read_text(encoding="utf-8"))
        docstrings = set()
        for node in ast.walk(tree):
            if isinstance(node, (ast.Module, ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                body = node.body
                if body and isinstance(body[0], ast.Expr) and isinstance(getattr(body[0], "value", None), ast.Constant):
                    docstrings.add(id(body[0].value))
        for node in ast.walk(tree):
            if isinstance(node, ast.Constant) and isinstance(node.value, str) and id(node) not in docstrings:
                v = node.value.replace("\\", "/").strip("/").lower()
                if v == "data" or v.startswith("data/") or v.endswith("/data") or "/data/" in v:
                    offenders.append(f"{src.name}: string {node.value!r}")
    check(not offenders, "; ".join(offenders))


@test
def test_mobile_api_never_unpickles():
    banned_modules = {"pickle", "cPickle", "_pickle", "marshal", "shelve", "dill", "cloudpickle", "jsonpickle"}
    offenders = []
    for src in package_sources():
        text = src.read_text(encoding="utf-8")
        tree = ast.parse(text)
        for mod in imports_in(tree) & banned_modules:
            offenders.append(f"{src.name} imports {mod}")
        for node in ast.walk(tree):
            if isinstance(node, ast.Call):
                fn = ast.unparse(node.func)
                if fn in ("joblib.load", "torch.load", "np.load", "numpy.load", "yaml.load", "yaml.unsafe_load"):
                    offenders.append(f"{src.name}: {fn}(...)")
                for kw in node.keywords:
                    if kw.arg == "allow_pickle" and not (isinstance(kw.value, ast.Constant) and kw.value.value is False):
                        offenders.append(f"{src.name}: allow_pickle")
        if "Faceset.load" in text or "faceset" in {m.lower() for m in imports_in(tree)}:
            offenders.append(f"{src.name} touches Faceset (pickle based, local-only)")
    check(not offenders, "; ".join(offenders))


# --------------------------------------------------------------------------- runtime test

def tree_digest(root: Path):
    """Names, sizes, mtimes and content hashes of everything under root (None if it does not exist)."""
    if not root.exists():
        return None
    entries = []
    for p in sorted(root.rglob("*")):
        st = p.stat()
        h = hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else ""
        entries.append((str(p.relative_to(root)), st.st_size, st.st_mtime_ns, h))
    return entries


RUNTIME_SCRIPT = r'''
import hashlib, io, json, os, shutil, sys, tempfile
from pathlib import Path
import cv2, numpy as np
from fastapi.testclient import TestClient
from mobile_api.app import create_app
from mobile_api.pair_ui import create_pair_app
from mobile_api.testing import make_test_context
from mobile_api.tls import ensure_cert
from mobile_api.workspace import Workspace

tmp = Path(tempfile.mkdtemp(prefix="mobile_stateless_"))
try:
    ctx = make_test_context(tmp)
    ctx.cert = ensure_cert(ctx.workspace.tls_dir)
    client = TestClient(create_app(ctx))
    code = ctx.pairing.issue().code
    token = client.post("/v1/pair/complete", json={"code": code, "device_name": "t"}).json()["token"]
    auth = {"Authorization": f"Bearer {token}"}
    assert client.get("/v1/capabilities", headers=auth).status_code == 200
    data = os.urandom(3000)
    digest = hashlib.sha256(data).hexdigest()
    assert client.put(f"/v1/blobs/{digest}", content=data, headers=auth).status_code == 201
    img = np.random.default_rng(1).integers(0, 255, (480, 640, 3), dtype=np.uint8)
    jpg = cv2.imencode(".jpg", img)[1].tobytes()
    r = client.post("/v1/analyze/image", files={"image": ("a.jpg", jpg, "image/jpeg")}, headers=auth)
    assert r.status_code == 200 and r.json()["faces"], r.text
    assert TestClient(create_pair_app(ctx)).get("/pair").status_code == 200
    ctx.workspace.purge_expired_jobs()
finally:
    shutil.rmtree(tmp, ignore_errors=True)

# (pickle/marshal are loaded by numpy, importlib and others themselves, so they say nothing about
#  mobile_api - the static test above checks that mobile_api never imports them)
FORBIDDEN = {"database", "gallery_grouping", "library_scanner", "gallery_page", "face_miner", "dashboard",
             "lora_trainer", "lora_staging", "lora_identity", "lora_dataset"}
print("RESULT " + json.dumps({"loaded": sorted(FORBIDDEN & set(sys.modules)), "cwd": os.getcwd()}))
'''


@test
def test_a_full_round_trip_never_loads_database_and_leaves_data_untouched():
    try:
        import fastapi  # noqa: F401
    except ImportError as e:
        raise AssertionError(f"FastAPI is not installed in this interpreter ({e}); install requirements_mobile_api.txt")
    before = tree_digest(DATA)
    with tempfile.TemporaryDirectory(prefix="mobile_stateless_cwd_") as elsewhere:
        # run from a different cwd on purpose: nothing may depend on (or write into) a relative data/ either
        proc = subprocess.run([sys.executable, "-c", RUNTIME_SCRIPT], cwd=elsewhere, capture_output=True, text=True,
                              env={**__import__("os").environ, "PYTHONPATH": str(HERE)}, timeout=300)
        check(proc.returncode == 0, f"runtime script failed:\n{proc.stdout[-1500:]}\n{proc.stderr[-2500:]}")
        line = next((l for l in proc.stdout.splitlines() if l.startswith("RESULT ")), None)
        check(line is not None, f"no result line:\n{proc.stdout[-800:]}\n{proc.stderr[-800:]}")
        result = json.loads(line[len("RESULT "):])
        check(result["loaded"] == [], f"forbidden modules were imported at runtime: {result['loaded']}")
        check(not (Path(elsewhere) / "data").exists(), "a relative data/ folder was created")
    after = tree_digest(DATA)
    check(before == after, "the data/ folder changed while the API ran")


def main(argv):
    pattern = argv[0] if argv else ""
    selected = [t for t in _TESTS if pattern in t.__name__]
    failed = 0
    for t in selected:
        try:
            t()
            print(f"[PASS] {t.__name__}")
        except Exception as e:  # noqa: BLE001
            failed += 1
            print(f"[FAIL] {t.__name__}: {e}")
            traceback.print_exc()
    print(f"\n{len(selected) - failed}/{len(selected)} passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
