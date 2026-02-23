#!/usr/bin/env python3
"""
EasyMultiProfiler 统一启动器
同时支持 R包调用 和 网页界面
"""

import os
import sys
import subprocess
import webbrowser
import threading
import time

def print_banner():
    print("""
╔══════════════════════════════════════════════════════════════╗
║           🧬 EasyMultiProfiler v2.0                  ║
║         统一多组学分析平台 (R包 + 网页版)              ║
╚══════════════════════════════════════════════════════════════╝
    """)

def check_r_installed():
    """检查R和EasyMultiProfiler包是否安装"""
    try:
        result = subprocess.run(
            ['R', '--quiet', '-e', 'library(EasyMultiProfiler)'],
            capture_output=True,
            text=True,
            timeout=10
        )
        if result.returncode == 0:
            return True
    except:
        pass
    return False

def check_python_deps():
    """检查Python依赖"""
    try:
        import flask
        import requests
        return True
    except ImportError:
        return False

def install_r_package():
    """安装R包"""
    print("正在安装 EasyMultiProfiler R包...")
    cmd = '''
options(repos = c(CRAN = "https://mirrors.tuna.tsinghua.edu.cn/CRAN/"))
if (!requireNamespace("pak", quietly = TRUE)) install.packages("pak")
pak::pak("liubingdong/EasyMultiProfiler")
'''
    subprocess.run(['R', '--vanilla', '-e', cmd])
    print("✅ R包安装完成")

def install_python_deps():
    """安装Python依赖"""
    print("正在安装Python依赖...")
    subprocess.run([sys.executable, '-m', 'pip', 'install', '-q', 
                 'flask', 'requests', 'beautifulsoup4', 'numpy', 'pandas'])
    print("✅ Python依赖安装完成")

def clone_web_version():
    """克隆网页版"""
    if not os.path.exists('EasyMultiProfiler-Web'):
        print("正在克隆网页版...")
        subprocess.run(['git', 'clone', 
                     'https://github.com/xielab2017/EasyMultiProfiler-Web.git'])
        print("✅ 网页版准备完成")
    else:
        print("✅ 网页版已存在")

def start_web_server():
    """启动网页服务器"""
    print("\n启动网页服务...")
    os.chdir('EasyMultiProfiler-Web/web')
    subprocess.run([sys.executable, 'app.py'])

def open_browser():
    """延迟打开浏览器"""
    time.sleep(2)
    webbrowser.open('http://localhost:5000')

def main():
    print_banner()
    
    # 检查R包
    r_installed = check_r_installed()
    python_deps = check_python_deps()
    
    print("检查安装状态:")
    print(f"  {'✅' if r_installed else '❌'} R包: EasyMultiProfiler")
    print(f"  {'✅' if python_deps else '❌'} Python依赖")
    print()
    
    if not r_installed:
        print("提示: R包未安装，需要R 4.3+环境")
        install = input("是否现在安装? [y/N]: ").lower().strip()
        if install == 'y':
            install_r_package()
    
    if not python_deps:
        print("提示: Python依赖未安装")
        install = input("是否现在安装? [y/N]: ").lower().strip()
        if install == 'y':
            install_python_deps()
    
    # 克隆网页版
    if not os.path.exists('EasyMultiProfiler-Web'):
        clone = input("是否克隆网页版? [Y/n]: ").lower().strip()
        if clone != 'n':
            clone_web_version()
    
    # 启动
    print("\n" + "="*50)
    print("启动服务:")
    print("="*50)
    print()
    print("选项:")
    print("  1. 启动网页界面")
    print("  2. 仅检查R包")
    print("  3. 安装并退出")
    print()
    
    choice = input("请选择 [1-3]: ").strip()
    
    if choice == '1':
        if not os.path.exists('EasyMultiProfiler-Web'):
            print("❌ 网页版未找到，请先克隆")
            return
        
        # 启动浏览器
        threading.Thread(target=open_browser, daemon=True).start()
        
        # 启动服务
        start_web_server()
        
    elif choice == '2':
        if r_installed:
            print("\n✅ R包已就绪！使用:")
            print("   library(EasyMultiProfiler)")
        else:
            print("\n❌ R包未安装")
    
    elif choice == '3':
        print("\n执行安装...")
        if not r_installed:
            install_r_package()
        if not python_deps:
            install_python_deps()
        clone_web_version()
        print("\n✅ 全部完成！")
        print("\n使用方法:")
        print("  R包: library(EasyMultiProfiler)")
        print("  网页: cd EasyMultiProfiler-Web/web && python app.py")

if __name__ == '__main__':
    main()
