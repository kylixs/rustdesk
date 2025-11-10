# CM子进程用户身份获取机制分析

## 问题背景

从 `show-processes.ps1` 脚本可以看到，cm进程是以登录用户身份运行的，而不是以服务（SYSTEM）身份运行。需要分析这个用户身份是如何获取的。

## 核心流程

### 1. 启动入口 (connection.rs:4400-4437)

当需要启动cm子进程时：

```rust
if crate::platform::is_root() {
    // 以root/SYSTEM身份运行时，使用 run_as_user 启动子进程
    res = crate::platform::run_as_user(args.clone());
}
```

### 2. Windows平台实现 (windows.rs:800-855)

```rust
pub fn run_as_user(arg: Vec<&str>) -> ResultType<Option<std::process::Child>> {
    run_exe_in_cur_session(std::env::current_exe()?.to_str().unwrap_or(""), arg, false)
}

pub fn run_exe_in_cur_session(exe: &str, arg: Vec<&str>, show: bool) -> ResultType<Option<std::process::Child>> {
    // 关键：获取当前进程的 session ID
    let Some(session_id) = get_current_process_session_id() else {
        bail!("Failed to get current process session id");
    };
    run_exe_in_session(exe, arg, session_id, show)
}
```

**关键点：**
- 当 RustDesk 服务接受远程连接时，该服务进程的 session ID 就是**登录用户所在的 session ID**
- 不是 session 0（服务session），而是用户session（通常是session 1、2等）

### 3. Session ID 获取 (windows.rs:1006-1017)

```rust
pub fn get_current_process_session_id() -> Option<u32> {
    get_session_id_of_process(unsafe { GetCurrentProcessId() })
}

pub fn get_session_id_of_process(pid: DWORD) -> Option<u32> {
    let mut sid = 0;
    if unsafe { ProcessIdToSessionId(pid, &mut sid) == TRUE } {
        Some(sid)
    } else {
        None
    }
}
```

**原理：**
- 使用 Windows API `ProcessIdToSessionId` 获取当前进程所属的 session
- 如果是服务响应用户远程连接，该服务进程会关联到用户的 session

### 4. C++底层实现 - 查找用户进程 (windows.cc:126-150)

```cpp
DWORD GetLogonPid(DWORD dwSessionId, BOOL as_user)
{
    DWORD dwLogonPid = 0;
    HANDLE hSnap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);

    if (Process32FirstW(hSnap, &procEntry))
        do {
            DWORD dwLogonSessionId = 0;
            // 关键：查找 explorer.exe 进程（当 as_user=TRUE）
            if (_wcsicmp(procEntry.szExeFile, as_user ? L"explorer.exe" : L"winlogon.exe") == 0 &&
                ProcessIdToSessionId(procEntry.th32ProcessID, &dwLogonSessionId) &&
                dwLogonSessionId == dwSessionId)
            {
                dwLogonPid = procEntry.th32ProcessID;
                break;
            }
        } while (Process32NextW(hSnap, &procEntry));

    return dwLogonPid;
}
```

**核心机制：**
- 遍历所有进程，查找指定 session 中的 **explorer.exe** 进程
- explorer.exe 是用户登录后启动的 shell 进程，代表了登录用户的身份
- 找到 explorer.exe 的 PID

### 5. 获取用户Token (windows.cc:205-221)

```cpp
BOOL GetSessionUserTokenWin(OUT LPHANDLE lphUserToken, DWORD dwSessionId, BOOL as_user, DWORD *pDwTokenPid)
{
    BOOL bResult = FALSE;
    // 获取 explorer.exe 的 PID
    DWORD Id = GetLogonPid(dwSessionId, as_user);
    if (Id == 0) {
        // 如果找不到 explorer.exe，尝试 fallback（sihost.exe）
        Id = GetFallbackUserPid(dwSessionId);
    }

    // 打开 explorer.exe 进程并获取其 token
    if (HANDLE hProcess = OpenProcess(PROCESS_ALL_ACCESS, FALSE, Id)) {
        bResult = OpenProcessToken(hProcess, TOKEN_ALL_ACCESS, lphUserToken);
        CloseHandle(hProcess);
    }
    return bResult;
}
```

**关键步骤：**
1. 找到登录用户的 explorer.exe 进程
2. 打开该进程并获取其 access token
3. 这个 token 包含了：
   - 用户身份（SID）
   - 用户权限
   - 用户环境变量信息

### 6. 创建用户进程 (windows.cc:233-274)

```cpp
HANDLE LaunchProcessWin(LPCWSTR cmd, DWORD dwSessionId, BOOL as_user, BOOL show, DWORD *pDwTokenPid)
{
    HANDLE hProcess = NULL;
    HANDLE hToken = NULL;

    if (GetSessionUserTokenWin(&hToken, dwSessionId, as_user, pDwTokenPid)) {
        LPVOID lpEnvironment = NULL;

        if (as_user) {
            // 关键：使用用户token创建环境块
            CreateEnvironmentBlock(&lpEnvironment, hToken, TRUE);
        }

        // 使用用户token和环境块创建进程
        if (CreateProcessAsUserW(hToken, NULL, buf, NULL, NULL, FALSE,
                                dwCreationFlags, lpEnvironment, NULL, &si, &pi)) {
            CloseHandle(pi.hThread);
            hProcess = pi.hProcess;
        }

        CloseHandle(hToken);
        if (lpEnvironment)
            DestroyEnvironmentBlock(lpEnvironment);
    }
    return hProcess;
}
```

