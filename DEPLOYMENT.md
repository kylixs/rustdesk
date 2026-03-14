# Phase 2 测试环境部署文档

## 部署状态

**编译状态**：✅ 成功
**服务状态**：✅ 运行中（PID: 727019）
**端口监听**：✅ 21117/21119正常

## 部署包准备

### 文件清单
- `target/release/hbbr` - 中继服务器（包含Phase 2功能）
- `server_config.json` - 配置文件（堡垒机模式）
- `DEPLOYMENT.md` - 本文档

### 配置文件
位置：`/opt/workspace/rustdesk/rustdesk-server/server_config.json`

## 测试环境要求

### 硬件要求
- 中继服务器：已部署（当前机器）
- 测试客户端A：内网机器（如192.168.1.x）
- 测试客户端B：外网机器（公网IP）

### 软件要求
- Rustdesk客户端（支持自定义中继服务器）
- 两台测试机器可以互相连接

## 测试场景

### 场景1：内网→外网复制（应拦截）
1. 客户端A（内网）连接到客户端B（外网）
2. 在A上复制文本，尝试粘贴到B
3. **预期结果**：粘贴失败

### 场景2：外网→内网复制（应允许）
1. 客户端B（外网）连接到客户端A（内网）
2. 在B上复制文本，粘贴到A
3. **预期结果**：粘贴成功

## 验证命令

### 检查服务状态
```bash
ps aux | grep hbbr | grep -v grep
netstat -tlnp | grep -E "(21117|21119)"
```

### 查看拦截日志
```bash
tail -f /opt/workspace/rustdesk/rustdesk-server/hbbr.log | grep "Blocked"
```

## 配置管理

### 查看当前配置
```bash
cat /opt/workspace/rustdesk/rustdesk-server/server_config.json
```

### 修改配置
编辑 `server_config.json`，修改后自动生效（热重载）

## 部署完成

✅ Phase 2已成功集成并部署到中继服务器
✅ 支持灵活的复制策略配置
✅ 准备进行测试验证

---
*部署时间：2026-03-13 21:46*
*负责人：rust-system-expert*
