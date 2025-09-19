# PowerShell代理配置与自动切换
_Exported on 2025/9/19 at GMT+8 15:30:59 from Cursor (1.6.26)_

---

**User**

我的需求是：如果用环境变量给powershell配置代理，那么配置后如果关闭了代理是否会造成powershell无法联网，有办法自动切换吗？

deepseek给了我这个配置函数，它合适吗？可以直接使用还是仍然需要优化？

function Set-SmartProxy {
    # 测试代理端口是否开放（例如等待0.5秒）
    $testConnection = Test-NetConnection -ComputerName 127.0.0.1 -Port 7890 -InformationLevel Quiet -WarningAction SilentlyContinue

    if ($testConnection) {
        # 代理端口通，设置环境变量
        $env:HTTP_PROXY = "http://127.0.0.1:7890"
        $env:HTTPS_PROXY = "http://127.0.0.1:7890"
        Write-Host "✅ 代理已开启 (127.0.0.1:7890)" -ForegroundColor Green
    } else {
        # 代理端口不通，清除环境变量，确保直连
        Remove-Item Env:HTTP_PROXY -ErrorAction SilentlyContinue
        Remove-Item Env:HTTPS_PROXY -ErrorAction SilentlyContinue
        Write-Host "ℹ️  代理未运行，已切换为直连模式" -ForegroundColor Yellow
    }
}

function Unset-Proxy {
    Remove-Item Env:HTTP_PROXY -ErrorAction SilentlyContinue
    Remove-Item Env:HTTPS_PROXY -ErrorAction SilentlyContinue
    Write-Host "✅ 代理设置已清除" -ForegroundColor Green
}

# 可选：每次启动 PowerShell 时自动检测一次
# Set-SmartProxy


---

**Cursor**

### 简短回答
- 会的：如果用环境变量指向已关闭的代理，很多命令会走“坏代理”而超时，直到你清理这些环境变量。
- 你的函数能用，思路正确（端口通就设置，不通就清理），放进 `$PROFILE` 开机/启动时执行即可。
- 建议优化：同时设置/清理大小写变量、加 `NO_PROXY`、可选 `ALL_PROXY`（socks）、支持持久化到用户环境以及可选后台自动切换。

