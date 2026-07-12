# Security And Privacy

Report security or privacy issues privately through GitHub Security Advisories.

Ulysses backups and exported notes contain private writing and attachments. Public issues should include only `ulysses-export-report.json`, whose schema excludes note text, titles, filenames, URLs, and filesystem paths. Review any diagnostic before uploading it.

The exporter reads the selected backup and writes only to a new empty destination and its temporary sibling staging directory. It does not upload data or use network APIs.
