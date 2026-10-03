# OPDS browser transport

The web client routes OPDS feeds, covers and book downloads through the Papyrus
server relay. Public browsing and guest imports do not require an account, but
the configured server must be reachable. Guest imports stay in the local library.
See [OPDS setup and behavior](opds-support.md).

A catalog response allowing browser access does not guarantee that its downloads
allow it: redirects and final file responses can have different CORS policies.
A direct-first fallback would make imports depend on each publisher's response
headers. The relay keeps this behavior consistent and applies backend origin,
redirect and credential rules. It does not bypass catalog authentication.

The server implementation and security checks live in `papyrus/services/opds.py`
and `tests/api/routes/test_opds.py`; the client transport is
`app/lib/opds/opds_http_client.dart`. Keep relay/account isolation and cancellation
regressions when changing this boundary.
