# B4 report guard fixtures

These fixed, sanitized JSON reports are **unit-test input**, captured from the original B4 positive backup/update runs. They contain no credentials or employee names. They are not newly executed recovery evidence or a current approval. Their run identities, timestamps and digests deliberately remain stable so tests need neither a database nor live secrets.

`Test-P416RecoveryReportSemantics.ps1` removes or changes every field and applies additional independent semantic mutations. The redaction scripts use these structurally valid reports for their clean positive controls; rejection cases must fail specifically for redaction.

Raw JSON cases also exercise duplicate/case-colliding keys. Caller-result cases distinguish a retained valid FAIL artifact from evidence of a successful current run.
