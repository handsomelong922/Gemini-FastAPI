#!/bin/bash

# 自动化依赖更新脚本
# 作者: handsomelong922
# 日期: 2025-08-31

set -e  # 遇到错误时退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_info() {
    echo -e "${BLUE}[信息]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

print_error() {
    echo -e "${RED}[错误]${NC} $1"
}

# 检查必要的文件
check_files() {
    if [ ! -f "pyproject.toml" ]; then
        print_error "当前目录没有 pyproject.toml 文件"
        exit 1
    fi
    
    if [ ! -f "uv.lock" ]; then
        print_warning "没有找到 uv.lock 文件，将创建新的"
    fi
}

# 检查 uv 是否安装
check_uv() {
    if ! command -v uv &> /dev/null; then
        print_error "uv 命令未找到，请先安装 uv"
        echo "安装方法："
        echo "  PowerShell: powershell -c \"irm https://astral.sh/uv/install.ps1 | iex\""
        echo "  或者: pip install uv"
        exit 1
    fi
    
    print_info "uv 版本: $(uv --version)"
}

# 备份现有文件
backup_files() {
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    
    if [ -f "uv.lock" ]; then
        cp uv.lock "uv.lock.backup_${timestamp}"
        print_info "已备份 uv.lock 到 uv.lock.backup_${timestamp}"
    fi
    
    cp pyproject.toml "pyproject.toml.backup_${timestamp}"
    print_info "已备份 pyproject.toml 到 pyproject.toml.backup_${timestamp}"
}

# 显示当前依赖状态
show_current_status() {
    print_info "当前 pyproject.toml 中的 gemini-webapi 要求:"
    grep "gemini-webapi" pyproject.toml || print_warning "未找到 gemini-webapi 依赖"
    
    if [ -f "uv.lock" ]; then
        print_info "当前 uv.lock 中的 gemini-webapi 版本:"
        grep -A 3 '"gemini-webapi"' uv.lock || print_warning "uv.lock 中未找到 gemini-webapi"
    fi
}

# 更新依赖
update_dependencies() {
    print_info "开始更新依赖..."
    
    # 选择更新方式
    echo "请选择更新方式:"
    echo "1) 强制重新解析所有依赖（删除 uv.lock 重新生成）"
    echo "2) 仅升级 gemini-webapi"
    echo "3) 升级所有可升级的包"
    read -p "请输入选项 (1-3): " choice
    
    case $choice in
        1)
            print_info "删除现有 uv.lock 文件..."
            rm -f uv.lock
            print_info "重新生成 uv.lock 文件..."
            uv sync
            ;;
        2)
            print_info "仅升级 gemini-webapi..."
            uv sync --upgrade-package gemini-webapi
            ;;
        3)
            print_info "升级所有可升级的包..."
            uv sync --upgrade
            ;;
        *)
            print_error "无效选项"
            exit 1
            ;;
    esac
}

# 验证更新结果
verify_update() {
    print_info "验证更新结果..."
    
    # 显示新的版本信息
    print_info "新的 uv.lock 中的 gemini-webapi:"
    grep -A 10 -B 2 '"gemini-webapi"' uv.lock
    
    # 检查实际安装的版本
    print_info "检查实际安装的版本:"
    if uv show gemini-webapi; then
        print_success "gemini-webapi 安装正常"
    else
        print_error "gemini-webapi 安装可能有问题"
    fi
    
    # 测试导入
    print_info "测试模块导入..."
    if uv run python -c "import gemini_webapi; print('✓ gemini_webapi 导入成功')"; then
        print_success "模块导入测试通过"
    else
        print_error "模块导入测试失败"
    fi
}

# 询问是否提交更改
ask_commit() {
    # 检查是否在 git 仓库中
    if [ ! -d ".git" ]; then
        print_warning "当前目录不是 git 仓库，跳过提交步骤"
        return
    fi
    
    print_info "检查文件变化..."
    if git diff --quiet && git diff --cached --quiet; then
        print_info "没有检测到文件变化"
        return
    fi
    
    print_info "检测到以下文件变化:"
    git status --porcelain
    
    read -p "是否要提交这些更改到 git? (y/N): " commit_choice
    if [[ $commit_choice =~ ^[Yy]$ ]]; then
        commit_changes
    else
        print_info "跳过 git 提交"
    fi
}

# 提交更改
commit_changes() {
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    
    print_info "添加更改的文件到 git..."
    git add uv.lock
    
    # 如果 pyproject.toml 有变化也添加
    if ! git diff --quiet HEAD pyproject.toml 2>/dev/null; then
        git add pyproject.toml
        print_info "已添加 pyproject.toml 的变化"
    fi
    
    print_info "提交更改..."
    git commit -m "chore: update dependencies - ${timestamp}

- Updated gemini-webapi and related dependencies
- Regenerated uv.lock file
- Automated update on ${timestamp}"
    
    print_success "更改已提交到本地仓库"
    
    read -p "是否要推送到远程仓库? (y/N): " push_choice
    if [[ $push_choice =~ ^[Yy]$ ]]; then
        print_info "推送到远程仓库..."
        git push
        print_success "已推送到远程仓库"
    fi
}

# 清理备份文件
cleanup_backups() {
    read -p "是否要清理今天之前的备份文件? (y/N): " cleanup_choice
    if [[ $cleanup_choice =~ ^[Yy]$ ]]; then
        local today=$(date +"%Y%m%d")
        local count=0
        
        for file in *.backup_*; do
            if [ -f "$file" ]; then
                local file_date=${file##*.backup_}
                file_date=${file_date:0:8}
                if [ "$file_date" -lt "$today" ]; then
                    rm "$file"
                    ((count++))
                    print_info "已删除旧备份: $file"
                fi
            fi
        done
        
        if [ $count -eq 0 ]; then
            print_info "没有找到需要清理的旧备份文件"
        else
            print_success "已清理 $count 个旧备份文件"
        fi
    fi
}

# 主函数
main() {
    print_info "=== Gemini-FastAPI 依赖更新脚本 ==="
    print_info "开始时间: $(date)"
    print_info "用户: handsomelong922"
    echo
    
    # 执行检查
    check_uv
    check_files
    
    # 显示当前状态
    show_current_status
    echo
    
    # 询问是否继续
    read -p "是否要继续更新依赖? (y/N): " continue_choice
    if [[ ! $continue_choice =~ ^[Yy]$ ]]; then
        print_info "操作已取消"
        exit 0
    fi
    
    # 备份文件
    backup_files
    
    # 更新依赖
    update_dependencies
    
    # 验证结果
    verify_update
    
    # 询问是否提交
    ask_commit
    
    # 清理备份
    cleanup_backups
    
    print_success "=== 依赖更新完成 ==="
    print_info "结束时间: $(date)"
}

# 错误处理
trap 'print_error "脚本执行过程中出现错误，退出码: $?"' ERR

# 运行主函数
main "$@"


