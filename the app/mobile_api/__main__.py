import sys
import faulthandler

# Native inference failures cannot be caught by the HTTP exception handler.
# Keep every Python thread's location in the redirected server log as well.
faulthandler.enable(all_threads=True)

from .server import main

sys.exit(main())
