"""florence_captioner: caption cleaning and the venv_ai worker client (no model, no GPU).

Fake workers stand in for venv_ai: results, a crash midway, garbage output, a hang
(timeout) and a cancelled job. Exits 1 on failure.
"""
import sys
import time

import florence_captioner as fc

failures = []


def check(name, ok, detail=""):
    print(("PASS " if ok else "FAIL ") + name + (f" - {detail}" if detail and not ok else ""))
    if not ok:
        failures.append(name)


# --- clean_caption ------------------------------------------------------------------
check("dedupes sentences", fc.clean_caption("A woman. A woman. She smiles.") == "A woman. She smiles")
check("drops unfinished tail", fc.clean_caption("A woman smiles. The person is in the middle of the") == "A woman smiles")
check("strips task tokens", fc.clean_caption("<CAPTION>A dog runs.</s>") == "A dog runs")
check("caps words", len(fc.clean_caption(" ".join(["word"] * 80))).__le__(25 * 5))
check("empty stays empty", fc.clean_caption("") == "")


def worker(body):
    return [sys.executable, "-c", "import json,sys\npaths=json.loads(sys.stdin.read())\n" + body]


PREFIX = repr(fc.RESULT_PREFIX)
paths = ["a.jpg", "b.jpg", "c.jpg"]

ok = fc.caption_paths(paths, worker_command=worker(
    f"for p in paths: print({PREFIX} + json.dumps({{'path': p, 'caption': 'cap ' + p}}), flush=True)"))
check("all captions returned", ok == {p: "cap " + p for p in paths}, str(ok))

crash = fc.caption_paths(paths, worker_command=worker(
    f"print({PREFIX} + json.dumps({{'path': paths[0], 'caption': 'one'}}), flush=True)\nimport os; os._exit(3)"))
check("crash keeps finished captions", crash == {"a.jpg": "one"}, str(crash))

junk = fc.caption_paths(paths, worker_command=worker(
    f"print('noise'); print({PREFIX} + '{{bad json'); print({PREFIX} + json.dumps({{'path': 'b.jpg', 'caption': ''}}))"))
check("garbage and empty captions ignored", junk == {}, str(junk))

saved = fc.STARTUP_TIMEOUT_S
fc.STARTUP_TIMEOUT_S = 1.0
t = time.monotonic()
hung = fc.caption_paths(paths, worker_command=worker("import time; time.sleep(60)"))
fc.STARTUP_TIMEOUT_S = saved
check("hung worker times out and is killed", hung == {} and time.monotonic() - t < 15, f"{time.monotonic() - t:.1f}s")


class Cancelled(Exception):
    pass


def cancel(done, total):
    raise Cancelled()


try:
    fc.caption_paths(paths, progress=cancel, worker_command=worker(
        f"import time\nfor p in paths: print({PREFIX} + json.dumps({{'path': p, 'caption': 'x'}}), flush=True); time.sleep(5)"))
    check("cancel propagates", False, "no exception")
except Cancelled:
    check("cancel propagates", True)

missing = fc.caption_paths(paths, python=fc.APP_DIR / "no_such_python.exe")
check("missing worker python -> no captions", missing == {})

if failures:
    print(f"\n{len(failures)} failure(s): {failures}")
    sys.exit(1)
print("\nAll florence_captioner checks passed.")
