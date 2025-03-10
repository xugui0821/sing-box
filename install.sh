#!/bin/bash

# 定义颜色
red='\e[31m'
yellow='\e[33m'
gray='\e[90m'
green='\e[92m'
blue='\e[94m'
magenta='\e[95m'
cyan='\e[96m'
none='\e[0m'

# 定义输出函数
_red() { echo -e ${red}$@${none}; }
_blue() { echo -e ${blue}$@${none}; }
_cyan() { echo -e ${cyan}$@${none}; }
_green() { echo -e ${green}$@${none}; }
_yellow() { echo -e ${yellow}$@${none}; }
_magenta() { echo -e ${magenta}$@${none}; }
_red_bg() { echo -e "\e[41m$@${none}"; }

is_err=$(_red_bg 错误!)
is_warn=$(_red_bg 警告!)

err() { 
    echo -e "\n$is_err $@\n" && exit 1 
}

warn() { 
    echo -e "\n$is_warn $@\n" 
}

# 检查是否为root用户
[[ $EUID != 0 ]] && err "当前非 ${yellow}ROOT用户.${none}"

# 检查包管理器
cmd=$(type -P apt-get || type -P yum)
[[ ! $cmd ]] && err "此脚本仅支持 ${yellow}(Ubuntu or Debian or CentOS)${none}."

# 检查systemd
[[ ! $(type -P systemctl) ]] && {
    err "此系统缺少 ${yellow}(systemctl)${none}, 请尝试执行:${yellow} ${cmd} update -y;${cmd} install systemd -y ${none}来修复此错误."
}

# 检查wget
is_wget=$(type -P wget)

# 检查架构
case $(uname -m) in
    amd64 | x86_64)
        is_arch=amd64
        ;;
    _aarch64_ | _armv8_)
        is_arch=arm64
        ;;
    *)
        err "此脚本仅支持 64 位系统..."
        ;;
esac

# 定义变量
is_core=sing-box
is_core_name=sing-box
is_core_dir=/etc/$is_core
is_core_bin=$is_core_dir/bin/$is_core
is_core_repo=SagerNet/$is_core
is_conf_dir=$is_core_dir/conf
is_log_dir=/var/log/$is_core
is_sh_bin=/usr/local/bin/$is_core
is_sh_dir=$is_core_dir/sh
is_sh_repo=$author/$is_core
is_pkg="wget tar"
is_config_json=$is_core_dir/config.json

tmp_var_lists=(
    tmpcore
    tmpsh
    tmpjq
    is_core_ok
    is_sh_ok
    is_jq_ok
    is_pkg_ok
)

# 创建临时目录
tmpdir=$(mktemp -u)
[[ ! $tmpdir ]] && {
    tmpdir=/tmp/tmp-$RANDOM
}

# 设置临时变量
for i in ${tmp_var_lists[@]}; do
    export $i=$tmpdir/$i
done

# 加载bash脚本
load() {
    . $is_sh_dir/src/$1
}

# 修改wget命令以支持进度条和下载速度
_wget() {
    [[ $proxy ]] && export https_proxy=$proxy
    wget --no-check-certificate --progress=bar:force --show-progress $*
}

# 打印消息
msg() {
    case $1 in
        warn)
            local color=$yellow
            ;;
        err)
            local color=$red
            ;;
        ok)
            local color=$green
            ;;
    esac
    echo -e "${color}$(date +'%T')${none}) ${2}"
}

# 显示帮助信息
show_help() {
    echo -e "Usage: $0 [-f xxx | -l | -p xxx | -v xxx | -h]"
    echo -e "  -f, --core-file <path>          自定义 $is_core_name 文件路径, e.g., -f /root/$is_core-linux-amd64.tar.gz"
    echo -e "  -l, --local-install             本地获取安装脚本, 使用当前目录"
    echo -e "  -p, --proxy <addr>              使用代理下载, e.g., -p http://127.0.0.1:2333 or -p socks5://127.0.0.1:2333"
    echo -e "  -v, --core-version <ver>        自定义 $is_core_name 版本, e.g., -v v1.8.13"
    echo -e "  -h, --help                      显示此帮助界面\n"
    exit 0
}

# 安装依赖包
install_pkg() {
    cmd_not_found=
    for i in $*; do
        [[ ! $(type -P $i) ]] && cmd_not_found="$cmd_not_found，$i"
    done
    if [[ $cmd_not_found ]]; then
        pkg=$(echo $cmd_not_found | sed 's/,/ /g')
        msg warn "安装依赖包 >${pkg}"
        $cmd install -y $pkg &>/dev/null
        if [[ $? != 0 ]]; then
            [[ $cmd =~ yum ]] && yum install epel-release -y &>/dev/null
            $cmd update -y &>/dev/null
            $cmd install -y $pkg &>/dev/null
            [[ $? == 0 ]] && >$is_pkg_ok
        else
            >$is_pkg_ok
        fi
    else
        >$is_pkg_ok
    fi
}

