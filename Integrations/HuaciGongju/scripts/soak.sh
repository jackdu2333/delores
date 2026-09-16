#!/bin/bash
#
# 资源回归测试（soak test）：对正在运行的划词小工具做低频采样，
# 观察空闲状态下的内存与 CPU 是否稳定，用来发现「缓慢泄漏」和「待机不静默」。
#
# 用法：
#   ./scripts/soak.sh                # 每 10s 采一次，共 36 次（6 分钟）
#   ./scripts/soak.sh 5 60           # 每 5s 采一次，共 60 次（5 分钟）
#   ./scripts/soak.sh 60 60          # 每 60s 采一次，共 60 次（1 小时，建议挂着跑）
#
# 判读：
#   RSS 长期单调上升且不回落  → 疑似泄漏
#   CPU 空闲时持续 > 1%      → 待机不静默（多半是全局事件监听没关掉）
#
# 注意：采样本身开销极低（一次 ps），不会干扰被测进程。

set -uo pipefail

INTERVAL="${1:-10}"
SAMPLES="${2:-36}"
PROC_NAME="HuaciGongju"

PID=$(pgrep -x "$PROC_NAME" | head -1)
if [ -z "$PID" ]; then
    echo "❌ 没找到运行中的 $PROC_NAME。请先启动应用（仓库根目录的 划词小工具.app）。"
    exit 1
fi

BIN=$(ps -p "$PID" -o comm= 2>/dev/null)
echo "🎯 采样对象：PID $PID ($BIN)"
echo "   采样间隔 ${INTERVAL}s × ${SAMPLES} 次 ≈ $((INTERVAL * SAMPLES / 60)) 分钟"
printf "\n%-8s %-12s %-8s\n" "次数" "RSS(MB)" "CPU(%)"
printf -- "-------------------------------------------\n"

rss_min=999999999; rss_max=0; rss_sum=0
cpu_max=0; cpu_sum=0
rss_first=0; rss_last=0

for ((i = 1; i <= SAMPLES; i++)); do
    if ! kill -0 "$PID" 2>/dev/null; then
        echo "⚠️  进程 $PID 已退出，采样提前结束。"
        break
    fi
    read -r rss_kb cpu < <(ps -p "$PID" -o rss= -o pcpu= 2>/dev/null)
    [ -z "${rss_kb:-}" ] && { echo "⚠️  读不到进程信息，退出。"; break; }

    rss_mb=$((rss_kb / 1024))
    [ "$i" -eq 1 ] && rss_first=$rss_mb
    rss_last=$rss_mb

    ((rss_mb < rss_min)) && rss_min=$rss_mb
    ((rss_mb > rss_max)) && rss_max=$rss_mb
    rss_sum=$((rss_sum + rss_mb))

    cpu_int=${cpu%%.*}
    ((cpu_int > cpu_max)) && cpu_max=$cpu_int
    cpu_sum=$((cpu_sum + cpu_int))

    printf "%-8s %-12s %-8s\n" "$i/$SAMPLES" "$rss_mb" "$cpu"
    ((i < SAMPLES)) && sleep "$INTERVAL"
done

n=$SAMPLES
printf -- "-------------------------------------------\n"
echo "📊 汇总（共采样 ${n} 次）"
echo "   RSS： 首 ${rss_first}MB → 末 ${rss_last}MB  （最小 ${rss_min} / 最大 ${rss_max} / 平均 $((rss_sum / n)) MB）"
echo "   CPU： 峰值 ${cpu_max}%  平均 $((cpu_sum / n))%"
echo
echo "   判读：RSS 末值相对首值增长 $((rss_last - rss_first))MB；"
echo "         若持续增长且不回落 → 疑似泄漏；若 CPU 空闲平均值 > 1% → 待机不静默。"
