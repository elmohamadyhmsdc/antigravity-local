# Test-only TLS certificate

`test_server.crt` / `test_server.key` are a throwaway self-signed EC certificate (100-year validity, CN
`antigravity-test`, SAN `localhost` + `127.0.0.1`) used by `test/data/pinned_http_test.dart` to run a
local HTTPS server and prove that the client trusts exactly one pinned fingerprint.

The private key protects nothing: it was generated for this test only and is never used by the app or
the PC server (the PC generates its own certificate on first run, see `the app/mobile_api/tls.py`).

Regenerate with:

    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
      -keyout test_server.key -out test_server.crt -days 36500 -subj "/CN=antigravity-test" \
      -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"
