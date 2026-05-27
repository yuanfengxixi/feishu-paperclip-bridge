# Install at: C:\Users\<you>\add-feishu-routes.ps1
# Run as Administrator (right-click → 以管理员身份运行)
# OR: Start-Process powershell -Verb RunAs -ArgumentList '-File','C:\path\to\add-feishu-routes.ps1'
#
# Purpose: same as wsl/feishu-routes.sh but for the Windows host — adds
# persistent static routes so Feishu CIDRs bypass FlClash/Clash Verge TUN
# adapter, routing through the real WLAN adapter to the LAN gateway.
#
# PolicyStore PersistentStore = survives reboot.
# PolicyStore ActiveStore = takes effect immediately (no reboot needed).
# We write to both so it works now AND after restart.

$cidrs = @('111.1.166.0/24', '112.13.108.0/24', '223.95.56.0/24', '39.173.165.0/24')
$gw    = '192.168.0.1'    # adjust to your LAN gateway
$alias = 'WLAN'           # adjust if you're on Ethernet (run `Get-NetAdapter` to see)

foreach ($c in $cidrs) {
    Get-NetRoute -DestinationPrefix $c -ErrorAction SilentlyContinue | Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
    try {
        New-NetRoute -DestinationPrefix $c -InterfaceAlias $alias -NextHop $gw -RouteMetric 1 -PolicyStore PersistentStore -ErrorAction Stop | Out-Null
        Write-Host "OK persistent: $c via $gw on $alias"
    } catch {
        Write-Host "FAIL persistent: $c : $($_.Exception.Message)"
    }
    try {
        New-NetRoute -DestinationPrefix $c -InterfaceAlias $alias -NextHop $gw -RouteMetric 1 -PolicyStore ActiveStore -ErrorAction Stop | Out-Null
        Write-Host "OK active: $c"
    } catch {
        Write-Host "FAIL active: $c : $($_.Exception.Message)"
    }
}

# Also pin Feishu hostnames in Windows hosts file as a belt-and-suspenders fix.
# Without this, FlClash's DNS layer can still return fake-IPs before TCP routing
# kicks in.
$hostsFile = "$env:SystemRoot\System32\drivers\etc\hosts"
$marker = "# --- feishu fixed IPs ---"
$content = Get-Content $hostsFile -Raw
if ($content -notmatch [regex]::Escape($marker)) {
    $entries = @"

$marker
111.1.166.68    open.feishu.cn
112.13.108.17   open.feishu.cn
39.173.165.166  msg-frontier.feishu.cn
39.173.165.166  open-callback-ws.feishu.cn
39.173.165.166  lark-msg-frontier.feishu.cn
"@
    Add-Content -Path $hostsFile -Value $entries -Encoding ASCII
    Write-Host "hosts: appended"
} else {
    Write-Host "hosts: already has entries"
}
Write-Host "`nAll done. Press Enter to close this window..."
$null = Read-Host
