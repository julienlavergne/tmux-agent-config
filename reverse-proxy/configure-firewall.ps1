#requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'

$windowsRuleName = 'CaddyReverseProxyWindowsInbound'
$hyperVRuleName = 'CaddyReverseProxyInbound'
$wslCreatorId = '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}'
$caddyPorts = @('18080', '18443', '18765')

Remove-NetFirewallRule -Name $windowsRuleName -ErrorAction SilentlyContinue
Remove-NetFirewallHyperVRule -Name $hyperVRuleName -ErrorAction SilentlyContinue

New-NetFirewallRule `
    -Name $windowsRuleName `
    -DisplayName 'Caddy reverse proxy high ports' `
    -Direction Inbound `
    -Action Allow `
    -Protocol TCP `
    -LocalPort $caddyPorts `
    -Profile Domain,Private,Public | Out-Null

New-NetFirewallHyperVRule `
    -Name $hyperVRuleName `
    -DisplayName 'Caddy reverse proxy high ports' `
    -Direction Inbound `
    -VMCreatorId $wslCreatorId `
    -Protocol TCP `
    -LocalPorts $caddyPorts `
    -Action Allow | Out-Null

Write-Output 'Allowed inbound TCP ports 18080, 18443 and 18765 for the Caddy proxy.'
