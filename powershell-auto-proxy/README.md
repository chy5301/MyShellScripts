# PowerShell 自动代理配置工具

一个智能的 PowerShell 代理配置工具，支持自动检测代理服务状态并智能切换，避免代理服务关闭时导致的网络连接问题。

## 功能特性

- 🚀 **智能检测**：自动检测代理端口是否可用
- 🔄 **自动切换**：代理不可用时自动切换到直连模式
- 📊 **状态显示**：实时显示当前代理配置状态
- 🎯 **SOCKS 支持**：支持 HTTP/HTTPS 和 SOCKS5 代理
- ⚡ **快速响应**：轻量级端口检测，响应迅速
- 🔧 **启动提示**：PowerShell 启动时显示可用命令提示

## 核心功能

### 主要函数

- `Set-SmartProxy` - 智能设置代理（自动检测端口可用性）
- `Unset-Proxy` - 清除所有代理设置
- `Get-ProxyStatus` - 查看当前代理状态
- `Test-ProxyPort` - 测试指定代理端口是否可用

## 快速开始

### 1. 导入脚本

```powershell
# 方法1：直接运行脚本
. .\powershell-auto-proxy.ps1

# 方法2：添加到 PowerShell 配置文件
# 将脚本内容复制到 $PROFILE 中
```

### 2. 基本使用

```powershell
# 设置代理（默认 127.0.0.1:7890）
Set-SmartProxy

# 设置代理并启用 SOCKS（7891 端口）
Set-SmartProxy -UseSocks

# 清除代理设置
Unset-Proxy

# 查看当前代理状态
Get-ProxyStatus
```

## 详细配置

### 自定义代理参数

```powershell
# 自定义代理服务器和端口
Set-SmartProxy -ProxyHost "192.168.1.100" -HttpPort 8080

# 启用 SOCKS 并指定端口
Set-SmartProxy -ProxyHost "127.0.0.1" -HttpPort 7890 -UseSocks -SocksPort 7891
```

### 环境变量设置

该工具会自动设置以下环境变量：

```
HTTP_PROXY=http://127.0.0.1:7890
HTTPS_PROXY=http://127.0.0.1:7890
http_proxy=http://127.0.0.1:7890
https_proxy=http://127.0.0.1:7890
NO_PROXY=localhost,127.0.0.1,::1,.local,.lan
no_proxy=localhost,127.0.0.1,::1,.local,.lan
ALL_PROXY=socks5://127.0.0.1:7891  # 仅在启用 SOCKS 时
all_proxy=socks5://127.0.0.1:7891  # 仅在启用 SOCKS 时
```

## 自动化配置

### 添加到 PowerShell 配置文件

1. 打开或创建 PowerShell 配置文件：
```powershell
if (-not (Test-Path $PROFILE)) { New-Item -Type File -Path $PROFILE -Force }
notepad $PROFILE
```

2. 将脚本内容添加到配置文件中

3. 重新加载配置：
```powershell
. $PROFILE
```

### 启动时的智能提示

脚本会在 PowerShell 启动时显示代理状态和可用命令：

```
[代理可用] Set-SmartProxy | Unset-Proxy | Get-ProxyStatus
```

## 工作原理

1. **端口检测**：使用 TCP 连接测试代理端口是否可用（超时 800ms）
2. **智能切换**：
   - 如果代理端口可用 → 设置代理环境变量
   - 如果代理端口不可用 → 清除代理设置，使用直连
3. **兼容性保证**：同时设置大小写环境变量，确保不同工具的兼容性

## 常见使用场景

### 场景 1：开发环境代理切换
```powershell
# 开启代理进行外网访问
Set-SmartProxy

# 完成工作后关闭代理
Unset-Proxy
```

### 场景 2：SOCKS 代理支持
```powershell
# 对于需要 SOCKS 协议的应用
Set-SmartProxy -UseSocks
```

### 场景 3：检查当前状态
```powershell
# 快速查看当前代理配置
Get-ProxyStatus
```

## 技术细节

- **端口检测超时**：800ms（快速响应，避免长时间等待）
- **支持协议**：HTTP、HTTPS、SOCKS5
- **作用范围**：仅影响当前 PowerShell 会话的环境变量
- **兼容性**：支持 Windows PowerShell 5.x 和 PowerShell 7+

## 注意事项

- 该工具仅设置环境变量，不会修改系统级代理设置
- 代理设置仅在当前 PowerShell 会话中有效
- 支持的应用需要能够识别环境变量代理设置（如 curl、git、npm 等）
- Windows 系统级应用可能需要单独配置系统代理

## 故障排除

### 常见问题

1. **代理设置后仍无法访问网络**
   - 检查代理服务是否正常运行
   - 确认代理端口配置是否正确
   - 验证目标应用是否支持环境变量代理

2. **启动提示不显示**
   - 确认脚本已正确添加到 `$PROFILE`
   - 重新加载配置文件：`. $PROFILE`

3. **SOCKS 代理不生效**
   - 确认应用支持 SOCKS5 协议
   - 检查 SOCKS 端口是否正确

## 许可证

本项目采用 MIT 许可证。

## 贡献

欢迎提交 Issue 和 Pull Request 来改进这个工具。