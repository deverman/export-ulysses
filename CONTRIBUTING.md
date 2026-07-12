# Contributing

Open an issue before changing migration semantics. A fidelity change needs a minimal synthetic fixture, a regression test, and an explanation of how both Ulysses and FSNotes represent the data.

Pull requests must keep private content out of fixtures and logs, pass `swift test`, preserve atomic output, and update the compatibility or troubleshooting documentation when user-visible behavior changes.

Do not attach a real `.ulbackup`, private manifest, or visible migration report to a public issue. Use the anonymous support JSON.
