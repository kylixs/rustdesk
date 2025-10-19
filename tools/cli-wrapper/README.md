# RustDesk CLI Wrapper (.COM)

## 问题

RustDesk 使用 `windows_subsystem = "windows"` 来避免 GUI 双击时闪现控制台窗口。
但这导致在命令行中使用 CLI 参数时，程序退出后不返回终端提示符。

## 解决方案：.COM 包装程序

创建一个 console subsystem 的包装程序 `rustdesk.com`：

1. **Windows 优先级**：当用户在命令行输入 `rustdesk` 时，Windows 优先执行 `.com` 而不是 `.exe`
2. **Console 阻塞**：`rustdesk.com` 是 console subsystem，Shell 会等待它完成
3. **透明代理**：`rustdesk.com` 启动 `rustdesk.exe` 并等待其退出
4. **完美体验**：
   - 命令行：`rustdesk --version` → 自动返回提示符 ✅
   - 双击：启动 `rustdesk.exe` → 无闪窗 ✅

## 构建

```bash
cd cli-wrapper
cargo build --release
```

编译后的 `target/release/cli-wrapper.exe` 需要重命名为 `rustdesk.com` 并与 `rustdesk.exe` 放在同一目录。

## 部署

将 `rustdesk.com` 和 `rustdesk.exe` 一起发布：

```
rustdesk/
  ├── rustdesk.exe   (Windows subsystem - GUI 主程序)
  └── rustdesk.com   (Console subsystem - CLI 包装)
```

## 使用

用户体验完全透明：

```bash
# 命令行使用
C:\> rustdesk --version
RustDesk 1.4.3
C:\>                        # 自动返回提示符

# GUI 使用
双击 rustdesk.exe            # 或者通过快捷方式
```

## 技术参考

- [Can one executable be both console and GUI](https://stackoverflow.com/questions/493536/)
- [COM vs EXE priority in Windows](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/cmd)
- Visual Studio 使用同样的技巧：`devenv.com` + `devenv.exe`
