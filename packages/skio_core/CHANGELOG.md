## 0.1.2

- README badges; clearer pub.dev description and a link to
  skio-flutter.dev.

## 0.1.1

- README rewritten to explain every part in plain words: permissions,
  error types, device filters, plug events and logging, with tables and
  examples.

## 0.1.0

First stable release. No API changes since 0.1.0-beta.1.

## 0.1.0-beta.1

First beta. The API may still change before 0.1.0.


- Initial types: `AccessStatus`, `AccessReport`, `HardwareAccess`,
  `DeviceHandle`, `DeviceFilter`, `DeviceEvent` and the sealed
  `HardwareException` family.
- `SkioLog`: opt-in logging (`LogLevel`, `LogRecord`, hex helper), silent
  by default.
