#requires -Version 7.4

# Guards the sanitized acceptance report. Dot-sourced by the acceptance runner
# and by scripts/backup/Test-BackupAcceptanceRedaction.ps1.
function Assert-BackupAcceptanceReport {
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
    $schema = 'storeos.p416.b4.backup.v1'
    $manifestPaths = @('apps/server/tool/backup_restore_fixture.dart', 'apps/server/tool/shift_swap_recovery_acceptance.dart', 'apps/server/tool/shift_transfer_acceptance.dart', 'scripts/backup/Run-BackupRestoreAcceptance.ps1', 'scripts/backup/Assert-BackupAcceptanceReport.ps1')
    $phases = @('createSourceDatabase', 'prepare', 'backup', 'restore', 'verify', 'corruptionRejected')
    $failureSteps = @('create-source-database', 'prepare', 'backup', 'restore', 'verify', 'corruption')
    if ($report -isnot [System.Collections.IDictionary]) { throw 'Report must be an object.' }
    $id = $report['runId']
    $ownedNames = @("storeos_backup_accept_$id", "storeos_restore_bkacc_$id", "storeos_restore_bkacc_${id}c")
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
            '#bool' { $Value -is [bool]; break }
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
    Assert-Node $report @{ restoreDatabase = $ownedNames[1]; corruption = @{ rejected = $report.steps.Contains('corruptionRejected'); targetRemoved = $(if ($pass) { $true } else { '#bool' }) } }
    if ($report.operatingDatabase -cin $ownedNames) { throw 'Operating database is a recovery target.' }
    if (!$legacyFailure) {
        if ($historicalB4Failure -and $report.schemaState -is [string]) {
            Assert-Node $report.schemaState 'source-and-restored-0001-0029' 'historical schemaState'
        } else {
            Assert-Node $report @{ schemaState = @{ source = $(if ($report.steps.Contains('prepare')) { '0001-0029' } else { 'NOT VERIFIED' }); restored = $(if ($report.steps.Contains('restore')) { '0001-0029' } else { 'NOT VERIFIED; isolated target only' }) } }
        }
        Assert-Node $report @{ failureInjection = '#text' }
        if ($report.failureInjection -cnotin @('none', 'prepare', 'backup', 'restore', 'verify', 'corruption', 'wrong-key', 'interrupted-archive', 'invalid-archive', 'cleanup') -or ($pass -and $report.failureInjection -cne 'none')) { throw 'Result contradicts failure injection.' }
        # Earlier retained B4 FAIL reports predate negativeRecoveryProof.
        if ($pass -or $report.Contains('negativeRecoveryProof')) {
            $negative = $report.failureInjection -cin @('wrong-key', 'interrupted-archive', 'invalid-archive') -and $report.failedStep -ceq 'restore'
            Assert-Node $report @{ negativeRecoveryProof = @{ scenario = $report.failureInjection; restoreRejected = '#bool'; unexpectedRestoreSuccess = '#bool' } }
            $proof = $report.negativeRecoveryProof
            # An unexpected restore success is legitimate FAIL evidence. Retain
            # it as such; it must never become successful recovery acceptance.
            if (($proof.restoreRejected -and $proof.unexpectedRestoreSuccess) -or
                ((!$negative -or $pass) -and ($proof.restoreRejected -or $proof.unexpectedRestoreSuccess))) {
                throw 'Result contradicts negative recovery evidence.'
            }
        }
    }
    if (!$pass) { return }
    if (!$report.Contains('verification')) { throw 'Missing verification phase evidence.' }
    if ($report.steps.Contains('verify')) {
        $v = $report.verification
        Assert-Node $v @{
            'runId' = '#text'
            'sourceDatabase' = '#text'
            'targetDatabase' = '#text'
            'sourcePreserved' = $true
            'swaps' = @{
                'classification' = 'PASS'
                'activeSwapClaims' = 5
            }
            'restoredSwapAuthorization' = @{
                'classification' = 'PASS'
                'runtimeRoleVerified' = $true
                'staleCredentialDenials' = 4
                'previouslyActiveSourceSessionDenied' = $true
                'revokedCredentialDenials' = 2
                'exactReplays' = 23
                'scopedReadAndReplayDenialsVerified' = $true
                'oldConsentAfterAccountChangeRefused' = $true
                'explicitClosures' = 3
                'ownedClaimsReleased' = 5
                'terminalReplayClaimsRemainReleased' = $true
                'oldReceiptsUnchanged' = 23
                'legacyTransferAndQuantityEvidenceUnchanged' = $true
                'capturedConsentAndPairedWorkUnchanged' = $true
            }
            'handoffClaims' = @{
                'activeTransferClaims' = 2
                'staleActiveTransferCount' = 1
                'claimsAndParentsDigest' = '#md5'
                'exactScopedParentConsistencyVerified' = $true
                'sourceAndRestoredClaimsEqual' = $true
            }
            'sequences' = @{
                'audit_entries_id_seq' = @{
                    'sourceLastValue' = '#digits'
                    'sourceIsCalled' = $true
                    'restoredLastValue' = '#digits'
                    'restoredIsCalled' = $true
                }
                'plugin_inbox_id_seq' = @{
                    'sourceLastValue' = '#digits'
                    'sourceIsCalled' = $false
                    'restoredLastValue' = '#digits'
                    'restoredIsCalled' = $false
                }
            }
            'sourceActiveSessions' = '#positive'
            'restoredActiveSessions' = 0
            'sourceActivePluginTokens' = '#positive'
            'restoredActivePluginTokens' = 0
            'sourceRuntimeConnect' = $true
            'restoredRuntimeConnect' = $false
            'restoredRuntimeConnectionRejected' = $true
            'preparation' = @{
                'historicalSource' = @{
                    'batchId' = '#uuid'
                    'recipeId' = '#uuid'
                    'pinnedR1Id' = '#uuid'
                    'laterR2Id' = '#uuid'
                    'recipeRetired' = $true
                    'laterPublicationExists' = $true
                    'employeeContextR1Verified' = $true
                    'managerContextR1Verified' = $true
                    'standaloneEmployeeExcluded' = $true
                    'otherEmployeeDenied' = $true
                    'retiredWarningVerified' = $true
                    'contextReadsPreserveBusinessAndAudit' = $true
                    'frozenContentSha256' = '#sha256'
                    'laterContentSha256' = '#sha256'
                }
                'historicalRestored' = @{
                    'batchId' = '#uuid'
                    'recipeId' = '#uuid'
                    'pinnedR1Id' = '#uuid'
                    'laterR2Id' = '#uuid'
                    'recipeRetired' = $true
                    'laterPublicationExists' = $true
                    'employeeContextR1Verified' = $true
                    'managerContextR1Verified' = $true
                    'standaloneEmployeeExcluded' = $true
                    'otherEmployeeDenied' = $true
                    'retiredWarningVerified' = $true
                    'contextReadsPreserveBusinessAndAudit' = $true
                    'frozenContentSha256' = '#sha256'
                    'laterContentSha256' = '#sha256'
                }
                'sourceAndRestoredHistoricalProofEqual' = $true
                'migration' = '0022_preparation_batches'
                'assignmentCount' = 7
                'assignmentReceiptCount' = 12
                'batchCount' = 9
                'receiptCount' = 20
                'correctionCount' = 4
                'deterministicEvidencePreserved' = $true
                'ownAndManagerAuthorizationVerified' = $true
                'otherEmployeeDenied' = $true
                'exactContextAndReplayVerified' = $true
                'correctedZeroVerified' = $true
                'runtimeGrantsVerified' = $true
            }
            'recipes' = @{
                'migration' = '0021_recipe_compositions'
                'retainedStatesVerified' = $true
                'frozenContentVerified' = $true
                'employeeVisibilityVerified' = $true
                'managerHistoryVerified' = $true
                'replayVerified' = $true
                'authorizationVerified' = $true
            }
            'guidance' = @{
                'schemaVersion' = 4
                'exactPlanogramPinPreserved' = $true
                'retiredReassignedLayoutReadVerified' = $true
                'historicalRevision' = 1
                'completedPinPreserved' = $true
                'contextualReadVerified' = $true
                'arbitraryHistoryDenied' = $true
                'runtimeProtections' = $true
                'articleAssortmentStockMovementHashesMatch' = $true
                'currentA2R2ReadVerified' = $true
                'currentArticleAssortmentNonemptyStockVerified' = $true
                'planogramHistoricalDenials' = 5
                'planogramConfiguredLocationDenials' = 4
                'planogramConfiguredLocationReturnVerified' = $true
                'planogramDatabaseRejections' = 14
                'planogramGeneratedColumnsVerified' = 6
            }
        } 'verification'
        Assert-Same $v.runId $report.runId 'verification.runId'
        Assert-Same $v.sourceDatabase $report.sourceDatabase 'verification.sourceDatabase'
        Assert-Same $v.targetDatabase $report.restoreDatabase 'verification.targetDatabase'
        Assert-Node $v.tables '#object' 'verification.tables'
        $tables = @('workforce_shift_swap_requests', 'workforce_shift_swap_legs', 'workforce_shift_swap_commands', 'task_swap_links', 'inventory_quantity_profiles', 'inventory_quantity_revisions', 'inventory_quantity_commands', 'stock_quantity_bindings', 'stock_quantity_corrections', 'schema_migrations', 'purchasing_suppliers', 'purchasing_orders', 'purchasing_order_lines', 'purchasing_commands', 'purchasing_delivery_revisions', 'purchasing_delivery_revision_lines', 'purchasing_delivery_commands', 'purchasing_delivery_terminal_snapshots', 'articles', 'article_location_assortment', 'stock_levels', 'stock_movements', 'stock_counts', 'stock_count_lines', 'stock_count_rounds', 'stock_count_observations', 'stock_count_commands', 'production_recipes', 'production_recipe_revisions', 'production_recipe_ingredients', 'production_preparation_assignments', 'production_preparation_assignment_commands', 'production_preparation_batches', 'production_preparation_batch_commands', 'production_preparation_batch_count_corrections', 'knowledge_articles', 'knowledge_revisions', 'shifts', 'shift_template_selections', 'workforce_shift_transfer_requests', 'workforce_shift_transfer_commands', 'workforce_shift_handoff_claims', 'task_transfer_links', 'merchandising_fixtures', 'merchandising_planograms', 'merchandising_planogram_revisions', 'merchandising_planogram_zones', 'merchandising_planogram_placements', 'merchandising_planogram_assignments', 'task_template_revisions', 'task_instances', 'task_step_results', 'task_numeric_attempts', 'task_blockings', 'task_execution_commands', 'audit_entries')
        Assert-Same $v.tables.Count $tables.Count 'verification.tables'
        foreach ($table in $tables) {
            Assert-Node $v.tables @{ $table = @{ sourceCount = '#positive'; sourceHash = '#sha256'; restoredCount = '#positive'; restoredHash = '#sha256' } } 'verification.tables'
            $state = $v.tables[$table]
            Assert-Same $state.sourceCount $state.restoredCount "tables.$table.count"
            Assert-Same $state.sourceHash $state.restoredHash "tables.$table.sha256"
        }
        Assert-Same $v.tables.schema_migrations.sourceCount 29 'schema migration count'
        $swapCounts = @{ workforce_shift_swap_requests = 8; workforce_shift_swap_legs = 15; workforce_shift_swap_commands = 23; task_swap_links = 2 }
        Assert-Digests $v.swaps.tables $swapCounts 'swaps.tables'
        foreach ($table in $swapCounts.Keys) {
            Assert-Same $v.tables[$table].sourceCount $v.swaps.tables[$table].count "swaps.$table.count"
            Assert-Same $v.tables[$table].sourceHash $v.swaps.tables[$table].sha256 "swaps.$table.sha256"
        }
        Assert-Same $v.tables.workforce_shift_handoff_claims.sourceCount ($v.swaps.activeSwapClaims + $v.handoffClaims.activeTransferClaims) 'shared claim count'
        Assert-Same $v.tables.workforce_shift_transfer_requests.sourceCount 9 'historical transfer requests'
        Assert-Same $v.tables.workforce_shift_transfer_commands.sourceCount 21 'historical transfer receipts'
        Assert-Same $v.tables.task_transfer_links.sourceCount 1 'historical transfer links'
        foreach ($table in @('inventory_quantity_profiles', 'inventory_quantity_revisions', 'inventory_quantity_commands', 'stock_quantity_bindings', 'stock_quantity_corrections')) {
            Assert-Same $v.tables[$table].sourceCount 1 "quantities.$table.count"
        }
        foreach ($entry in @{
            production_preparation_assignments = $v.preparation.assignmentCount
            production_preparation_assignment_commands = $v.preparation.assignmentReceiptCount
            production_preparation_batches = $v.preparation.batchCount
            production_preparation_batch_commands = $v.preparation.receiptCount
            production_preparation_batch_count_corrections = $v.preparation.correctionCount
        }.GetEnumerator()) { Assert-Same $v.tables[$entry.Key].sourceCount $entry.Value "preparation.$($entry.Key).count" }
        foreach ($sequence in @('audit_entries_id_seq', 'plugin_inbox_id_seq')) {
            $s = $v.sequences[$sequence]
            Assert-Same $s.sourceLastValue $s.restoredLastValue "sequences.$sequence.value"
            Assert-Same $s.sourceIsCalled $s.restoredIsCalled "sequences.$sequence.called"
        }
        foreach ($name in $v.preparation.historicalSource.Keys) { Assert-Same $v.preparation.historicalSource[$name] $v.preparation.historicalRestored[$name] "historical preparation.$name" }
    } elseif ($null -ne $report.verification -and $report.verification -isnot [System.Collections.IDictionary]) { throw 'Invalid incomplete verification evidence.' }
}