### 可直接替换的改进版（含自动切换可选）
```powershell
# 轻量端口探测（更快，带超时）
function Test-TcpOpen {
    param(
        [string]$Host = '127.0.0.1',
        [int]$Port = 7890,
        [int]$TimeoutMs = 300
    )
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect($Host, $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { $client.Close(); return $false }
        $client.EndConnect($iar); $client.Close(); return $true
    } catch { return $false }
}

function Set-EnvVar {
    param(
        [string]$Name,
        [string]$Value,
        [ValidateSet('Process','User','Machine')] [string]$Scope = 'Process'
    )
    # 进程内立即生效
    if ($null -ne $Value) { Set-Item -Path "Env:$Name" -Value $Value -ErrorAction SilentlyContinue }
    else { Remove-Item -Path "Env:$Name" -ErrorAction SilentlyContinue }

    # 可选持久化（User/Machine），Machine 需要管理员
    if ($Scope -ne 'Process') {
        [Environment]::SetEnvironmentVariable($Name, $Value, $Scope)
    }
}

function Set-SmartProxy {
    param(
        [string]$Host = '127.0.0.1',
        [int]$HttpPort = 7890,
        [int]$SocksPort = 7891,
        [ValidateSet('Process','User','Machine')] [string]$Scope = 'Process',
        [string]$NoProxy = 'localhost,127.0.0.1,::1,.local,.lan',
        [switch]$UseSocks,      # 需要时设置 ALL_PROXY（常见为 7891）
        [switch]$Quiet
    )

    $ok = Test-TcpOpen -Host $Host -Port $HttpPort
    if ($ok) {
        $http = "http://$Host:$HttpPort"
        $vars = @{
            'HTTP_PROXY'  = $http;  'http_proxy'  = $http;
            'HTTPS_PROXY' = $http;  'https_proxy' = $http;
            'NO_PROXY'    = $NoProxy; 'no_proxy'  = $NoProxy
        }
        if ($UseSocks) {
            $socks = "socks5://$Host:$SocksPort"
            $vars['ALL_PROXY'] = $socks
            $vars['all_proxy'] = $socks
        }
        foreach ($k in $vars.Keys) { Set-EnvVar -Name $k -Value $vars[$k] -Scope $Scope }
        if (-not $Quiet) { Write-Host "✅ 代理已开启 ($Host:$HttpPort)$($UseSocks ? " + SOCKS:$SocksPort" : "")，Scope=$Scope" -ForegroundColor Green }
    } else {
        Unset-Proxy -Scope $Scope -Quiet:$Quiet
    }
}

function Unset-Proxy {
    param([ValidateSet('Process','User','Machine')] [string]$Scope = 'Process', [switch]$Quiet)
    foreach ($k in 'HTTP_PROXY','http_proxy','HTTPS_PROXY','https_proxy','ALL_PROXY','all_proxy','NO_PROXY','no_proxy') {
        Set-EnvVar -Name $k -Value $null -Scope $Scope
    }
    if (-not $Quiet) { Write-Host "ℹ️  已切换直连（已清理代理变量），Scope=$Scope" -ForegroundColor Yellow }
}

# 可选：后台定时自动切换（监控端口，掉线即清理，恢复即设置）
$script:SmartProxyTimer = $null
function Start-ProxyAutoSwitch {
    param(
        [int]$IntervalSeconds = 5,
        [string]$Host = '127.0.0.1',
        [int]$HttpPort = 7890,
        [int]$SocksPort = 7891,
        [ValidateSet('Process','User','Machine')] [string]$Scope = 'Process',
        [string]$NoProxy = 'localhost,127.0.0.1,::1,.local,.lan',
        [switch]$UseSocks
    )
    Stop-ProxyAutoSwitch | Out-Null
    $script:SmartProxyTimer = New-Object System.Timers.Timer
    $script:SmartProxyTimer.Interval = [double]($IntervalSeconds * 1000)
    $script:SmartProxyTimer.AutoReset = $true
    $action = {
        try {
            Set-SmartProxy -Host $using:Host -HttpPort $using:HttpPort -SocksPort $using:SocksPort -Scope $using:Scope -NoProxy $using:NoProxy -UseSocks:$using:UseSocks -Quiet
        } catch { }
    }
    Register-ObjectEvent -InputObject $script:SmartProxyTimer -EventName Elapsed -Action $action | Out-Null
    $script:SmartProxyTimer.Start()
    Write-Host "🔁 已启动自动切换（每 $IntervalSeconds 秒检测 $Host:$HttpPort）" -ForegroundColor Cyan
}

function Stop-ProxyAutoSwitch {
    if ($script:SmartProxyTimer) {
        $script:SmartProxyTimer.Stop()
        $script:SmartProxyTimer.Dispose()
        $script:SmartProxyTimer = $null
        Write-Host "⏹️  已停止自动切换" -ForegroundColor Cyan
    }
}
```

### 怎么用（最简）
- 仅当前会话智能切换（HTTP 端口 7890）:
```powershell
Set-SmartProxy
```
- 同时设置 SOCKS（常见 Clash: 7891）:
```powershell
Set-SmartProxy -UseSocks
```
- 清理（直连）:
```powershell
Unset-Proxy
```
- 开机/每次启动自动：把下面一行加到 `$PROFILE`，或手动开个后台监控
```powershell
Start-ProxyAutoSwitch -IntervalSeconds 10 -UseSocks
```