# 下载文件
download() {
    case $1 in
        core)
            [[ ! $is_core_ver ]] && is_core_ver=$(_wget -qO- "https://api.github.com/repos/${is_core_repo}/releases/latest?v=$RANDOM" | grep tag_name | egrep -o 'v([0-9.]+)')
            [[ $is_core_ver ]] && link="https://gh-proxy.com//${is_core_repo}/releases/download/${is_core_ver}/${is_core}-${is_core_ver:1}-linux-${is_arch}.tar.gz"
            name=$is_core_name
            tmpfile=$tmpcore
            is_ok=$is_core_ok
            ;;
        sh)
            link=https://gh-proxy.com/github.com/${is_sh_repo}/releases/latest/download/code.tar.gz
            name="$is_core_name 脚本"
            tmpfile=$tmpsh
            is_ok=$is_sh_ok
            ;;
        jq)
            link=https://gh-proxy.com/github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-$is_arch
            name="jq"
            tmpfile=$tmpjq
            is_ok=$is_jq_ok
            ;;
    esac
    [[ $link ]] && {
        msg warn "下载 ${name} > ${link}"
        if _wget -t 3 -q -c $link -O $tmpfile; then
            mv -f $tmpfile $is_ok
        fi
    }
}

# 获取服务器IP
get_ip() {
    export "$(_wget -4 -qO- https://one.one.one.one/cdn-cgi/trace | grep ip=)" &>/dev/null
    [[ -z $ip ]] && export "$(_wget -6 -qO- https://one.one.one.one/cdn-cgi/trace | grep ip=)" &>/dev/null
}

# 检查背景任务状态
check_status() {
    # 依赖包安装失败
    [[ ! -f $is_pkg_ok ]] && {
        msg err "安装依赖包失败"
        msg err "请尝试手动安装依赖包: $cmd update -y; $cmd install -y $pkg"
        is_fail=1
    }
    # 下载文件状态
    if [[ $is_wget ]]; then
        [[ ! -f $is_core_ok ]] && {
            msg err "下载 ${is_core_name} 失败"
            is_fail=1
        }
        [[ ! -f $is_sh_ok ]] && {
            msg err "下载 ${is_core_name} 脚本失败"
            is_fail=1
        }
        [[ ! -f $is_jq_ok ]] && {
            msg err "下载 jq 失败"
            is_fail=1
        }
    else
        [[ ! $is_fail ]] && {
            is_wget=1
            [[ ! $is_core_file ]] && download core &
            [[ ! $local_install ]] && download sh &
            [[ $jq_not_found ]] && download jq &
            get_ip
            wait
            check_status
        }
    fi
    # 发现失败状态，删除临时目录并退出
    [[ $is_fail ]] && {
        exit_and_del_tmpdir
    }
}

# 参数检查
pass_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f | --core-file)
                [[ -z $2 ]] && {
                    err "($1) 缺少必需参数, 正确使用示例: [$1 /root/$is_core-linux-amd64.tar.gz]"
                } || [[ ! -f $2 ]] && {
                    err "($2) 不是一个常规的文件."
                }
                is_core_file=$2
                shift 2
                ;;
            -l | --local-install)
                [[ ! -f ${PWD}/src/core.sh || ! -f ${PWD}/$is_core.sh ]] && {
                    err "当前目录 (${PWD}) 非完整的脚本目录."
                }
                local_install=1
                shift 1
                ;;
            -p | --proxy)
                [[ -z $2 ]] && {
                    err "($1) 缺少必需参数, 正确使用示例: [$1 http://127.0.0.1:2333 or -p socks5://127.0.0.1:2333]"
                }
                proxy=$2
                shift 2
                ;;
            -v | --core-version)
                [[ -z $2 ]] && {
                    err "($1) 缺少必需参数, 正确使用示例: [$1 v1.8.13]"
                }
                is_core_ver=v${2//v/}
                shift 2
                ;;
            -h | --help)
                show_help
                ;;
            *)
                echo -e "\n${is_err} ($@) 为未知参数...\n"
                show_help
                ;;
        esac
    done
    [[ $is_core_ver && $is_core_file ]] && {
        err "无法同时自定义 ${is_core_name} 版本和 ${is_core_name} 文件."
    }
}

