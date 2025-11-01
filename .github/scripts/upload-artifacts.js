#!/usr/bin/env node

/**
 * GitHub Actions Artifact Upload Script
 *
 * 使用 @actions/artifact 包上传构建产物
 * 支持 Node 16+ 环境
 *
 * 使用方法:
 *   node upload-artifacts.js <artifact-name> <file-patterns...>
 *
 * 示例:
 *   node upload-artifacts.js rustdesk-ubuntu18 "rustdesk*.deb" "rustdesk*.rpm"
 */

const { DefaultArtifactClient } = require('@actions/artifact');
const { glob } = require('glob');
const path = require('path');
const fs = require('fs');

// 解析命令行参数
const args = process.argv.slice(2);

if (args.length < 2) {
  console.error('❌ 用法: node upload-artifacts.js <artifact-name> <file-patterns...>');
  console.error('');
  console.error('示例:');
  console.error('  node upload-artifacts.js rustdesk-ubuntu18 "rustdesk*.deb" "rustdesk*.rpm"');
  console.error('  node upload-artifacts.js build-logs "*.log"');
  process.exit(1);
}

const artifactName = args[0];
const filePatterns = args.slice(1);
const rootDirectory = process.cwd();

console.log('==========================================');
console.log('GitHub Actions Artifact Upload');
console.log('==========================================');
console.log(`📦 Artifact Name: ${artifactName}`);
console.log(`📁 Root Directory: ${rootDirectory}`);
console.log(`🔍 File Patterns: ${filePatterns.join(', ')}`);
console.log('');

async function findFiles(patterns) {
  const allFiles = [];

  for (const pattern of patterns) {
    console.log(`🔍 Searching for: ${pattern}`);

    const files = await glob(pattern, {
      cwd: rootDirectory,
      absolute: false,
      nodir: true
    });

    if (files.length === 0) {
      console.log(`⚠️  No files found matching: ${pattern}`);
    } else {
      console.log(`✓ Found ${files.length} file(s):`);
      files.forEach(file => {
        const stat = fs.statSync(path.join(rootDirectory, file));
        const sizeInMB = (stat.size / (1024 * 1024)).toFixed(2);
        console.log(`  - ${file} (${sizeInMB} MB)`);
      });
      allFiles.push(...files);
    }
  }

  return allFiles;
}

async function uploadArtifact() {
  try {
    // 查找所有匹配的文件
    const files = await findFiles(filePatterns);

    if (files.length === 0) {
      console.error('');
      console.error('❌ No files found to upload!');
      process.exit(1);
    }

    console.log('');
    console.log(`📤 Uploading ${files.length} file(s) to artifact "${artifactName}"...`);
    console.log('');

    // 创建 artifact client
    const artifact = new DefaultArtifactClient();

    // 上传文件
    const uploadResponse = await artifact.uploadArtifact(
      artifactName,
      files,
      rootDirectory,
      {
        // 保留文件路径结构
        retentionDays: 30,
      }
    );

    console.log('');
    console.log('==========================================');
    console.log('✅ Upload Complete!');
    console.log('==========================================');
    console.log(`📦 Artifact Name: ${uploadResponse.artifactName}`);
    console.log(`🆔 Artifact ID: ${uploadResponse.artifactId}`);
    console.log(`📊 Size: ${uploadResponse.size} bytes`);
    console.log('');

    // 输出文件列表
    console.log('📁 Uploaded files:');
    files.forEach((file, index) => {
      console.log(`  ${index + 1}. ${file}`);
    });
    console.log('');

    process.exit(0);

  } catch (error) {
    console.error('');
    console.error('==========================================');
    console.error('❌ Upload Failed!');
    console.error('==========================================');
    console.error(`Error: ${error.message}`);

    if (error.stack) {
      console.error('');
      console.error('Stack trace:');
      console.error(error.stack);
    }

    process.exit(1);
  }
}

// 执行上传
uploadArtifact();