### 说明与注意
- 环境变量法只影响认可这些变量的程序（如 PowerShell 7 的 Invoke-WebRequest、curl、pip、git 等）。不影响使用系统/WinHTTP 代理的程序（如部分微软组件、旧 .NET/IE 栈）。
- 若需要系统层代理，请单独在“Windows 设置-网络-代理”或使用 `netsh winhttp set proxy` 配置；这与环境变量互不覆盖。
- 大小写变量同时设置是为兼容性（部分工具只认小写）。
- `NO_PROXY` 防止本地/内网流量走代理，可根据你的内网域名补充。

如果你只想要“会话内开/关且自动兜底直连”，你的原函数已足够；上面的版本主要加强了兼容性和自动化。

```powershell
# 轻量端口探测（更快，带超时）
function Test-TcpOpen {
    param(
        [string]$Host = '127.0.0.1',
        [int]$Port = 7890,
        [int]$TimeoutMs = 300
    )
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect($Host, $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { $client.Close(); return $false }
        $client.EndConnect($iar); $client.Close(); return $true
    } catch { return $false }
}

function Set-EnvVar {
    param(
        [string]$Name,
        [string]$Value,
        [ValidateSet('Process','User','Machine')] [string]$Scope = 'Process'
    )
    # 进程内立即生效
    if ($null -ne $Value) { Set-Item -Path "Env:$Name" -Value $Value -ErrorAction SilentlyContinue }
    else { Remove-Item -Path "Env:$Name" -ErrorAction SilentlyContinue }

    # 可选持久化（User/Machine），Machine 需要管理员
    if ($Scope -ne 'Process') {
        [Environment]::SetEnvironmentVariable($Name, $Value, $Scope)
    }
}

function Set-SmartProxy {
    param(
        [string]$Host = '127.0.0.1',
        [int]$HttpPort = 7890,
        [int]$SocksPort = 7891,
        [ValidateSet('Process','User','Machine')] [string]$Scope = 'Process',
        [string]$NoProxy = 'localhost,127.0.0.1,::1,.local,.lan',
        [switch]$UseSocks,      # 需要时设置 ALL_PROXY（常见为 7891）
        [switch]$Quiet
    )

    $ok = Test-TcpOpen -Host $Host -Port $HttpPort
    if ($ok) {
        $http = "http://$Host:$HttpPort"
        $vars = @{
            'HTTP_PROXY'  = $http;  'http_proxy'  = $http;
            'HTTPS_PROXY' = $http;  'https_proxy' = $http;
            'NO_PROXY'    = $NoProxy; 'no_proxy'  = $NoProxy
        }
        if ($UseSocks) {
            $socks = "socks5://$Host:$SocksPort"
            $vars['ALL_PROXY'] = $socks
            $vars['all_proxy'] = $socks
        }
        foreach ($k in $vars.Keys) { Set-EnvVar -Name $k -Value $vars[$k] -Scope $Scope }
        if (-not $Quiet) { Write-Host "✅ 代理已开启 ($Host:$HttpPort)$($UseSocks ? " + SOCKS:$SocksPort" : "")，Scope=$Scope" -ForegroundColor Green }
    } else {
        Unset-Proxy -Scope $Scope -Quiet:$Quiet
    }
}

function Unset-Proxy {
    param([ValidateSet('Process','User','Machine')] [string]$Scope = 'Process', [switch]$Quiet)
    foreach ($k in 'HTTP_PROXY','http_proxy','HTTPS_PROXY','https_proxy','ALL_PROXY','all_proxy','NO_PROXY','no_proxy') {
        Set-EnvVar -Name $k -Value $null -Scope $Scope
    }
    if (-not $Quiet) { Write-Host "ℹ️  已切换直连（已清理代理变量），Scope=$Scope" -ForegroundColor Yellow }
}

# 可选：后台定时自动切换（监控端口，掉线即清理，恢复即设置）
$script:SmartProxyTimer = $null
function Start-ProxyAutoSwitch {
    param(
        [int]$IntervalSeconds = 5,
        [string]$Host = '127.0.0.1',
        [int]$HttpPort = 7890,
        [int]$SocksPort = 7891,
        [ValidateSet('Process','User','Machine')] [string]$Scope = 'Process',
        [string]$NoProxy = 'localhost,127.0.0.1,::1,.local,.lan',
        [switch]$UseSocks
    )
    Stop-ProxyAutoSwitch | Out-Null
    $script:SmartProxyTimer = New-Object System.Timers.Timer
    $script:SmartProxyTimer.Interval = [double]($IntervalSeconds * 1000)
    $script:SmartProxyTimer.AutoReset = $true
    $action = {
        try {
            Set-SmartProxy -Host $using:Host -HttpPort $using:HttpPort -SocksPort $using:SocksPort -Scope $using:Scope -NoProxy $using:NoProxy -UseSocks:$using:UseSocks -Quiet
        } catch { }
    }
    Register-ObjectEvent -InputObject $script:SmartProxyTimer -EventName Elapsed -Action $action | Out-Null
    $script:SmartProxyTimer.Start()
    Write-Host "🔁 已启动自动切换（每 $IntervalSeconds 秒检测 $Host:$HttpPort）" -ForegroundColor Cyan
}

function Stop-ProxyAutoSwitch {
    if ($script:SmartProxyTimer) {
        $script:SmartProxyTimer.Stop()
        $script:SmartProxyTimer.Dispose()
        $script:SmartProxyTimer = $null
        Write-Host "⏹️  已停止自动切换" -ForegroundColor Cyan
    }
}
```

