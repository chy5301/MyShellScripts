# Downloaded Videos Auto Sync

一个基于 `inotify` 的视频文件自动同步工具，实时监控下载目录中的新增视频文件，并自动同步到指定的目标目录。该工具专为 NAS 或服务器环境设计，支持断点续传和智能重试机制。

## 功能特性

- 🔍 **实时监控**：使用 `inotifywait` 实时监控源目录的文件变化
- 📁 **智能过滤**：自动排除下载中的临时文件（`.part`、`.crdownload` 等）
- 🔄 **断点续传**：使用 `rsync` 支持断点续传和增量同步
- 🛡️ **智能重试**：支持可配置的重试次数和动态重试间隔
- 🎯 **精确同步**：仅同步新增文件，保持目录结构不变
- ⚡ **高效传输**：采用 `rsync` 的 `--no-whole-file` 选项优化传输效率
- 🔧 **systemd 集成**：提供完整的系统服务配置

## 系统要求

- Linux 系统（支持 `inotify`）
- `inotify-tools` 软件包
- `rsync` 工具
- `bash` shell 环境

### 安装依赖

```bash
# Ubuntu/Debian
sudo apt-get install inotify-tools rsync

# CentOS/RHEL
sudo yum install inotify-tools rsync

# 或者使用 dnf（较新版本）
sudo dnf install inotify-tools rsync
```

## 快速开始

### 1. 基本使用

```bash
# 直接运行（使用默认配置）
./downloaded-videos-auto-sync.sh

# 使用自定义目录
SOURCE_DIR="/path/to/downloads" DEST_DIR="/path/to/destination" ./downloaded-videos-auto-sync.sh
```

### 2. 配置环境变量

```bash
# 设置源目录
export SOURCE_DIR="/volume1/downloads/Videos"

# 设置目标目录
export DEST_DIR="/volume2/@home/chy/Videos"

# 设置最大重试次数（默认：3）
export MAX_RETRIES=5

# 设置初始重试间隔（默认：1 秒）
export INITIAL_RETRY_DELAY=2

# 运行脚本
./downloaded-videos-auto-sync.sh
```

## systemd 服务配置

### 1. 安装服务

```bash
# 复制脚本到系统目录
sudo cp downloaded-videos-auto-sync.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/downloaded-videos-auto-sync.sh

# 复制服务文件
sudo cp downloaded-videos-auto-sync.service /etc/systemd/system/

# 根据实际情况修改服务文件中的路径
sudo nano /etc/systemd/system/downloaded-videos-auto-sync.service
```

### 2. 服务文件配置

```ini
[Unit]
Description=Auto Sync Downloaded Videos Directory
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/downloaded-videos-auto-sync.sh
Restart=always
RestartSec=5
User=chy
Group=admin
MemoryHigh=1.6G
MemoryMax=2G
SyslogIdentifier=downloaded-videos-auto-sync

[Install]
WantedBy=multi-user.target
```

### 3. 启动和管理服务

```bash
# 重新加载 systemd 配置
sudo systemctl daemon-reload

# 启动服务
sudo systemctl start downloaded-videos-auto-sync

# 设置开机自启
sudo systemctl enable downloaded-videos-auto-sync

# 查看服务状态
sudo systemctl status downloaded-videos-auto-sync

# 查看服务日志
sudo journalctl -u downloaded-videos-auto-sync -f
```

## 配置参数详解

### 环境变量配置

| 变量名                | 默认值                      | 说明                     |
| --------------------- | --------------------------- | ------------------------ |
| `SOURCE_DIR`          | `/volume1/downloads/Videos` | 监控的源目录路径         |
| `DEST_DIR`            | `/volume2/@home/chy/Videos` | 同步的目标目录路径       |
| `MAX_RETRIES`         | `3`                         | 同步失败时的最大重试次数 |
| `INITIAL_RETRY_DELAY` | `1`                         | 初始重试间隔（秒）       |

### 过滤规则

脚本会自动过滤以下类型的文件：

- `.part` - 下载中的部分文件
- `.parts` - 多段下载文件
- `.crdownload` - Chrome 下载临时文件
- `.!qB` - qBittorrent 临时文件
- `.ug-tmp` - μTorrent 临时文件