# 退出并删除临时目录
exit_and_del_tmpdir() {
    rm -rf $tmpdir
    [[ ! $1 ]] && {
        msg err "哦豁.."
        msg err "安装过程出现错误..."
        echo -e "反馈问题) https://github.com/${is_sh_repo}/issues"
        echo
        exit 1
    }
    exit
}

# 主函数
main() {
    # 检查旧版本
    [[ -f $is_sh_bin && -d $is_core_dir/bin && -d $is_sh_dir && -d $is_conf_dir ]] && {
        err "检测到脚本已安装, 如需重装请使用${green} ${is_core} reinstall ${none}命令."
    }

    # 检查参数
    [[ $# -gt 0 ]] && pass_args $@

    # 显示欢迎信息
    clear
    echo
    echo "........... $is_core_name script by $author .........."
    echo

    # 开始安装...
    msg warn "开始安装..."
    [[ $is_core_ver ]] && msg warn "${is_core_name} 版本: ${yellow}$is_core_ver${none}"
    [[ $proxy ]] && msg warn "使用代理: ${yellow}$proxy${none}"

    # 创建临时目录
    mkdir -p $tmpdir

    # 如果is_core_file，复制文件
    [[ $is_core_file ]] && {
        cp -f $is_core_file $is_core_ok
        msg warn "${yellow}${is_core_name} 文件使用 > $is_core_file${none}"
    }

    # 本地目录安装脚本
    [[ $local_install ]] && {
        >$is_sh_ok
        msg warn "${yellow}本地获取安装脚本 > $PWD ${none}"
    }

    timedatectl set-ntp true &>/dev/null
    [[ $? != 0 ]] && {
        is_ntp_on=1
    }

    # 安装依赖包
    install_pkg $is_pkg &

    # 检查jq
    if [[ $(type -P jq) ]]; then
        >$is_jq_ok
    else
        jq_not_found=1
    fi

    # 如果wget已安装，下载核心、脚本、jq，获取IP
    [[ $is_wget ]] && {
        [[ ! $is_core_file ]] && download core &
        [[ ! $local_install ]] && download sh &
        [[ $jq_not_found ]] && download jq &
        get_ip
    }

    # 等待背景任务完成
    wait

    # 检查背景任务状态
    check_status

    # 测试is_core_file
    if [[ $is_core_file ]]; then
        mkdir -p $tmpdir/testzip
        tar zxf $is_core_ok --strip-components 1 -C $tmpdir/testzip &>/dev/null
        [[ $? != 0 ]] && {
            msg err "${is_core_name} 文件无法通过测试."
            exit_and_del_tmpdir
        }
        [[ ! -f $tmpdir/testzip/$is_core ]] && {
            msg err "${is_core_name} 文件无法通过测试."
            exit_and_del_tmpdir
        }
    fi

    # 获取服务器IP
    [[ ! $ip ]] && {
        msg err "获取服务器 IP 失败."
        exit_and_del_tmpdir
    }

    # 创建sh目录
    mkdir -p $is_sh_dir

    # 复制sh文件或解压sh压缩包
    if [[ $local_install ]]; then
        cp -rf $PWD/* $is_sh_dir
    else
        tar zxf $is_sh_ok -C $is_sh_dir
    fi

    # 创建核心二进制目录
    mkdir -p $is_core_dir/bin

    # 复制核心文件或解压核心压缩包
    if [[ $is_core_file ]]; then
        cp -rf $tmpdir/testzip/* $is_core_dir/bin
    else
        tar zxf $is_core_ok --strip-components 1 -C $is_core_dir/bin
    fi

    # 添加别名
    echo "alias sb=$is_sh_bin" >>/root/.bashrc
    echo "alias $is_core=$is_sh_bin" >>/root/.bashrc

    # 核心命令
    ln -sf $is_sh_dir/$is_core.sh $is_sh_bin
    ln -sf $is_sh_dir/$is_core.sh ${is_sh_bin/$is_core/sb}

    # jq
    [[ $jq_not_found ]] && mv -f $is_jq_ok /usr/bin/jq

    # 赋予可执行权限
    chmod +x $is_core_bin $is_sh_bin /usr/bin/jq ${is_sh_bin/$is_core/sb}

    # 创建日志目录
    mkdir -p $is_log_dir

    # 显示提示信息
    msg ok "生成配置文件..."

    # 创建systemd服务
    load systemd.sh
    is_new_install=1
    install_service $is_core &>/dev/null

    # 创建配置目录
    mkdir -p $is_conf_dir
    load core.sh

    # 创建一个reality配置
    add reality

    # 删除临时目录并退出
    exit_and_del_tmpdir
}

# 启动主函数
main $@