```powershell
Set-SmartProxy
```

```powershell
Set-SmartProxy -UseSocks
```

```powershell
Unset-Proxy
```

```powershell
Start-ProxyAutoSwitch -IntervalSeconds 10 -UseSocks
```

---

**User**

我认为启动时自动设置可能没必要，我认为在powershell启动时自动输出一行简要的提示以提示我可以使用哪个函数开启代理并使用哪个命令关闭

---

**Cursor**

### 可以，只在启动时给出一行提示
按你的想法，不自动设置代理，只在 PowerShell 启动时提示可用命令即可。把下面内容加到你的 `$PROFILE` 里即可。

#### 打开（或新建）`$PROFILE`
```powershell
if (-not (Test-Path $PROFILE)) { New-Item -Type File -Path $PROFILE -Force | Out-Null }
notepad $PROFILE
```

#### 在文件末尾加入一行“极简提示”
```powershell
Write-Host "提示: 运行 Set-SmartProxy 开启代理，运行 Unset-Proxy 关闭（仅当前会话）" -ForegroundColor DarkGray
```

#### 可选：带端口状态的简短提示（仍然不自动设置）
```powershell
$port = 7890
$up = Test-NetConnection -ComputerName 127.0.0.1 -Port $port -InformationLevel Quiet -WarningAction SilentlyContinue
$hint = if ($up) { "代理可能已运行(127.0.0.1:$port)" } else { "代理未运行" }
Write-Host "[$hint] 使用 Set-SmartProxy 开启，Unset-Proxy 关闭（会话内）" -ForegroundColor DarkGray
```

- 你已在别处定义了 `Set-SmartProxy` / `Unset-Proxy` 的话，上述提示会在每次启动时显示，但不会自动改动任何代理设置。  
- 之后想取消提示，只需从 `$PROFILE` 删除这几行即可。

- 简要
  - 提供了两种启动提示写法：极简固定提示、可选的端口状态提示。
  - 不自动切换代理，只提示你可用的开启/关闭命令。

```powershell
if (-not (Test-Path $PROFILE)) { New-Item -Type File -Path $PROFILE -Force | Out-Null }
notepad $PROFILE
```

```powershell
Write-Host "提示: 运行 Set-SmartProxy 开启代理，运行 Unset-Proxy 关闭（仅当前会话）" -ForegroundColor DarkGray
```

