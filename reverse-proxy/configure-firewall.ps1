#requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'

$windowsRuleName = 'CaddyReverseProxyWindowsInbound'
$hyperVRuleName = 'CaddyReverseProxyInbound'
$meshnetWindowsRuleName = 'CCPocketBridgeMeshnetWindowsInbound'
$meshnetHyperVRuleName = 'CCPocketBridgeMeshnetInbound'
$wslCreatorId = '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}'
$caddyPorts = @('18080', '18443', '18765')
$meshnetAddressRange = '100.64.0.0/10'

Remove-NetFirewallRule -Name $windowsRuleName -ErrorAction SilentlyContinue
Remove-NetFirewallHyperVRule -Name $hyperVRuleName -ErrorAction SilentlyContinue
Remove-NetFirewallRule -Name $meshnetWindowsRuleName -ErrorAction SilentlyContinue
Remove-NetFirewallHyperVRule -Name $meshnetHyperVRuleName -ErrorAction SilentlyContinue

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

New-NetFirewallRule `
    -Name $meshnetWindowsRuleName `
    -DisplayName 'CC Pocket Bridge over Meshnet' `
    -Direction Inbound `
    -Action Allow `
    -Protocol TCP `
    -LocalPort '8765' `
    -RemoteAddress $meshnetAddressRange `
    -Profile Domain,Private,Public | Out-Null

New-NetFirewallHyperVRule `
    -Name $meshnetHyperVRuleName `
    -DisplayName 'CC Pocket Bridge over Meshnet' `
    -Direction Inbound `
    -VMCreatorId $wslCreatorId `
    -Protocol TCP `
    -LocalPorts '8765' `
    -RemoteAddresses $meshnetAddressRange `
    -Action Allow | Out-Null

Write-Output 'Allowed Caddy TCP ports 18080, 18443 and 18765. Allowed Bridge TCP port 8765 only from Meshnet addresses in 100.64.0.0/10.'
