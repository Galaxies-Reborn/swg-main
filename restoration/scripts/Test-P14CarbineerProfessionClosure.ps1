param([Parameter(Mandatory=$true)][string]$SourceRoot,[ValidateSet("Build","Ready")][string]$Expectation="Build")
$ErrorActionPreference="Stop"
$root=Split-Path -Parent $PSScriptRoot
$m=Get-Content (Join-Path $root "manifest.json") -Raw|ConvertFrom-Json
$c=Get-Content (Join-Path $root ([string]$m.contracts.p14CarbineerProfessionClosure)) -Raw|ConvertFrom-Json
$skill=Join-Path (Resolve-Path $SourceRoot).Path ([string]$c.sourceFiles.skillTable
)
$lines=Get-Content $skill;$e=$c.publish14Evidence
$family=@($lines|?{$_.StartsWith([string]$e.family.prefix)-and-not$_.StartsWith([string]$e.excludedCompatibilityPrefix)}|Sort-Object)
$text=($family-join"`n")+"`n";$sha=[Security.Cryptography.SHA256]::Create()
try{$hash=($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text))|%{$_.ToString("x2")})-join""}finally{$sha.Dispose()}
$compat=@($lines|?{$_.StartsWith([string]$e.excludedCompatibilityPrefix)})
if($family.Count-ne19-or$compat.Count-ne7-or$hash-cne[string]$e.family.normalizedSortedRowsSha256){throw "Carbineer family check failed"}
if($Expectation-eq"Ready"){$b=$c.buildEvidence;$p=Join-Path $root ([string]$b.overlayPatch-replace"^restoration/","");if((Get-FileHash $skill).Hash.ToLower()-cne[string]$b.sourceSha256."skills.tab"-or(Get-FileHash $p).Hash.ToLower()-cne[string]$b.overlayPatchSha256-or-not$c.runtimeEvidence.graphVisible-or-not$c.runtimeEvidence.serverHealthy){throw "Carbineer ready check failed"}}
Write-Host "Publish 14.1 Carbineer profession closure passed."