```powershell
$port = 7890
$up = Test-NetConnection -ComputerName 127.0.0.1 -Port $port -InformationLevel Quiet -WarningAction SilentlyContinue
$hint = if ($up) { "代理可能已运行(127.0.0.1:$port)" } else { "代理未运行" }
Write-Host "[$hint] 使用 Set-SmartProxy 开启，Unset-Proxy 关闭（会话内）" -ForegroundColor DarkGray
```

---

**User**

综合启动时的自动提示和刚才的配置，从头到尾整理一下配置顺序

---

**Cursor**

### 一次性完整配置顺序（会话内手动开关 + 启动时仅提示）

- 打开（或新建）`$PROFILE` 并编辑：
```powershell
if (-not (Test-Path $PROFILE)) { New-Item -Type File -Path $PROFILE -Force | Out-Null }
notepad $PROFILE
```

- 把下面整段粘贴到 `$PROFILE` 末尾，保存：
```powershell
# 1) 仅当前会话的智能设置/清理函数
function Set-SmartProxy {
    param(
        [string]$Host = '127.0.0.1',
        [int]$HttpPort = 7890,
        [switch]$UseSocks,
        [int]$SocksPort = 7891,
        [string]$NoProxy = 'localhost,127.0.0.1,::1,.local,.lan'
    )
    $ok = Test-NetConnection -ComputerName $Host -Port $HttpPort -InformationLevel Quiet -WarningAction SilentlyContinue
    if ($ok) {
        $http = "http://$Host:$HttpPort"
        $env:HTTP_PROXY  = $http;  $env:http_proxy  = $http
        $env:HTTPS_PROXY = $http;  $env:https_proxy = $http
        $env:NO_PROXY    = $NoProxy; $env:no_proxy  = $NoProxy
        if ($UseSocks) {
            $socks = "socks5://$Host:$SocksPort"
            $env:ALL_PROXY = $socks; $env:all_proxy = $socks
        }
        Write-Host "✅ 代理已开启 ($Host:$HttpPort)$($UseSocks ? " + SOCKS:$SocksPort" : "")" -ForegroundColor Green
    } else {
        Unset-Proxy
    }
}

function Unset-Proxy {
    foreach ($k in 'HTTP_PROXY','http_proxy','HTTPS_PROXY','https_proxy','ALL_PROXY','all_proxy','NO_PROXY','no_proxy') {
        Remove-Item Env:$k -ErrorAction SilentlyContinue
    }
    Write-Host "ℹ️  已切换直连（已清理代理变量）" -ForegroundColor Yellow
}

# 2) 启动时的极简提示（不自动设置）
$port = 7890
$up = Test-NetConnection -ComputerName 127.0.0.1 -Port $port -InformationLevel Quiet -WarningAction SilentlyContinue
$hint = if ($up) { "代理可能已运行(127.0.0.1:$port)" } else { "代理未运行" }
Write-Host "[$hint] 使用 Set-SmartProxy 开启，Unset-Proxy 关闭（会话内）" -ForegroundColor DarkGray
```

- 让配置立刻生效（或重开一个 PowerShell）：
```powershell
. $PROFILE
```

### 使用方法（手动）
- 开启代理（默认 HTTP/HTTPS 走 `127.0.0.1:7890`）：
```powershell
Set-SmartProxy
```
- 同时开启 SOCKS（常见为 `127.0.0.1:7891`）：
```powershell
Set-SmartProxy -UseSocks
```
- 关闭代理（直连）：
```powershell
Unset-Proxy
```

- 关键点
  - 仅设置当前会话的环境变量，不会影响系统或用户级环境。
  - 端口不通时，`Set-SmartProxy` 会自动清理并直连，避免“坏代理”导致卡住。
  - 已包含大小写变量与 `NO_PROXY`，兼容更多工具。

