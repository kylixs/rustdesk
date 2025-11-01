# GitHub Actions 自定义 Artifact 上传脚本

## 概述

`upload-artifacts.js` 是一个使用 `@actions/artifact` npm 包的自定义上传脚本，专为 Node.js 16+ 环境设计，用于在 GitHub Actions workflow 中上传构建产物。

## 为什么需要这个脚本？

- **Node 16 兼容性**：官方 `actions/upload-artifact@v4` 需要 Node 20，而 Ubuntu 18.04 Docker 环境通常使用 Node 16
- **灵活性**：支持自定义文件模式匹配和上传逻辑
- **可扩展性**：可以根据项目需求轻松修改和扩展

## 依赖项

```json
{
  "@actions/artifact": "^2.0.0",
  "glob": "^10.0.0"
}
```

## 使用方法

### 基本语法

```bash
node .github/scripts/upload-artifacts.js <artifact-name> <file-patterns...>
```

### 示例

#### 上传 DEB 和 RPM 包

```bash
node .github/scripts/upload-artifacts.js \
  rustdesk-ubuntu18 \
  "rustdesk*.deb" \
  "rustdesk*.rpm"
```

#### 上传日志文件

```bash
node .github/scripts/upload-artifacts.js \
  build-logs \
  "*.log" \
  "build/*.log"
```

#### 上传多种文件类型

```bash
node .github/scripts/upload-artifacts.js \
  all-artifacts \
  "*.deb" \
  "*.rpm" \
  "*.pkg.tar.zst" \
  "*.log"
```

## 在 GitHub Actions Workflow 中使用

### 示例 1: 在 Ubuntu 18 Container 中使用（推荐）

```yaml
jobs:
  build-ubuntu18:
    runs-on: ubuntu-latest
    container:
      image: ubuntu:18.04
      options: --privileged
    strategy:
      fail-fast: false
      matrix:
        job:
          - {
              arch: x86_64,
              target: x86_64-unknown-linux-gnu,
              deb_arch: amd64,
              vcpkg-triplet: x64-linux,
            }

    steps:
      - name: Checkout code
        uses: actions/checkout@v3

      - name: Build RustDesk
        run: ./build-for-ubuntu18.sh

      - name: Install Node.js in container
        run: |
          # 更新包列表并安装必要工具
          apt-get update
          apt-get install -y curl ca-certificates

          # 安装 Node.js 16
          curl -fsSL https://deb.nodesource.com/setup_16.x | bash -
          apt-get install -y nodejs

          # 验证安装
          node --version
          npm --version

      - name: Install dependencies
        run: npm install @actions/artifact glob

      - name: Upload artifacts
        run: |
          node .github/scripts/upload-artifacts.js \
            "rustdesk-ubuntu18-${{ github.run_number }}" \
            "rustdesk*.deb" \
            "rustdesk*.rpm"
```

### 示例 2: 在 Docker Run 中使用

```yaml
jobs:
  build-ubuntu18:
    runs-on: ubuntu-22.04

    steps:
      - name: Checkout code
        uses: actions/checkout@v3

      - name: Build in Ubuntu 18 Docker
        run: |
          docker run --rm \
            -v ${{ github.workspace }}:/workspace \
            -w /workspace \
            ubuntu:18.04 bash -c "./build-for-ubuntu18.sh"

      - name: Setup Node.js
        uses: actions/setup-node@v3
        with:
          node-version: '16'

      - name: Install dependencies
        run: npm install @actions/artifact glob

      - name: Upload artifacts
        run: |
          node .github/scripts/upload-artifacts.js \
            "rustdesk-ubuntu18-${{ github.run_number }}" \
            "rustdesk*.deb" \
            "rustdesk*.rpm"
```

### 示例 3: 分别上传不同类型的文件

```yaml
      - name: Upload packages
        run: |
          node .github/scripts/upload-artifacts.js \
            "packages-${{ github.run_number }}" \
            "*.deb" \
            "*.rpm" \
            "*.pkg.tar.zst"

      - name: Upload logs
        run: |
          node .github/scripts/upload-artifacts.js \
            "logs-${{ github.run_number }}" \
            "*.log"
```

### 示例 4: 带错误处理

