# RustDesk 单向剪贴板功能设计文档

## 文档信息
- **创建日期**: 2026-03-12
- **作者**: @rust-system-expert
- **分支**: feature-block-intranet-copy
- **状态**: 草案

## 1. 需求概述

### 1.1 核心需求
实现 RustDesk 远程桌面的**单向复制**功能，确保内网安全，避免内网资料泄露。

**具体要求**:
- ✅ **允许**: 从外网复制文件/文字到内网
- ❌ **禁止**: 从内网复制文件/文字到外网

### 1.2 技术场景
```
外部办公网络 → 中继服务(hbbr) → 内网开发机
(客户端)        (拦截点)         (服务端)
```

### 1.3 安全要求
1. 在中继服务上实现拦截（最可靠）
2. 客户端/服务端也支持（防绕过备份）
3. 强制使用定制版客户端/服务端

---

## 2. 代码架构分析

### 2.1 关键代码位置

| 组件 | 路径 | 功能 |
|------|------|------|
| 剪贴板服务 | `src/server/clipboard_service.rs` | 监控并发送剪贴板数据 |
| 连接处理 | `src/server/connection.rs` | 处理剪贴板消息(line 828) |
| 剪贴板库 | `libs/clipboard/` | 跨平台剪贴板实现 |
| 消息协议 | `libs/hbb_common/protos/message.proto` | 剪贴板消息定义 |
| 中继协议 | `libs/hbb_common/protos/rendezvous.proto` | 中继连接协议 |

### 2.2 数据流分析

```
剪贴板数据流向:

[内网开发机 - 服务端]
       ↓
clipboard_service.rs (监控剪贴板变化)
       ↓
sp.send(MultiClipboards) [发送剪贴板消息]
       ↓
connection.rs (处理消息)
       ↓
[中继服务器 - hbbr] ← 拦截点
       ↓
[外网客户端 - 客户端]
```

### 2.3 关键消息结构

**message.proto**:
```protobuf
message Clipboard {
  bool compress = 1;
  bytes content = 2;
  int32 width = 3;
  int32 height = 4;
  ClipboardFormat format = 5;
  string special_name = 6;
}

message MultiClipboards { 
  repeated Clipboard clipboards = 1; 
}
```

---

## 3. 技术方案

### 3.1 方案一: 中继服务器拦截（推荐）

**优势**:
- 最安全，用户无法绕过
- 集中控制，易于管理
- 不影响客户端/服务端兼容性

**实现步骤**:
1. 修改 `hbbr`（rustdesk-server 中的中继服务器）
2. 解析通过中继的数据流
3. 识别 `MultiClipboards` / `Clipboard` 消息
4. 根据消息方向决定是否拦截

**需要修改**:
- rustdesk-server 仓库的 `hbbr` 模块
- 添加剪贴板消息过滤器

### 3.2 方案二: 客户端/服务端控制（备选）

**优势**:
- 无需修改中继服务器
- 实现相对简单

**实现步骤**:

**服务端修改** (`src/server/clipboard_service.rs`):
```rust
// 添加单向模式检查
fn run(sp: EmptyExtraFieldService) -> ResultType<()> {
    let one_way_clipboard = Config::get_option("one-way-clipboard") == "true";
    
    while sp.ok() {
        // ... 现有代码 ...
        
        if let Some(msg) = handler.get_clipboard_msg() {
            // 单向模式下不发送剪贴板数据
            if !one_way_clipboard {
                sp.send(msg);
            }
        }
    }
}
```

**连接处理修改** (`src/server/connection.rs`):
```rust
// 在 line 828 附近
Some(message::Union::MultiClipboards(_multi_clipboards)) => {
    // 单向模式下忽略来自内网的剪贴板数据
    if self.one_way_clipboard && self.is_server_side() {
        log::info!("Blocked clipboard data from internal network");
        return;
    }
    // ... 现有处理代码 ...
}
```

### 3.3 方案三: 协议锁定（防绕过）

**目标**: 确保只有定制版客户端/服务端能建立连接

**实现方式**:
1. 在握手阶段添加 `one-way-mode` 标志
2. 服务端收到带有此标志的连接时，启用单向模式
3. 标准版 RustDesk 拒绝带有此标志的连接

**协议修改** (`rendezvous.proto`):
```protobuf
message ConnectPeer {
    // ... 现有字段 ...
    bool one_way_clipboard = 10;  // 新增: 单向剪贴板标志
}
```

---

## 4. 配置选项设计

### 4.1 现有配置选项（已实现）✅

**RustDesk 已内置单向复制选项**：

| 选项 | 说明 | 位置 |
|------|------|------|
| `one-way-clipboard-redirection` | 单向剪贴板同步 | `config.rs:2587` |
| `one-way-file-transfer` | 单向文件传输 | `config.rs:2589` |

**CLI 配置方式**：
```bash
# 在内网机器（被控端）上执行
sudo rustdesk --option one-way-clipboard-redirection Y
sudo rustdesk --option one-way-file-transfer Y
```

**实现机制** (`src/server/connection.rs:1733`):
```rust
fn can_sub_clipboard_service(&self) -> bool {
    self.clipboard_enabled()
        && self.peer_keyboard_enabled()
        && crate::get_builtin_option(keys::OPTION_ONE_WAY_CLIPBOARD_REDIRECTION) != "Y"
}
```

当选项设为 "Y" 时：
- 服务端不订阅剪贴板服务
- 不发送剪贴板数据到客户端
- 实现内网→外网的阻断 ✅

### 4.2 中继服务器配置（待开发）

**hbbr 配置**:
```bash
# 启用单向剪贴板拦截
hbbr --one-way-clipboard=true
```

---

## 5. 实施计划

### Phase 1: 技术验证（1-2天）
- [ ] 确认 rustdesk-server 仓库位置
- [ ] 分析 hbbr 中继服务器代码
- [ ] 验证剪贴板消息解析可行性

### Phase 2: 中继服务器实现（3-5天）
- [ ] 实现 hbbr 剪贴板消息过滤器
- [ ] 添加方向识别逻辑
- [ ] 单元测试

### Phase 3: 客户端/服务端实现（2-3天）
- [ ] 添加 `one-way-clipboard` 配置选项
- [ ] 修改 clipboard_service.rs
- [ ] 修改 connection.rs
- [ ] 集成测试

### Phase 4: 协议锁定（2-3天）
- [ ] 修改 rendezvous.proto
- [ ] 实现握手阶段标志传递
- [ ] 安全测试

### Phase 5: 测试与文档（2-3天）
- [ ] 端到端测试
- [ ] 安全审计
- [ ] 更新文档

---

## 6. 待解决问题

1. **rustdesk-server 仓库位置**
   - 是否有 kylixs/rustdesk-server？
   - 还是使用官方 rustdesk/rustdesk-server？

2. **部署环境**
   - 中继服务器操作系统？
   - 是否需要跨平台支持？

3. **安全审计需求**
   - 是否需要记录拦截日志？
   - 是否需要配置管理界面？

---

## 7. 参考资料

- 飞书文档: https://my.feishu.cn/wiki/RZVtwLPccieD4OkXIKZclll4nVc
- Git仓库: git@github.com:kylixs/rustdesk.git
- 分支: feature-block-intranet-copy

---

*最后更新: 2026-03-12*