```powershell
if (-not (Test-Path $PROFILE)) { New-Item -Type File -Path $PROFILE -Force | Out-Null }
notepad $PROFILE
```

```powershell
# 1) 仅当前会话的智能设置/清理函数
function Set-SmartProxy {
    param(
        [string]$Host = '127.0.0.1',
        [int]$HttpPort = 7890,
        [switch]$UseSocks,
        [int]$SocksPort = 7891,
        [string]$NoProxy = 'localhost,127.0.0.1,::1,.local,.lan'
    )
    $ok = Test-NetConnection -ComputerName $Host -Port $HttpPort -InformationLevel Quiet -WarningAction SilentlyContinue
    if ($ok) {
        $http = "http://$Host:$HttpPort"
        $env:HTTP_PROXY  = $http;  $env:http_proxy  = $http
        $env:HTTPS_PROXY = $http;  $env:https_proxy = $http
        $env:NO_PROXY    = $NoProxy; $env:no_proxy  = $NoProxy
        if ($UseSocks) {
            $socks = "socks5://$Host:$SocksPort"
            $env:ALL_PROXY = $socks; $env:all_proxy = $socks
        }
        Write-Host "✅ 代理已开启 ($Host:$HttpPort)$($UseSocks ? " + SOCKS:$SocksPort" : "")" -ForegroundColor Green
    } else {
        Unset-Proxy
    }
}

function Unset-Proxy {
    foreach ($k in 'HTTP_PROXY','http_proxy','HTTPS_PROXY','https_proxy','ALL_PROXY','all_proxy','NO_PROXY','no_proxy') {
        Remove-Item Env:$k -ErrorAction SilentlyContinue
    }
    Write-Host "ℹ️  已切换直连（已清理代理变量）" -ForegroundColor Yellow
}

# 2) 启动时的极简提示（不自动设置）
$port = 7890
$up = Test-NetConnection -ComputerName 127.0.0.1 -Port $port -InformationLevel Quiet -WarningAction SilentlyContinue
$hint = if ($up) { "代理可能已运行(127.0.0.1:$port)" } else { "代理未运行" }
Write-Host "[$hint] 使用 Set-SmartProxy 开启，Unset-Proxy 关闭（会话内）" -ForegroundColor DarkGray
```

```powershell
. $PROFILE
```

```powershell
Set-SmartProxy
```

```powershell
Set-SmartProxy -UseSocks
```

```powershell
Unset-Proxy
```

---

**User**

如果把可选的启动时自动设置代理的配置也保留呢？

---

**Cursor**

### 整合版配置（启动仅提示；保留“可选：启动时自动设置一次”）
把下面整段粘贴到你的 `$PROFILE` 末尾，保存后执行 `. $PROFILE`。

```powershell
# 1) 仅当前会话的智能设置/清理函数
function Set-SmartProxy {
    param(
        [string]$Host = '127.0.0.1',
        [int]$HttpPort = 7890,
        [switch]$UseSocks,
        [int]$SocksPort = 7891,
        [string]$NoProxy = 'localhost,127.0.0.1,::1,.local,.lan'
    )
    $ok = Test-NetConnection -ComputerName $Host -Port $HttpPort -InformationLevel Quiet -WarningAction SilentlyContinue
    if ($ok) {
        $http = "http://$Host:$HttpPort"
        $env:HTTP_PROXY  = $http;  $env:http_proxy  = $http
        $env:HTTPS_PROXY = $http;  $env:https_proxy = $http
        $env:NO_PROXY    = $NoProxy; $env:no_proxy  = $NoProxy
        if ($UseSocks) {
            $socks = "socks5://$Host:$SocksPort"
            $env:ALL_PROXY = $socks; $env:all_proxy = $socks
        }
        Write-Host "✅ 代理已开启 ($Host:$HttpPort)$($UseSocks ? " + SOCKS:$SocksPort" : "")" -ForegroundColor Green
    } else {
        Unset-Proxy
    }
}

function Unset-Proxy {
    foreach ($k in 'HTTP_PROXY','http_proxy','HTTPS_PROXY','https_proxy','ALL_PROXY','all_proxy','NO_PROXY','no_proxy') {
        Remove-Item Env:$k -ErrorAction SilentlyContinue
    }
    Write-Host "ℹ️  已切换直连（已清理代理变量）" -ForegroundColor Yellow
}

# 2) 启动时提示（不自动设置）
$port = 7890
$up = Test-NetConnection -ComputerName 127.0.0.1 -Port $port -InformationLevel Quiet -WarningAction SilentlyContinue
$hint = if ($up) { "代理可能已运行(127.0.0.1:$port)" } else { "代理未运行" }
Write-Host "[$hint] 使用 Set-SmartProxy 开启，Unset-Proxy 关闭（会话内）" -ForegroundColor DarkGray

# 3) 可选：启动时自动设置一次（需要时取消注释任意一行）
# Set-SmartProxy
# Set-SmartProxy -UseSocks
```

