#!/bin/bash
# EasyMultiProfiler 一键安装脚本
# 同时安装 R包 和 网页版

set -e

echo "======================================"
echo "   EasyMultiProfiler 统一安装程序"
echo "======================================"
echo ""

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 检查系统
check_system() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        SYSTEM="macOS"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        SYSTEM="Linux"
    elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
        SYSTEM="Windows"
    else
        echo -e "${RED}不支持的系统${NC}"
        exit 1
    fi
    echo -e "${GREEN}检测到系统: $SYSTEM${NC}"
}

# 检查R
check_r() {
    echo ""
    echo "检查R环境..."
    if command -v R &> /dev/null; then
        R_VERSION=$(R --version | head -1)
        echo -e "${GREEN}R已安装: $R_VERSION${NC}"
        
        # 检查版本
        R_VER=$(R --version | head -1 | grep -oP '\d+\.\d+' | head -1)
        if (( $(echo "$R_VER >= 4.3" | bc -l) 2>/dev/null || [[ "$R_VER" == "4.3" || "$R_VER" == "4.4" || "$R_VER" == "4.5" ]]); then
            echo -e "${GREEN}R版本符合要求 (>= 4.3)${NC}"
            return 0
        else
            echo -e "${YELLOW}警告: R版本可能过低，建议升级到4.3+${NC}"
        fi
    else
        echo -e "${YELLOW}R未安装，是否安装? [Y/n]${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]] || [[ -z "$response" ]]; then
            install_r
        fi
    fi
    return 0
}

# 安装R (macOS)
install_r_mac() {
    if command -v brew &> /dev/null; then
        echo "使用Homebrew安装R..."
        brew install r
    else
        echo "请从 https://cran.r-project.org/ 下载R"
    fi
}

# 安装R (Linux)
install_r_linux() {
    echo "安装R..."
    sudo apt-get update
    sudo apt-get install -y r-base r-base-dev
}

# 安装R
install_r() {
    if [[ "$SYSTEM" == "macOS" ]]; then
        install_r_mac
    elif [[ "$SYSTEM" == "Linux" ]]; then
        install_r_linux
    fi
}

# 安装Python依赖
install_python() {
    echo ""
    echo "安装Python依赖..."
    pip install -q flask requests beautifulsoup4 numpy pandas
    echo -e "${GREEN}Python依赖安装完成${NC}"
}

# 安装R包
install_r_package() {
    echo ""
    echo "安装EasyMultiProfiler R包..."
    R --vanilla << 'RCODE'
options(repos = c(CRAN = "https://mirrors.tuna.tsinghua.edu.cn/CRAN/"))
if (!requireNamespace("pak", quietly = TRUE)) install.packages("pak")
pak::pak("liubingdong/EasyMultiProfiler")
RCODE
    echo -e "${GREEN}R包安装完成${NC}"
}

# 克隆网页版
install_web() {
    echo ""
    echo "克隆网页版..."
    if [ -d "EasyMultiProfiler-Web" ]; then
        echo "网页版已存在"
    else
        git clone https://github.com/xielab2017/EasyMultiProfiler-Web.git
    fi
    echo -e "${GREEN}网页版准备完成${NC}"
}

# 主菜单
main_menu() {
    echo ""
    echo "请选择安装选项:"
    echo "1. 仅安装R包"
    echo "2. 仅安装网页版"
    echo "3. 安装全部 (R包 + 网页版)"
    echo "4. 退出"
    echo ""
    read -p "请输入选项 [1-4]: " choice
    
    case $choice in
        1)
            check_system
            check_r
            install_r_package
            ;;
        2)
            check_system
            install_python
            install_web
            ;;
        3)
            check_system
            check_r
            install_python
            install_r_package
            install_web
            ;;
        4)
            echo "退出"
            exit 0
            ;;
        *)
            echo "无效选项"
            exit 1
            ;;
    esac
}

# 启动服务
start_services() {
    echo ""
    echo "======================================"
    echo "安装完成！"
    echo "======================================"
    echo ""
    echo "启动服务:"
    echo ""
    echo "1. R包使用:"
    echo "   library(EasyMultiProfiler)"
    echo ""
    echo "2. 网页版:"
    echo "   cd EasyMultiProfiler-Web"
    echo "   python web/app.py"
    echo "   然后浏览器访问 http://localhost:5000"
    echo ""
}

# 运行
main_menu
start_services
