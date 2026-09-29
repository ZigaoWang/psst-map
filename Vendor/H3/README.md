# H3

Uber's H3 library (https://github.com/uber/h3), version 4.5.0, the same version the Psst server uses, so the
app and the server compute identical cell ids. The C sources are unmodified; `include/h3api.h` was generated
from `h3api.h.in` with the version numbers filled in. Licensed under the Apache License 2.0 (`LICENSE`).

The app compiles these files directly and imports them as the `CH3` module (see `project.yml`).
`PsstMapTests/H3Tests.swift` checks 1,000 cell ids against the server's.