使用方法（手动）：
- 开启代理（HTTP/HTTPS 走 127.0.0.1:7890）：`Set-SmartProxy`
- 同时开 SOCKS（127.0.0.1:7891）：`Set-SmartProxy -UseSocks`
- 关闭代理（直连）：`Unset-Proxy`

- 变更生效：`. $PROFILE` 或重开 PowerShell 窗口。

- 简要
  - 启动时默认只打印提示，不改动代理。
  - 同时保留了“可选：启动时自动设置一次”的两行（注释状态）。需要时取消注释即可。

```powershell
# 1) 仅当前会话的智能设置/清理函数
function Set-SmartProxy {
    param(
        [string]$Host = '127.0.0.1',
        [int]$HttpPort = 7890,
        [switch]$UseSocks,
        [int]$SocksPort = 7891,
        [string]$NoProxy = 'localhost,127.0.0.1,::1,.local,.lan'
    )
    $ok = Test-NetConnection -ComputerName $Host -Port $HttpPort -InformationLevel Quiet -WarningAction SilentlyContinue
    if ($ok) {
        $http = "http://$Host:$HttpPort"
        $env:HTTP_PROXY  = $http;  $env:http_proxy  = $http
        $env:HTTPS_PROXY = $http;  $env:https_proxy = $http
        $env:NO_PROXY    = $NoProxy; $env:no_proxy  = $NoProxy
        if ($UseSocks) {
            $socks = "socks5://$Host:$SocksPort"
            $env:ALL_PROXY = $socks; $env:all_proxy = $socks
        }
        Write-Host "✅ 代理已开启 ($Host:$HttpPort)$($UseSocks ? " + SOCKS:$SocksPort" : "")" -ForegroundColor Green
    } else {
        Unset-Proxy
    }
}

function Unset-Proxy {
    foreach ($k in 'HTTP_PROXY','http_proxy','HTTPS_PROXY','https_proxy','ALL_PROXY','all_proxy','NO_PROXY','no_proxy') {
        Remove-Item Env:$k -ErrorAction SilentlyContinue
    }
    Write-Host "ℹ️  已切换直连（已清理代理变量）" -ForegroundColor Yellow
}

# 2) 启动时提示（不自动设置）
$port = 7890
$up = Test-NetConnection -ComputerName 127.0.0.1 -Port $port -InformationLevel Quiet -WarningAction SilentlyContinue
$hint = if ($up) { "代理可能已运行(127.0.0.1:$port)" } else { "代理未运行" }
Write-Host "[$hint] 使用 Set-SmartProxy 开启，Unset-Proxy 关闭（会话内）" -ForegroundColor DarkGray

# 3) 可选：启动时自动设置一次（需要时取消注释任意一行）
# Set-SmartProxy
# Set-SmartProxy -UseSocks
```

