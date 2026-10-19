#requires -Version 7.4

# Guards the sanitized update/recovery acceptance report. Dot-sourced by the
# acceptance runner and by scripts/update/Test-UpdateAcceptanceRedaction.ps1.
function Assert-UpdateAcceptanceReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [string[]] $SensitiveValues = @(),
        [ValidateSet('pass', 'failed')] [string] $ExpectedResult
    )

    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw 'Acceptance report not found.'
    }
    # Raw checks catch serialization leaks before parsing. Decoded checks below
    # use the same patterns and ordinal sensitive representations.
    $ErrorActionPreference = 'Stop'
    $patterns = @(
        '(?i)postgres(?:ql)?://',
        '(?i)bearer\s+[A-Za-z0-9._~+/-]',
        '(?i)"(password|token|secret|key|displayName|username|terminalReason|connectionString|authorization|proxy-authorization)"\s*:',
        '(?i)\b(?:proxy-)?authorization\s*:\s*(?:basic|bearer)\b',
        '-----BEGIN'
    )
    $representations = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $base64Representations = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    function Assert-ReportText([string]$Text) {
        $inspection.textRemaining -= $Text.Length
        if ($inspection.textRemaining -lt 0) { throw 'Acceptance report JSON inspection limit exceeded.' }
        foreach ($pattern in $patterns) {
            if ($Text -match $pattern) { throw 'Acceptance report contains a forbidden pattern.' }
        }
        foreach ($representation in $representations) {
            if ($Text.Contains($representation, [StringComparison]::Ordinal)) { throw 'Acceptance report contains a sensitive value.' }
        }
        # URL percent hex is case-insensitive and unreserved characters can be
        # escaped too. Inspect one URI decoding without changing JSON semantics.
        $uriText = $Text
        if ($representations.Count -gt 0 -and $Text.Contains('%')) {
            $uriText = [Uri]::UnescapeDataString($Text)
            if ($uriText -cne $Text) {
                $inspection.textRemaining -= $uriText.Length
                if ($inspection.textRemaining -lt 0) { throw 'Acceptance report JSON inspection limit exceeded.' }
                foreach ($representation in $representations) {
                    if ($uriText.Contains($representation, [StringComparison]::Ordinal)) { throw 'Acceptance report contains a sensitive value.' }
                }
            }
        }
        # Standard Base64 permits ASCII space, tab, CR and LF. Only Base64
        # representations are compared after removing those separators.
        if ($base64Representations.Count -gt 0) {
            $base64Text = $uriText.Replace(' ', '').Replace([string][char]9, '').Replace([string][char]13, '').Replace([string][char]10, '')
            if ($base64Text -cne $uriText) {
                $inspection.textRemaining -= $base64Text.Length
                if ($inspection.textRemaining -lt 0) { throw 'Acceptance report JSON inspection limit exceeded.' }
                foreach ($representation in $base64Representations) {
                    if ($base64Text.Contains($representation, [StringComparison]::Ordinal)) { throw 'Acceptance report contains a sensitive value.' }
                }
            }
        }
    }
    # All document parses share traversal/text budgets. Nested JSON text supports
    # four encoding layers; ordinary text (including literal backslashes) is not
    # globally unescaped. No offending content enters a rejection diagnostic.
    $inspection = @{ nodesRemaining = 32768; textRemaining = 8388608 }
    $options = [System.Text.Json.JsonDocumentOptions]::new()
    $options.MaxDepth = 64
    function Assert-JsonText([string]$Text, [int]$Depth, [int]$NestedDepth) {
        Assert-ReportText $Text
        $trimmed = $Text.TrimStart()
        if ($trimmed.Length -gt 0 -and $trimmed[0] -cin @('{', '[', '"')) {
            if ($NestedDepth -ge 4) { throw 'Acceptance report JSON inspection limit exceeded.' }
            $nestedDocument = [System.Text.Json.JsonDocument]::Parse($trimmed, $options)
            try { Assert-JsonContent $nestedDocument.RootElement ($Depth + 1) ($NestedDepth + 1) } finally { $nestedDocument.Dispose() }
        }
    }
    function Assert-JsonContent([System.Text.Json.JsonElement]$Element, [int]$Depth, [int]$NestedDepth) {
        $inspection.nodesRemaining--
        if ($inspection.nodesRemaining -lt 0 -or $Depth -gt 64) { throw 'Acceptance report JSON inspection limit exceeded.' }
        if ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
            $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach ($property in $Element.EnumerateObject()) {
                # PowerShell can suppress a .NET property-getter exception.
                # A valid JSON member name is a string, including the empty one.
                $name = $property.Name
                if ($null -eq $name) { throw 'Acceptance report JSON inspection failed.' }
                $inspection.nodesRemaining--
                if ($inspection.nodesRemaining -lt 0) { throw 'Acceptance report JSON inspection limit exceeded.' }
                if (!$names.Add($name)) { throw 'Acceptance report contains ambiguous JSON keys.' }
                if ($name -imatch '^(password|token|secret|key|displayName|username|terminalReason|connectionString|authorization|proxy-authorization)$') {
                    throw 'Acceptance report contains a forbidden pattern.'
                }
                Assert-JsonText $name $Depth $NestedDepth
                Assert-JsonContent $property.Value ($Depth + 1) $NestedDepth
            }
        } elseif ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Array) {
            foreach ($elementValue in $Element.EnumerateArray()) { Assert-JsonContent $elementValue ($Depth + 1) $NestedDepth }
        } elseif ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::String) {
            Assert-JsonText $Element.GetString() $Depth $NestedDepth
        }
    }
    try {
    foreach ($value in $SensitiveValues) {
        if ([string]::IsNullOrEmpty($value)) { continue }
        $base64 = [Convert]::ToBase64String([Text.UTF8Encoding]::new($false, $true).GetBytes($value))
        [void]$base64Representations.Add($base64)
        foreach ($representation in @($value, [Uri]::EscapeDataString($value), $base64)) {
            [void]$representations.Add($representation)
        }
    }
        # UTF-8 is the wrapper report format. Hold a read-only stream while
        # enforcing its size; strict decoding also rejects invalid UTF-8 bytes.
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        try {
            if ($stream.Length -gt 4194304) { throw 'Acceptance report JSON inspection limit exceeded.' }
            $reader = [IO.StreamReader]::new($stream, [Text.UTF8Encoding]::new($false, $true), $false)
            try { $content = $reader.ReadToEnd() } finally { $reader.Dispose() }
        } finally { $stream.Dispose() }
        if ($content.Length -gt 0 -and $content[0] -eq [char]0xfeff) { $content = $content.Substring(1) }
        Assert-ReportText $content
        $document = [System.Text.Json.JsonDocument]::Parse($content, $options)
        try { Assert-JsonContent $document.RootElement 0 0 } finally { $document.Dispose() }
        $report = $content | ConvertFrom-Json -AsHashtable -ErrorAction Stop
    } catch {
        # Keep the established redaction categories; parser/decoder details can
        # echo attacker-controlled text and are intentionally not propagated.
        if ($_.Exception.Message -cin @('Acceptance report contains a forbidden pattern.', 'Acceptance report contains a sensitive value.', 'Acceptance report contains ambiguous JSON keys.', 'Acceptance report JSON inspection limit exceeded.')) { throw $_.Exception.Message }
        throw 'Acceptance report JSON inspection failed.'
    }
    $schema = 'storeos.p416.b4.update.v1'
    $manifestPaths = @('apps/server/tool/update_recovery_fixture.dart', 'apps/server/tool/shift_swap_recovery_acceptance.dart', 'apps/server/tool/shift_transfer_acceptance.dart', 'scripts/update/Run-UpdateRecoveryAcceptance.ps1', 'scripts/update/Assert-UpdateAcceptanceReport.ps1')
    $phases = @('createSourceDatabase', 'prepare', 'restorePoint', 'upgrade', 'smoke', 'recoveryRestore', 'recoveryVerify')
    $failureSteps = @('create-source-database', 'prepare', 'restore-point', 'upgrade', 'smoke', 'recovery-restore', 'recovery-verify')
    if ($report -isnot [System.Collections.IDictionary]) { throw 'Report must be an object.' }
    $id = $report['runId']
    $ownedNames = @("storeos_update_$id", "storeos_restore_upd_$id")
    $migrationVersions = @('0001_platform_auth', '0002_platform_organization', '0003_platform_events_plugins', '0004_employee_identity_and_audit', '0005_task_templates', '0006_shifts_and_task_instances', '0007_task_execution', '0008_task_blocking', '0009_task_cancellation', '0010_task_numeric_steps', '0011_published_shift_cancellation', '0012_published_shift_amendment', '0013_article_master', '0014_location_assortment', '0015_manual_stock', '0016_local_planograms', '0017_approved_operational_knowledge', '0018_task_knowledge_guidance', '0019_task_planogram_guidance', '0020_stock_counts', '0021_recipe_compositions', '0022_preparation_batches', '0023_one_way_shift_transfers', '0024_bounded_purchase_orders', '0025_planned_preparation_assignments', '0026_purchase_order_delivery_evidence', '0027_article_quantities', '0028_bilateral_shift_swaps', '0029_swap_leg_future_error')
    # Report validation never grants a report success by falling through an
    # unrecognized schema. These helpers check JSON types before comparisons.
    function Assert-Node($Value, $Shape, [string]$Field = 'report') {
        if ($Shape -is [System.Collections.IDictionary]) {
            if ($Value -isnot [System.Collections.IDictionary]) { throw "Invalid report object: $Field." }
            foreach ($name in $Shape.Keys) {
                if (!$Value.Contains($name)) { throw "Missing report field: $Field.$name." }
                Assert-Node $Value[$name] $Shape[$name] "$Field.$name"
            }
            return
        }
        $valid = switch -CaseSensitive ($Shape) {
            '#object' { $Value -is [System.Collections.IDictionary]; break }
            '#array' { $Value -is [array]; break }
            '#text' { $Value -is [string] -and ![string]::IsNullOrWhiteSpace($Value); break }
            '#positive' { ($Value -is [long] -or $Value -is [int]) -and $Value -gt 0; break }
            '#digits' { $Value -is [string] -and $Value -cmatch '^[1-9][0-9]*$'; break }
            '#sha256' { $Value -is [string] -and $Value -cmatch '^[a-f0-9]{64}$'; break }
            '#md5' { $Value -is [string] -and $Value -cmatch '^[a-f0-9]{32}$'; break }
            '#uuid' { $Value -is [string] -and $Value -cmatch '^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$'; break }
            default {
                if ($Shape -is [bool]) { $Value -is [bool] -and $Value -eq $Shape }
                elseif ($Shape -is [int] -or $Shape -is [long]) { ($Value -is [int] -or $Value -is [long]) -and $Value -eq $Shape }
                else { $Value -is [string] -and $Value -ceq $Shape }
            }
        }
        if (!$valid) { throw "Invalid report value: $Field." }
    }
    function Assert-Same($Left, $Right, [string]$Field) {
        if ($Left -cne $Right) { throw "Inconsistent report evidence: $Field." }
    }
    function Assert-Versions($Values, [int]$Start, [int]$End, [string]$Field) {
        Assert-Node $Values '#array' $Field
        if ($Values.Count -ne $End - $Start + 1) { throw "Invalid migration inventory: $Field." }
        for ($i = 0; $i -lt $Values.Count; $i++) {
            Assert-Node $Values[$i] $migrationVersions[$Start + $i - 1] $Field
        }
    }
    function Assert-Digests($Values, $Counts, [string]$Field) {
        Assert-Node $Values '#object' $Field
        Assert-Same $Values.Count $Counts.Count $Field
        foreach ($table in $Counts.Keys) {
            Assert-Node $Values @{ $table = @{ count = $Counts[$table]; sha256 = '#sha256' } } $Field
        }
    }
    Assert-Node $report @{ runId = '#text'; result = '#text'; failedStep = '#text'; operatingDatabase = '#text'; sourceDatabase = '#text'; steps = '#object'; cleanup = '#object' }
    if ($report.runId -cnotmatch '^[a-f0-9]{16}$' -or $report.operatingDatabase -cnotmatch '^[a-z0-9_]{1,63}$') { throw 'Invalid run/database identity.' }
    if ($report.result -cnotin @('pass', 'failed')) { throw 'Unsupported report result; not a PASS proof.' }
    if ($ExpectedResult -and $report.result -cne $ExpectedResult) { throw 'Acceptance report result differs from actual run result.' }
    $pass = $report.result -ceq 'pass'
    foreach ($field in @('startedAtUtc', 'finishedAtUtc')) {
        if (!$report.Contains($field) -or ($report[$field] -isnot [string] -and $report[$field] -isnot [DateTime])) { throw 'Invalid report timestamp.' }
        try { $stamp = [DateTimeOffset]::Parse($report[$field].ToString('o'), [Globalization.CultureInfo]::InvariantCulture) }
        catch {
            if ($report[$field] -isnot [string] -or $report[$field] -cnotmatch '^\d{4}-\d\d-\d\dT.*Z$') { throw 'Invalid report UTC timestamp.' }
            $stamp = [DateTimeOffset]::Parse($report[$field], [Globalization.CultureInfo]::InvariantCulture)
        }
        if ($stamp.Offset -ne [TimeSpan]::Zero) { throw 'Report timestamp must be UTC.' }
        if ($field -eq 'startedAtUtc') { $started = $stamp } elseif ($stamp -lt $started) { throw 'Report finishes before it starts.' }
    }
    $legacyFailure = !$report.Contains('acceptanceSchema') -and !$pass
    if ($legacyFailure) {
        # The historical unversioned wrappers emitted FAIL only via result=failed,
        # without any B4 provenance/classification fields. Never accept their
        # unversioned PASS format as a B4 acceptance proof.
        foreach ($name in @('classification', 'sourceRevision', 'sourceManifest', 'schemaState', 'failureInjection', 'negativeRecoveryProof')) {
            if ($report.Contains($name)) { throw 'Ambiguous legacy failure report.' }
        }
    } else {
        Assert-Node $report @{ acceptanceSchema = $schema; classification = $(if ($pass) { 'PASS' } else { 'FAIL' }) }
        $historicalB4Failure = !$pass -and !$report.Contains('sourceRevision') -and !$report.Contains('sourceManifest') -and !$report.Contains('negativeRecoveryProof')
        if (!$historicalB4Failure) {
        Assert-Node $report @{ sourceRevision = '#text'; sourceManifest = '#array' }
        if ($report.sourceRevision -cnotmatch '^[a-f0-9]{40}$' -or $report.sourceManifest.Count -ne $manifestPaths.Count) { throw 'Invalid source provenance.' }
        $seen = @()
        foreach ($entry in $report.sourceManifest) {
            Assert-Node $entry @{ path = '#text'; sha256 = '#sha256' } 'sourceManifest'
            if ($entry.path -cnotin $manifestPaths -or $entry.path -cin $seen) { throw 'Invalid source manifest inventory.' }
            $seen += $entry.path
        }
        }
    }
    $phaseCount = $report.steps.Count
    if ($phaseCount -gt $phases.Count -or ($pass -and $phaseCount -ne $phases.Count)) { throw 'Incomplete report phases.' }
    for ($i = 0; $i -lt $phaseCount; $i++) { Assert-Node $report.steps @{ $phases[$i] = $true } 'steps' }
    if ($report.failedStep -cnotin (@('setup', 'none', 'cleanup') + $failureSteps)) { throw 'Unknown failed phase.' }
    if ($pass -and $report.failedStep -cne 'none') { throw 'PASS report declares a failed phase.' }
    if (!$pass -and $report.failedStep -cin $failureSteps) {
        $failureIndex = [array]::IndexOf($failureSteps, $report.failedStep)
        if ($phaseCount -lt $failureIndex -or $phaseCount -gt $failureIndex + 1) { throw 'Failed phase contradicts completed phases.' }
    }
    if (!$pass -and $report.failedStep -ceq 'setup' -and $phaseCount -ne 0) { throw 'Setup failure contains completed phases.' }
    if (!$pass -and $report.failedStep -ceq 'cleanup' -and $phaseCount -ne $phases.Count) { throw 'Cleanup failure lacks completed phases.' }
    $cleanupBad = $false
    foreach ($name in $ownedNames) {
        if (!$report.cleanup.Contains($name) -or $report.cleanup[$name] -isnot [string] -or $report.cleanup[$name] -cnotin @('removed', 'absent', 'FAILED')) { throw 'Missing/invalid owned cleanup evidence.' }
        if ($report.cleanup[$name] -ceq 'FAILED') { $cleanupBad = $true }
    }
    foreach ($name in @('operatingDatabasePresent', 'acceptancePortFree')) {
        if (!$report.cleanup.Contains($name) -or $report.cleanup[$name] -isnot [bool]) { throw 'Invalid cleanup flag.' }
        if (!$report.cleanup[$name]) { $cleanupBad = $true }
    }
    foreach ($name in $report.cleanup.Keys) {
        if ($name -cnotin ($ownedNames + @('operatingDatabasePresent', 'acceptancePortFree', 'recoveryAfterInjectedFailure'))) { throw 'Unexpected cleanup identity.' }
    }
    if ($report.cleanup.Contains('recoveryAfterInjectedFailure')) { Assert-Node $report.cleanup.recoveryAfterInjectedFailure 'removed' 'cleanup.recoveryAfterInjectedFailure' }
    if (!$pass -and $report.failedStep -ceq 'cleanup' -and !$cleanupBad) { throw 'Cleanup failure lacks failure evidence.' }
    if (($pass -and $cleanupBad) -or (!$pass -and $report.failedStep -ceq 'none' -and !$cleanupBad)) { throw 'Result contradicts cleanup/failure evidence.' }
    Assert-Same $report.sourceDatabase $ownedNames[0] 'sourceDatabase'
    Assert-Node $report @{ recoveryTargetDatabase = $ownedNames[1]; injection = @{ after = '#text'; migrationCommitted = $report.steps.Contains('upgrade'); description = '#text' }; restorePoint = @{ createdBeforeUpgrade = $report.steps.Contains('restorePoint'); artifactStatus = 'deleted-after-run' } }
    if ($report.operatingDatabase -cin $ownedNames) { throw 'Operating database is a recovery target.' }
    $descriptions = @{
        none = 'none'
        prepare = 'Operational failure after the pre-update database and seed existed.'
        upgrade = 'Post-upgrade operational failure after the pending migrations committed and preservation was verified; this does not prove migration rollback.'
        recovery = 'Operational failure after the isolated recovery restore completed.'
    }
    if ($report.injection.after -cnotin @('none', 'prepare', 'upgrade', 'recovery') -or ($pass -and $report.injection.after -cne 'none')) { throw 'Result contradicts failure injection.' }
    if (!$legacyFailure) { Assert-Same $report.injection.description $descriptions[$report.injection.after] 'injection.description' }
    if ($report.steps.Contains('restorePoint')) { Assert-Node $report.restorePoint @{ artifactSha256 = '#sha256' } 'restorePoint' }
    if (!$pass) { return }
    Assert-Node $report @{ schemaState = 'pre-update-0010-upgraded-0029-recovered-0010'; contract = @{ supported = '#array'; notProven = '#array' } }
    $contractClaims = @{
        supported = @('quiesced offline update', 'encrypted PostgreSQL restore point before migration', 'forward-only migration with checksum and prefix validation', 'single-transaction migration atomicity', 'current application only after successful forward migration through 0029', 'isolated recovery of pre-update PostgreSQL state', 'recovery fencing', 'operator-verifiable evidence')
        notProven = @('no down migration', 'no application downgrade', 'no restore over the operating database', 'no automated restored-database activation', 'no production failover or high availability', 'no zero-downtime update', 'no attachment, TLS certificate, configuration or external secret backup', 'no retention or multi-site coordination')
    }
    foreach ($name in $contractClaims.Keys) {
        Assert-Same $report.contract[$name].Count $contractClaims[$name].Count "contract.$name"
        for ($i = 0; $i -lt $contractClaims[$name].Count; $i++) { Assert-Node $report.contract[$name][$i] $contractClaims[$name][$i] "contract.$name" }
    }
    foreach ($phase in @('prepare', 'upgrade', 'smoke', 'recovery')) {
        if (!$report.Contains($phase) -or ($null -ne $report[$phase] -and $report[$phase] -isnot [System.Collections.IDictionary])) { throw 'Missing/invalid phase evidence.' }
    }
    if ($report.steps.Contains('prepare')) {
        Assert-Node $report.prepare @{
            'sourceDatabase' = '#text'
            'prefixChecksumsVerified' = $true
            'prefixByteCopiesVerified' = $true
            'prefixTempDirectoryRemoved' = $true
            'seed' = @{
                'shifts' = 2
                'taskInstances' = 5
                'states' = @{
                    'open' = 1
                    'in_progress' = 1
                    'blocked' = 1
                    'completed' = 1
                    'cancelled' = 1
                }
                'stepResults' = 2
                'numericAttempts' = 2
                'blockings' = 2
                'receipts' = 11
                'auditEntries' = '#positive'
                'activeSessions' = 1
                'activePluginTokens' = 1
            }
            'snapshot' = @{
                'tables' = @{
                    'companies' = @{
                        'count' = 1
                        'hash' = '#md5'
                    }
                    'locations' = @{
                        'count' = 1
                        'hash' = '#md5'
                    }
                    'accounts' = @{
                        'count' = 2
                        'hash' = '#md5'
                    }
                    'bootstrap_state' = @{
                        'count' = 1
                        'hash' = '#md5'
                    }
                    'employees' = @{
                        'count' = 1
                        'hash' = '#md5'
                    }
                    'account_employee_links' = @{
                        'count' = 1
                        'hash' = '#md5'
                    }
                    'task_templates' = @{
                        'count' = 5
                        'hash' = '#md5'
                    }
                    'task_template_revisions' = @{
                        'count' = 5
                        'hash' = '#md5'
                    }
                    'shifts' = @{
                        'count' = 2
                        'hash' = '#md5'
                    }
                    'shift_template_selections' = @{
                        'count' = 5
                        'hash' = '#md5'
                    }
                    'task_instances' = @{
                        'count' = 5
                        'hash' = '#md5'
                    }
                    'task_step_results' = @{
                        'count' = 2
                        'hash' = '#md5'
                    }
                    'task_numeric_attempts' = @{
                        'count' = 2
                        'hash' = '#md5'
                    }
                    'task_blockings' = @{
                        'count' = 2
                        'hash' = '#md5'
                    }
                    'task_execution_commands' = @{
                        'count' = 11
                        'hash' = '#md5'
                    }
                    'audit_entries' = @{
                        'count' = 14
                        'hash' = '#md5'
                    }
                    'plugin_registrations' = @{
                        'count' = 1
                        'hash' = '#md5'
                    }
                    'event_outbox' = @{
                        'count' = 0
                        'hash' = 'empty'
                    }
                    'plugin_inbox' = @{
                        'count' = 0
                        'hash' = 'empty'
                    }
                }
                'sequences' = @{
                    'audit_entries_id_seq' = @{
                        'lastValue' = '#digits'
                        'isCalled' = $true
                    }
                    'plugin_inbox_id_seq' = @{
                        'lastValue' = '#digits'
                        'isCalled' = $false
                    }
                }
                'activeSessions' = 1
                'activePluginTokens' = 1
            }
        } 'prepare'
        Assert-Same $report.prepare.sourceDatabase $report.sourceDatabase 'prepare.sourceDatabase'
        Assert-Versions $report.prepare.prefixVersions 1 10 'prepare.prefixVersions'
    }
    if ($report.steps.Contains('upgrade')) {
        Assert-Node $report.upgrade @{
            'repositoryMigrationCount' = 29
            'checksumsMatchRepository' = $true
            'preservation' = @{
                'projectionsMatch' = $true
                'sequencesMatch' = $true
                'activeSessionsMatch' = $true
                'activePluginTokensMatch' = $true
            }
            'newColumns' = @{
                'shifts.cancelled_at' = $true
                'shifts.cancelled_by' = $true
                'shifts.cancellation_reason' = $true
                'shifts.cancellation_version' = $true
                'task_instances.cancelled_at' = $true
                'task_instances.cancelled_by' = $true
            }
            'newAmendmentColumns' = @{
                'shifts.amended_at' = $true
                'shifts.amended_by' = $true
                'shifts.amendment_version' = $true
            }
            'legacyCancellationFieldsNull' = $true
            'constraintsPresent' = @{
                'shifts_status' = $true
                'shifts_state' = $true
                'shifts_published_no_overlap' = $true
                'task_execution_status' = $true
                'task_execution_times' = $true
            }
            'triggersPresent' = @{
                'shifts_immutable' = $true
                'instances_immutable' = $true
            }
            'articleMasterSchema' = @{
                'tablePresent' = $true
                'skuIndexPresent' = $true
                'barcodeIndexPresent' = $true
                'selectGranted' = $true
                'insertGranted' = $true
                'deleteNotGranted' = $true
                'truncateNotGranted' = $true
            }
            'assortmentSchema' = @{
                'tablePresent' = $true
                'pairIndexPresent' = $true
                'pageIndexPresent' = $true
                'selectGranted' = $true
                'insertGranted' = $true
                'deleteNotGranted' = $true
                'truncateNotGranted' = $true
            }
            'stockSchema' = @{
                'projectionViewPresent' = $true
                'levelTablePresent' = $true
                'movementTablePresent' = $true
                'scopeUniquePresent' = $true
                'movementScopeFkPresent' = $true
                'movementVersionUniquePresent' = $true
                'levelUpdateColumnsExact' = $true
                'movementAppendOnly' = $true
                'projectionSelectGranted' = $true
            }
            'invalidWritesRejected' = @{
                'published_shift_evidence_without_transition' = $true
                'cancel_without_evidence' = $true
                'cancelled_instance_gains_unstarted_evidence' = $true
                'overlapping_published_interval' = $true
            }
            'invalidWritesLeftNoChange' = $true
        } 'upgrade'
        Assert-Versions $report.upgrade.migrationsBefore 1 10 'upgrade.migrationsBefore'
        Assert-Versions $report.upgrade.applied 11 29 'upgrade.applied'
        Assert-Versions $report.upgrade.migrationsAfter 1 29 'upgrade.migrationsAfter'
        Assert-Node $report.upgrade.secondRunApplied '#array' 'upgrade.secondRunApplied'
        Assert-Same $report.upgrade.secondRunApplied.Count 0 'upgrade.secondRunApplied'
    }
    if ($report.steps.Contains('smoke')) {
        Assert-Node $report.smoke @{
            'swaps' = @{
                'classification' = 'PASS'
                'activeSwapClaims' = 5
            }
            'deliveries' = @{
                'migration' = '0026_purchase_order_delivery_evidence'
                'revisions' = 9
                'receipts' = 9
                'terminalSnapshots' = 1
                'originalReplayAndTerminalComparisonVerified' = $true
            }
            'purchasing' = @{
                'migration' = '0024_bounded_purchase_orders'
                'suppliers' = 2
                'orders' = 8
                'lines' = 6
                'receipts' = 27
                'allEightKindsAndExactReplayVerified' = $true
            }
            'transfers' = @{
                'migration' = '0023_one_way_shift_transfers'
                'requests' = 9
                'receipts' = 21
                'taskLinks' = 1
                'exactReplayVerified' = $true
                'handoffClaims' = @{
                    'activeTransferClaims' = 2
                    'staleActiveTransferCount' = 1
                    'claimsAndParentsDigest' = '#md5'
                    'exactScopedParentConsistencyVerified' = $true
                }
            }
            'recipes' = @{
                'preparationMigration' = '0022_preparation_batches'
                'assignmentMigration' = '0025_planned_preparation_assignments'
                'assignmentCount' = 7
                'assignmentReceipts' = 12
                'preparationBatches' = 9
                'preparationReceipts' = 20
                'preparationCorrections' = 4
                'preparationReplayAndZeroVerified' = $true
                'migration' = '0021_recipe_compositions'
                'recipeCount' = 3
                'revisionCount' = 7
                'ingredientCount' = 14
                'replayVerified' = $true
                'runtimeProtections' = $true
            }
            'knowledge' = @{
                'migration' = '0017_approved_operational_knowledge'
                'articleCount' = 3
                'revisionCount' = 8
                'replayVerified' = $true
                'runtimeProtections' = $true
            }
            'guidance' = @{
                'migration' = '0018_task_knowledge_guidance'
                'completedPinnedTask' = $true
                'historicalRevision' = 1
                'articleRetired' = $true
                'runtimeProtections' = $true
            }
            'planogramGuidance' = @{
                'migration' = '0019_task_planogram_guidance'
                'exactPinPreserved' = $true
                'historicalContextualRead' = $true
                'retiredReassigned' = $true
                'runtimeProtections' = $true
            }
            'merchandising' = @{
                'revisionCount' = 2
                'assignmentCount' = 3
                'pinnedPrint' = $true
            }
            'ready' = $true
            'adminLogin' = $true
            'workerLogin' = $true
            'shiftDetail' = @{
                'status' = 'published'
                'taskCount' = 4
                'states' = @{
                    'in_progress' = 1
                    'blocked' = 1
                    'completed' = 1
                    'cancelled' = 1
                }
            }
            'executionReads' = @{
                'in_progress' = 'in_progress'
                'blocked' = 'blocked'
                'completed' = 'completed'
                'cancelled' = 'cancelled'
            }
            'employeeHome' = @{
                'itemCount' = 1
                'openShiftVisible' = $true
                'openTaskVisible' = $true
            }
            'cancellation' = @{
                'shiftStatus' = 'cancelled'
                'shiftVersion' = 3
                'taskStatus' = 'cancelled'
                'taskVersion' = 2
                'cancellationVersion' = 2
            }
            'readBack' = @{
                'status' = 'cancelled'
                'version' = 2
                'hasCancellationEvidence' = $true
            }
            'amendment' = @{
                'shiftStatus' = 'published'
                'shiftVersion' = 3
                'amendmentVersion' = 2
                'auditVerified' = $true
            }
            'articleMaster' = @{
                'created' = $true
                'readBack' = $true
                'auditVerified' = $true
            }
            'assortment' = @{
                'created' = $true
                'readBack' = $true
                'auditVerified' = $true
            }
            'stock' = @{
                'opened' = $true
                'adjusted' = $true
                'readBack' = $true
                'movementHistory' = 2
                'auditVerified' = $true
            }
            'auditVerified' = $true
            'correlationShared' = $true
        } 'smoke'
        Assert-Digests $report.smoke.swaps.tables @{ workforce_shift_swap_requests = 8; workforce_shift_swap_legs = 15; workforce_shift_swap_commands = 23; task_swap_links = 2 } 'smoke.swaps.tables'
        Assert-Digests $report.smoke.quantities @{ inventory_quantity_profiles = 1; inventory_quantity_revisions = 1; inventory_quantity_commands = 1; stock_quantity_bindings = 1; stock_quantity_corrections = 1 } 'smoke.quantities'
        Assert-Digests $report.smoke.historicalTransfers @{ workforce_shift_transfer_requests = 9; workforce_shift_transfer_commands = 21; task_transfer_links = 1 } 'smoke.historicalTransfers'
    }
    if ($report.steps.Contains('recoveryVerify')) {
        Assert-Node $report.recovery @{
            'targetDatabase' = '#text'
            'targetMigrationCount' = 10
            'targetHasNoPostPrefixColumns' = $true
            'evidenceProjectionsMatchPreUpdate' = $true
            'sequencesMatchPreUpdate' = $true
            'activeSessions' = 0
            'activePluginTokens' = 0
            'runtimeConnectCatalog' = $false
            'runtimeConnectionRejected' = $true
            'accountsPresent' = $true
            'bootstrapSingleton' = $true
            'targetPreUpdateBusinessState' = $true
            'sourceAtLatest' = $true
            'sourceSmokeEvidencePresent' = $true
            'sourceDistinctFromTarget' = $true
            'sourceHandoffClaimsPreserved' = $true
            'sourceSwapEvidencePreserved' = $true
            'sourceQuantityEvidencePreserved' = $true
            'sourceHistoricalTransfersPreserved' = $true
            'targetPredatesHandoffClaims' = $true
        } 'recovery'
        Assert-Same $report.recovery.targetDatabase $report.recoveryTargetDatabase 'recovery.targetDatabase'
        Assert-Versions $report.recovery.targetVersions 1 10 'recovery.targetVersions'
    }
}