```yaml
      - name: Upload artifacts
        id: upload
        run: |
          node .github/scripts/upload-artifacts.js \
            "rustdesk-${{ github.run_number }}" \
            "rustdesk*.deb" \
            "rustdesk*.rpm" || {
              echo "::error::Artifact upload failed"
              exit 1
            }

      - name: Upload failed - send notification
        if: failure() && steps.upload.outcome == 'failure'
        run: echo "Artifact upload failed, please check the logs"
```

## 脚本输出

脚本会输出详细的上传信息：

```
==========================================
GitHub Actions Artifact Upload
==========================================
📦 Artifact Name: rustdesk-ubuntu18
📁 Root Directory: /workspace
🔍 File Patterns: rustdesk*.deb, rustdesk*.rpm

🔍 Searching for: rustdesk*.deb
✓ Found 1 file(s):
  - rustdesk-1.4.2-x86_64-ubuntu18.deb (25.43 MB)

🔍 Searching for: rustdesk*.rpm
✓ Found 2 file(s):
  - rustdesk-1.4.2-x86_64.rpm (25.21 MB)
  - rustdesk-1.4.2-x86_64-suse.rpm (25.22 MB)

📤 Uploading 3 file(s) to artifact "rustdesk-ubuntu18"...

==========================================
✅ Upload Complete!
==========================================
📦 Artifact Name: rustdesk-ubuntu18
🆔 Artifact ID: 123456789
📊 Size: 79823456 bytes

📁 Uploaded files:
  1. rustdesk-1.4.2-x86_64-ubuntu18.deb
  2. rustdesk-1.4.2-x86_64.rpm
  3. rustdesk-1.4.2-x86_64-suse.rpm
```

## 文件模式匹配

脚本使用 `glob` 库进行文件匹配，支持以下模式：

- `*` - 匹配任意字符（不包括路径分隔符）
- `**` - 匹配任意字符（包括路径分隔符）
- `?` - 匹配单个字符
- `[abc]` - 匹配字符集中的任一字符
- `{a,b,c}` - 匹配大括号中的任一模式

### 示例模式

```bash
# 匹配所有 .deb 文件
"*.deb"

# 匹配所有子目录中的 .log 文件
"**/*.log"

# 匹配特定前缀的文件
"rustdesk-*.deb"

# 匹配多种扩展名
"rustdesk*.{deb,rpm,pkg.tar.zst}"
```

## 配置选项

### Artifact 保留天数

默认保留 30 天，可以在脚本中修改：

```javascript
const uploadResponse = await artifact.uploadArtifact(
  artifactName,
  files,
  rootDirectory,
  {
    retentionDays: 7,  // 修改为 7 天
  }
);
```

## 故障排查

### 问题：找不到文件

```
⚠️  No files found matching: rustdesk*.deb
❌ No files found to upload!
```

**解决方法**：
1. 检查文件是否存在：`ls -la rustdesk*.deb`
2. 确认文件路径是相对于工作目录的
3. 检查文件模式是否正确

### 问题：Node.js 版本不兼容

```
Error: @actions/artifact requires Node.js >= 16
```

**解决方法**：
使用 `actions/setup-node@v3` 安装 Node.js 16 或更高版本：

```yaml
- name: Setup Node.js
  uses: actions/setup-node@v3
  with:
    node-version: '16'
```

### 问题：缺少依赖

```
Error: Cannot find module '@actions/artifact'
```

**解决方法**：
在上传前安装依赖：

```yaml
- name: Install dependencies
  run: npm install @actions/artifact glob
```

## 与官方 Action 的对比

| 特性 | 官方 upload-artifact@v4 | 自定义脚本 |
|------|-------------------------|-----------|
| Node 版本要求 | Node 20 | Node 16+ |
| 使用难度 | 简单 | 中等 |
| 自定义能力 | 有限 | 完全可定制 |
| 文件模式匹配 | 内置 | 使用 glob |
| 错误处理 | 自动 | 需要自行处理 |
| 性能 | 优化过 | 依赖实现 |

## 测试

运行测试 workflow：

```bash
# 手动触发测试
gh workflow run test-artifact-upload.yml

# 或推送到测试分支
git checkout -b test-artifact-upload
git push origin test-artifact-upload
```

## 参考资料

- [@actions/artifact 文档](https://github.com/actions/toolkit/tree/main/packages/artifact)
- [glob 模式匹配](https://github.com/isaacs/node-glob)
- [GitHub Actions Artifacts API](https://docs.github.com/en/rest/actions/artifacts)

## 许可证

与 RustDesk 项目保持一致。