**关键API：**
1. **CreateEnvironmentBlock**：
   - 根据用户 token 创建环境块
   - 这个环境块包含了用户的所有环境变量
   - **包括 %AppData%, %LOCALAPPDATA%, %USERPROFILE% 等**

2. **CreateProcessAsUserW**：
   - 使用指定的用户 token 创建进程
   - 新进程以该 token 代表的用户身份运行
   - 继承 lpEnvironment 中的环境变量

## 完整流程图

```
服务进程(SYSTEM)
    │
    ├─ 1. 接受远程连接（在用户session中）
    │
    ├─ 2. 获取当前进程的 session ID
    │      (实际上是用户的 session ID，如 session 1)
    │
    ├─ 3. 在该 session 中查找 explorer.exe
    │      └─> 找到登录用户的 explorer.exe (PID: xxxx)
    │
    ├─ 4. 从 explorer.exe 获取用户 token
    │      └─> Token 包含：用户SID、权限、环境变量
    │
    ├─ 5. 使用 token 创建环境块
    │      └─> CreateEnvironmentBlock
    │           ├─ %AppData% = C:\Users\<username>\AppData\Roaming
    │           ├─ %LOCALAPPDATA% = C:\Users\<username>\AppData\Local
    │           └─ %USERPROFILE% = C:\Users\<username>
    │
    └─ 6. 使用 token 和环境块创建 cm 子进程
           └─> CreateProcessAsUserW
                └─> cm进程以登录用户身份运行
                    └─> 环境变量指向用户目录，而非 systemprofile
```

## 配置目录解析

### Config::path() 实现 (config.rs:632-655)

```rust
pub fn path<P: AsRef<Path>>(p: P) -> PathBuf {
    if let Some(project) = directories_next::ProjectDirs::from("", &org, &APP_NAME.read().unwrap()) {
        let mut path = patch(project.config_dir().to_path_buf());
        path.push(p);
        return path;
    }
    "".into()
}
```

### directories_next 库的行为

`ProjectDirs::from()` 内部调用：
1. **Windows**: 获取 `%AppData%` 环境变量
2. 构建路径：`%AppData%\RustDesk\config`

### 不同运行身份下的路径

| 运行身份 | %AppData% 值 | 最终配置路径 |
|---------|-------------|-------------|
| **服务进程 (SYSTEM)** | `C:\Windows\system32\config\systemprofile\AppData\Roaming` | `C:\Windows\system32\config\systemprofile\AppData\Roaming\RustDesk\config` |
| **cm子进程 (登录用户)** | `C:\Users\<username>\AppData\Roaming` | `C:\Users\<username>\AppData\Roaming\RustDesk\config` |

## 关键发现

### 1. cm子进程确实以登录用户身份运行

通过以下机制实现：
- 服务进程获取用户session ID
- 找到该session中的 explorer.exe
- 从 explorer.exe 获取用户 token
- 使用 CreateProcessAsUserW 创建进程

### 2. 环境变量自动指向用户目录

因为：
- `CreateEnvironmentBlock` 根据用户 token 创建完整的用户环境
- 新进程继承这些环境变量
- **不需要**手动指定用户目录路径
- **不需要**修改代码来选择AppData vs systemprofile

### 3. 程序没有硬编码systemprofile

- 程序只是读取 `%AppData%` 环境变量
- 该变量的值由进程的用户身份决定：
  - SYSTEM用户 → systemprofile
  - 登录用户 → C:\Users\<username>

## 为什么会访问systemprofile？

### 可能的原因

1. **服务主进程自身的配置**
   - 服务进程（SYSTEM身份）自己也需要读写配置
   - 它的 %AppData% 就是 systemprofile

2. **cm子进程启动失败的情况**
   - 如果 run_as_user 失败
   - 回退到直接启动（使用服务身份）
   - 此时会使用 systemprofile

3. **早期初始化阶段**
   - 服务启动时，在用户登录前
   - 可能需要读取某些配置

## 结论

**Q: 是否可以改为只使用登录用户AppData？**

**A: 理论上可以，但有复杂性：**

### 当前机制的优点
✅ 自动适应运行身份
✅ 服务进程和用户进程使用各自的配置
✅ 不需要手动管理路径

### 修改为只用登录用户AppData的挑战

1. **服务初始化问题**
   - 服务启动时可能没有登录用户
   - 需要等待用户登录才能确定目录

2. **多用户场景**
   - 多个用户可能同时连接（RDP）
   - 需要决定使用哪个用户的配置

3. **权限问题**
   - 服务进程（SYSTEM）需要访问用户目录
   - 可能遇到权限拒绝
   - 需要设置适当的ACL

4. **向后兼容**
   - 现有配置在 systemprofile
   - 需要迁移逻辑

### 推荐方案

**不修改**，原因：
- cm子进程已经自动使用登录用户AppData
- 服务主进程使用 systemprofile 是合理的
- 当前机制已经很好地处理了两种身份

**如果必须修改**，建议：
1. 只修改服务主进程的配置路径获取逻辑
2. 添加获取登录用户AppData的辅助函数
3. 处理无登录用户的情况（回退到systemprofile）
4. 添加配置迁移逻辑
