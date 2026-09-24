# Security policy

## Reporting a vulnerability

Please **do not open a public issue** for security problems.

Report privately through GitHub:
[Security → Report a vulnerability](https://github.com/skio-flutter/skio/security/advisories/new).

You can expect an acknowledgement within 7 days. Fixes are released as a
patch version of the affected package, and the advisory is published once a
fixed version is on pub.dev.

## Supported versions

Only the latest minor version of each skio package receives security fixes
while the packages are at 0.x.

## How releases are protected

- Packages are published only from GitHub Actions using pub.dev's OIDC
  automated publishing. No pub.dev credentials are stored in this repository
  or its secrets.
- Publishing requires a matching release tag (`<package>-v<version>`) and a
  manual approval in the `pub.dev` GitHub environment.
- skio packages make no network requests and collect no telemetry.
