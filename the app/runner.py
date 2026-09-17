import sys
import json
import base64
from pathlib import Path
from undress_core import get_shared_client

client = get_shared_client()
job_file = Path("jobs/b7362ba3.json")
if job_file.exists():
    params = json.loads(job_file.read_text())["params"]
else:
    params = {}

def cb(msg):
    print('UPDATE:', msg)
    sys.stdout.flush()

res = client.generate(params, timeout=7200, status_callback=cb)

if res.get("success") is False:
    print("ERROR:", res.get("error"))
    print("TRACEBACK:", res.get("traceback"))
else:
    print("RESULT:", list(res.keys()))

if res.get("success") is True and "output_image" in res:
    img_data = base64.b64decode(res["output_image"])
    out_path = Path("outputs/undress_result/test.png")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_bytes(img_data)
    
    if job_file.exists():
        job_data = json.loads(job_file.read_text())
        job_data["status"] = "completed"
        job_data["progress"] = 1.0
        job_data["result_path"] = str(out_path.absolute())
        job_file.write_text(json.dumps(job_data))
    print(f"Saved to {out_path}")
