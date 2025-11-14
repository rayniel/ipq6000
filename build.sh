#!/bin/bash
# 用于 OpenWrt 编译的多核参数和本地日志方案，同时本地显示进度

function usage() {
    echo "用法: $0 [-j <线程数>] [-l <日志文件名>]"
    echo "  -j <线程数>      指定 make 并发线程数，默认全部核心"
    echo "  -l <日志文件>    指定日志文件路径，默认 build.log"
    echo "  -h               显示帮助"
}

# 默认参数
CORES=$(nproc)
LOGFILE="build.log"

# 参数解析
while getopts "j:l:h" opt; do
    case "$opt" in
        j) CORES="$OPTARG" ;;
        l) LOGFILE="$OPTARG" ;;
        h) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done

echo "开始 OpenWrt 编译，线程数: $CORES"
echo "日志：$LOGFILE"
echo "-------------------------------"

# 本地终端会实时显示所有编译输出，同时保存完整日志
make -j"$CORES"  V=s 2>&1 | tee "$LOGFILE"
MAKE_CODE=${PIPESTATUS[0]}

if [[ $MAKE_CODE != 0 ]]; then
    echo "-------------------------------"
    echo "编译失败，退出码：$MAKE_CODE，日志最后30行："
    tail -n 30 "$LOGFILE"
    exit $MAKE_CODE
else
    echo "编译完成，日志已保存到 $LOGFILE"
fi0