### rsync 参数说明

```bash
rsync -rlptv --ignore-existing --no-whole-file "${NEW_FILE}" "${TARGET_FILE}"
```

- `-r`: 递归同步
- `-l`: 复制符号链接
- `-p`: 保持权限
- `-t`: 保持修改时间
- `-v`: 详细输出
- `--ignore-existing`: 跳过已存在的文件
- `--no-whole-file`: 使用增量传输算法

## 监控事件

脚本监控以下 `inotify` 事件：

- `create`: 新文件创建
- `moved_to`: 文件移动到监控目录

## 使用场景

### 场景 1：NAS 下载目录同步

```bash
# Synology NAS 环境
SOURCE_DIR="/volume1/downloads/Videos"
DEST_DIR="/volume2/@home/user/Videos"
./downloaded-videos-auto-sync.sh
```

### 场景 2：服务器文件分发

```bash
# 将下载目录的文件自动分发到用户目录
SOURCE_DIR="/home/downloads"
DEST_DIR="/home/users/shared/videos"
MAX_RETRIES=5
./downloaded-videos-auto-sync.sh
```

### 场景 3：备份和归档

```bash
# 自动备份重要视频文件
SOURCE_DIR="/media/recordings"
DEST_DIR="/backup/videos"
INITIAL_RETRY_DELAY=3
./downloaded-videos-auto-sync.sh
```

## 日志和监控

### 查看实时日志

```bash
# 如果作为 systemd 服务运行
sudo journalctl -u downloaded-videos-auto-sync -f

# 如果直接运行脚本
./downloaded-videos-auto-sync.sh 2>&1 | tee sync.log
```

### 日志输出示例

```
跳过文件：/volume1/downloads/Videos/movie.mp4.part
同步完成: /volume1/downloads/Videos/movie.mp4 -> /volume2/@home/chy/Videos/movie.mp4
同步失败: /volume1/downloads/Videos/video.mkv 状态码: 23 重试: 1/3
同步完成: /volume1/downloads/Videos/video.mkv -> /volume2/@home/chy/Videos/video.mkv
```

## 故障排除

### 常见问题

1. **权限问题**
   ```bash
   # 确保用户有读写权限
   sudo chown -R chy:admin /volume1/downloads/Videos
   sudo chown -R chy:admin /volume2/@home/chy/Videos
   ```

2. **目录不存在**
   ```bash
   # 脚本会自动创建目录，但确保父目录存在
   mkdir -p /volume2/@home/chy
   ```

3. **磁盘空间不足**
   ```bash
   # 检查目标目录磁盘空间
   df -h /volume2
   ```

4. **网络传输问题**
   ```bash
   # 如果目标是网络位置，检查网络连接
   ping target-server
   ```

### 调试模式

```bash
# 启用 bash 调试模式
bash -x downloaded-videos-auto-sync.sh

# 或者在脚本开头添加
set -x
```

## 性能优化

### 内存限制

systemd 服务配置中设置了内存限制：

- `MemoryHigh=1.6G`: 软限制，超过时系统会尝试回收内存
- `MemoryMax=2G`: 硬限制，超过时进程会被终止

### 优化建议

1. **调整重试策略**：根据网络状况调整 `MAX_RETRIES` 和 `INITIAL_RETRY_DELAY`
2. **监控资源使用**：定期检查服务的内存和 CPU 使用情况
3. **日志轮转**：配置 `journald` 日志轮转防止日志文件过大

## 安全注意事项

- 确保服务运行用户具有适当的文件系统权限
- 定期检查同步的文件完整性
- 考虑对敏感文件进行额外的访问控制
- 监控磁盘使用情况防止空间耗尽

## 更新历史

- **v1.0**: 初始版本，基本的文件监控和同步功能
- **v1.1**: 添加智能重试机制和动态重试间隔
- **v1.2**: 优化临时文件过滤规则
- **v1.3**: 完善 systemd 服务配置和内存管理

## 许可证

本项目采用 MIT 许可证。

## 贡献

欢迎提交 Issue 和 Pull Request 来改进这个工具。
