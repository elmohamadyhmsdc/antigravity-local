import sys
import faulthandler

# Native inference failures cannot be caught by the HTTP exception handler.
# Keep every Python thread's location in the redirected server log as well.
faulthandler.enable(all_threads=True)

from .supervisor import supervise, wants_supervisor

if wants_supervisor(sys.argv[1:]):
    # This process only restarts the real server (a child) after a crash; see supervisor.py.
    sys.exit(supervise(sys.argv[1:]))

# Grouping's clustering libraries (sklearn -> pandas -> pyarrow, scipy) used to be imported lazily
# on a request thread after the GPU models were loaded; that import crashed the whole server with an
# access violation (0xC0000005, logs/mobile_api.log 2026-10-27). Load them first, on the main thread.
import scipy.optimize  # noqa: E402,F401
import sklearn.cluster  # noqa: E402,F401

from .server import main  # noqa: E402

sys.exit(main())
