# Rustdesk 中继服务器 - Phase 2 使用文档

## 概述

本版本实现了灵活的剪贴板和文件传输方向控制，支持4种复制策略。

## 功能特性

### Phase 1: 单向复制拦截
- ✅ 拦截内网→外网的剪贴板传输
- ✅ 拦截内网→外网的文件传输
- ✅ 允许外网→内网的剪贴板和文件传输

### Phase 2: 灵活复制策略
- ✅ 4种复制策略：no_copy, client_to_server, server_to_client, bidirectional
- ✅ IP白名单管理（支持CIDR）
- ✅ 配置热重载
- ✅ 堡垒机模式支持

## 安装部署

### 编译
```bash
cd /opt/workspace/rustdesk/rustdesk-server
cargo build --release --bin hbbr
```

### 配置文件
创建 `server_config.json`：
```json
{
  "default_strategy": "client_to_server",
  "server_policies": [
    {
      "server_ip": "192.168.1.0/24",
      "strategy": "client_to_server",
      "description": "内网服务器：只允许客户端→服务端复制"
    },
    {
      "server_ip": "10.0.0.0/8",
      "strategy": "bidirectional",
      "description": "特殊内网：允许双向复制"
    }
  ]
}
```

### 启动服务
```bash
./target/release/hbbr
```

服务将在以下端口监听：
- TCP 21117：中继服务
- WebSocket 21119：WebSocket中继

## 复制策略说明

### 1. no_copy
- 禁止所有复制操作
- 剪贴板和文件传输都被拦截

### 2. client_to_server
- 只允许客户端→服务端复制
- 拦截服务端→客户端的复制
- **推荐用于内网服务器保护**

### 3. server_to_client
- 只允许服务端→客户端复制
- 拦截客户端→服务端的复制

### 4. bidirectional
- 允许双向复制
- 无任何限制

## 使用场景

### 场景1：内网服务器保护
```json
{
  "default_strategy": "client_to_server",
  "server_policies": [
    {
      "server_ip": "192.168.1.0/24",
      "strategy": "client_to_server"
    }
  ]
}
```
- 外网用户可以复制内容到内网服务器
- 内网服务器的内容无法复制到外网
- **防止数据泄露**

### 场景2：堡垒机模式
```json
{
  "default_strategy": "no_copy",
  "server_policies": [
    {
      "server_ip": "10.0.0.100",
      "strategy": "client_to_server"
    }
  ]
}
```
- 默认禁止所有复制
- 只允许堡垒机的client_to_server复制
- **严格安全控制**

### 场景3：特殊内网双向复制
```json
{
  "default_strategy": "client_to_server",
  "server_policies": [
    {
      "server_ip": "10.0.0.0/8",
      "strategy": "bidirectional"
    }
  ]
}
```
- 外网默认只能单向复制到内网
- 特殊内网段允许双向复制
- **灵活策略配置**

## 配置热重载

修改 `server_config.json` 后，配置会自动重新加载，无需重启服务。

## 验证和测试

### 检查服务状态
```bash
# 检查进程
ps aux | grep hbbr

# 检查端口
netstat -tlnp | grep -E "(21117|21119)"
```

### 查看拦截日志
```bash
tail -f /opt/workspace/rustdesk/rustdesk-server/hbbr.log | grep "Blocked"
```

### 测试剪贴板拦截
1. 配置客户端连接到中继服务器
2. 从内网服务器复制文本
3. 尝试粘贴到外网客户端
4. **预期结果**：粘贴失败（被拦截）

### 测试文件传输拦截
1. 从内网服务器传输文件到外网客户端
2. **预期结果**：传输失败（被拦截）

## 故障排查

### 问题1：配置不生效
- 检查 `server_config.json` 格式是否正确
- 查看日志确认配置已加载

### 问题2：拦截不生效
- 确认IP地址匹配策略
- 检查字节检测逻辑是否匹配

### 问题3：服务无法启动
- 检查端口21117/21119是否被占用
- 查看日志文件排查错误

## 技术细节

### 剪贴板检测
- 字节标记：0x82, 0xA2, 0xE2

### 文件传输检测
- 字节标记：0x83-0x86
- 数据大小：>1KB

### IP分类
- IPv4私有地址：10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16
- IPv6：暂不支持私有地址检测

## 版本信息

- **Phase 1**: 单向复制拦截
- **Phase 2**: 灵活复制策略
- **编译时间**: 2026-03-13 20:46
- **开发者**: rust-system-expert

## 联系支持

如遇问题，请在Rustdesk开发群提出。

---
*文档创建时间: 2026-03-14 03:42*
*负责人: rust-system-expert*
