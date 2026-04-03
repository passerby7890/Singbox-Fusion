#!/bin/bash

# =================================================================
#   V2bX Multi-Site Deployment Script (Google SRE Standard)
#   特性：多網站隔離共存、Docker 自動化、Sing-box 核心
#   功能：BBR / GSO / Swap / ZRAM / 健康檢查 / 端口衝突偵測
#   鏡像源：tinyserve/v2bx:latest (持續更新版)
#   版本：v2.0
# =================================================================

set -euo pipefail

# --- 顏色定義 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

normalize_api_host() {
    printf '%s' "${1:-}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's:/*$::'
}

get_config_api_host() {
    local config_path="$1"
    local api_host
    api_host=$(grep -oE '"ApiHost"[[:space:]]*:[[:space:]]*"[^"]*"' "$config_path" 2>/dev/null | head -1 | sed -E 's/^.*"ApiHost"[[:space:]]*:[[:space:]]*"([^"]*)".*$/\1/' || true)
    printf '%s' "$api_host"
}

config_uses_node_id() {
    local config_path="$1"
    local node_id="$2"
    grep -Eq "\"NodeID\"[[:space:]]*:[[:space:]]*${node_id}([[:space:]]*[,}])" "$config_path" 2>/dev/null
}

log_info()  { echo -e "${GREEN}[Info]${PLAIN} $1"; }
log_warn()  { echo -e "${YELLOW}[Warn]${PLAIN} $1"; }
log_error() { echo -e "${RED}[Error]${PLAIN} $1"; }
log_ok()    { echo -e "${GREEN}[✓]${PLAIN} $1"; }
log_fail()  { echo -e "${RED}[✗]${PLAIN} $1"; }

# =================================================================
#  List 模式：查詢所有已安裝的 V2bX 實例
# =================================================================
if [[ "${1:-}" == "list" ]]; then
    echo ""
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${CYAN}   V2bX 已安裝實例一覽${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    printf "%-15s %-25s %-12s %-15s\n" "SITE_TAG" "容器名稱" "運行狀態" "管理指令"
    echo "---------------------------------------------------------------"

    FOUND=0
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        CNAME=$(echo "$line" | awk '{print $1}')
        CSTATUS=$(echo "$line" | awk '{$1=""; print $0}' | xargs)
        TAG=$(echo "$CNAME" | sed 's/^v2bx-[a-zA-Z0-9]*-//')
        CMD="v2bx-${TAG}"
        printf "%-15s %-25s %-12s %-15s\n" "$TAG" "$CNAME" "$CSTATUS" "$CMD"
        FOUND=1
    done < <(docker ps -a --filter "name=v2bx-" --format "{{.Names}} {{.Status}}" 2>/dev/null)

    if [ "$FOUND" -eq 0 ]; then
        echo -e "${YELLOW}  （尚未安裝任何 V2bX 實例）${PLAIN}"
    fi
    echo ""
    exit 0
fi

# =================================================================
#  0. 變數檢查與驗證
# =================================================================
if [[ -z "${API_HOST:-}" || -z "${API_KEY:-}" || -z "${NODE_IDS:-}" || -z "${INSTALL_TYPE:-}" || -z "${SITE_TAG:-}" ]]; then
    log_error "缺少必要變數！"
    echo -e "為了實現多站點隔離，請務必 export 以下變數："
    echo -e "  - ${CYAN}SITE_TAG${PLAIN}     (例如: siteA, hk_node, hash234)"
    echo -e "  - ${CYAN}API_HOST${PLAIN}     (面板地址)"
    echo -e "  - ${CYAN}API_KEY${PLAIN}      (通訊密鑰)"
    echo -e "  - ${CYAN}NODE_IDS${PLAIN}     (節點 ID，多個用逗號分隔)"
    echo -e "  - ${CYAN}INSTALL_TYPE${PLAIN} (ss / v2ray / trojan / hy2)"
    exit 1
fi

# SITE_TAG 格式驗證（只允許字母、數字、底線）
if [[ ! "$SITE_TAG" =~ ^[a-zA-Z0-9_]+$ ]]; then
    log_error "SITE_TAG 只允許字母、數字和底線！當前值: '${SITE_TAG}'"
    exit 1
fi

# =================================================================
#  1. 定義隔離與核心變數
# =================================================================
: "${IMAGE_NAME:=tinyserve/v2bx:latest}"
: "${V2RAY_PROTOCOL:=vmess}"

# 根據 SITE_TAG 生成唯一的容器名與路徑
UNIQUE_ID="${INSTALL_TYPE}-${SITE_TAG}"
CONTAINER_NAME="v2bx-${UNIQUE_ID}"
HOST_CONFIG_DIR="/etc/V2bX_${UNIQUE_ID}"
SHORTCUT_CMD="v2bx-${SITE_TAG}"

# 初始化額外參數
EXTRA_DOCKER_ARGS=""

# 根據安裝類型設定參數
case "$INSTALL_TYPE" in
    ss|shadowsocks)
        TARGET_NODE_TYPE="shadowsocks"
        DISPLAY_NAME="Shadowsocks [${SITE_TAG}]"
        ;;
    v2ray|vmess|vless)
        TARGET_NODE_TYPE="${V2RAY_PROTOCOL}"
        DISPLAY_NAME="V2Ray [${SITE_TAG}]"
        ;;
    trojan)
        TARGET_NODE_TYPE="trojan"
        DISPLAY_NAME="Trojan [${SITE_TAG}]"
        ;;
    hy2|hysteria2)
        TARGET_NODE_TYPE="hysteria2"
        DISPLAY_NAME="Hysteria2 [${SITE_TAG}]"
        EXTRA_DOCKER_ARGS="--cap-add=NET_ADMIN"
        ;;
    *)
        log_error "未知的 INSTALL_TYPE: $INSTALL_TYPE"
        echo -e "支援的類型: ${CYAN}ss${PLAIN}, ${CYAN}v2ray${PLAIN}, ${CYAN}trojan${PLAIN}, ${CYAN}hy2${PLAIN}"
        exit 1
        ;;
esac

# =================================================================
#  [模組] 系統全方位優化 (BBR, GSO, Swap, ZRAM, Docker)
# =================================================================
system_optimization() {
    set +e
    log_info "正在執行系統全方位優化..."

    # 1. 安裝基礎工具
    if [ -x "$(command -v apt-get)" ]; then
        # 修復可能的 dpkg/apt 鎖死
        if fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; then
            log_warn "偵測到 dpkg 鎖死，嘗試修復..."
            kill -9 $(fuser /var/lib/dpkg/lock-frontend 2>/dev/null) 2>/dev/null || true
            rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock
            dpkg --configure -a
        fi
        apt-get update -y >/dev/null 2>&1
        apt-get install -y curl wget ethtool >/dev/null 2>&1
    elif [ -x "$(command -v yum)" ]; then
        yum install -y curl wget ethtool >/dev/null 2>&1
    fi

    # 2. 開啟 BBR 與網路優化
    if ! grep -q "net.ipv4.tcp_congestion_control = bbr" /etc/sysctl.conf; then
        log_warn "開啟 BBR..."
        cat >> /etc/sysctl.conf <<-SYSCTL
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_notsent_lowat = 16384
SYSCTL
        sysctl -p >/dev/null 2>&1
    fi
    log_ok "BBR 已啟用"

    # 3. 記憶體與 Swap 優化
    if [ "$(free -m | grep Swap | awk '{print $2}')" -eq 0 ]; then
        log_warn "檢測到無 Swap，正在建立 2GB Swap..."
        fallocate -l 2G /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        if ! grep -q "/swapfile" /etc/fstab; then
            echo "/swapfile none swap sw 0 0" >> /etc/fstab
        fi
    fi
    log_ok "Swap 已就緒"

    # 調整記憶體參數
    if ! grep -q "vm.swappiness" /etc/sysctl.conf; then
        echo "vm.swappiness = 10" >> /etc/sysctl.conf
        echo "vm.vfs_cache_pressure = 50" >> /etc/sysctl.conf
        sysctl -p >/dev/null 2>&1
    fi

    # 4. ZRAM 壓縮記憶體（小記憶體 VPS 加速）
    TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$TOTAL_MEM" -le 2048 ] && ! lsmod 2>/dev/null | grep -q zram; then
        log_warn "小記憶體 VPS (${TOTAL_MEM}MB)，啟用 ZRAM 壓縮..."
        if modprobe zram 2>/dev/null; then
            ZRAM_SIZE=$(( TOTAL_MEM / 2 ))
            echo ${ZRAM_SIZE}M > /sys/block/zram0/disksize 2>/dev/null || true
            mkswap /dev/zram0 2>/dev/null && swapon -p 5 /dev/zram0 2>/dev/null
            log_ok "ZRAM 已啟用 (${ZRAM_SIZE}MB)"
        else
            log_warn "ZRAM 模組不可用，跳過"
        fi
    fi

    # 5. GSO (Generic Segmentation Offload) 網卡優化
    DEFAULT_NIC=$(ip route show | grep default | awk '{print $5}' | head -n1)
    if [ -n "$DEFAULT_NIC" ]; then
        log_warn "正在對網卡 $DEFAULT_NIC 開啟 GSO/GRO 優化..."
        ethtool -K "$DEFAULT_NIC" gso on gro on tso on >/dev/null 2>&1 || true
        log_ok "GSO/GRO 已啟用"
    fi

    # 6. Docker 安裝檢查
    if ! command -v docker &> /dev/null; then
        log_warn "正在安裝 Docker..."
        curl -fsSL https://get.docker.com | bash
        systemctl enable docker
        systemctl start docker
        log_ok "Docker 安裝完成"
    else
        log_ok "Docker 已安裝"
    fi
    log_warn "System optimization ran in best-effort mode; continuing deployment even if some tuning steps failed."
    set -e
}

# =================================================================
#  [模組] 安裝專屬快捷管理工具
# =================================================================
install_shortcut() {
    cat > /usr/bin/${SHORTCUT_CMD} <<EOF
#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

NAME="${CONTAINER_NAME}"
DIR="${HOST_CONFIG_DIR}"
IMG="${IMAGE_NAME}"

# 容器操作
docker_op() {
    ACTION=\$1
    case "\$ACTION" in
        start)   docker start \$NAME && echo -e "\${GREEN}[✓] \$NAME 已啟動\${PLAIN}" ;;
        stop)    docker stop \$NAME && echo -e "\${GREEN}[✓] \$NAME 已停止\${PLAIN}" ;;
        restart) docker restart \$NAME && echo -e "\${GREEN}[✓] \$NAME 已重啟\${PLAIN}" ;;
        logs)    docker logs -f --tail 100 \$NAME ;;
    esac
}

# 更新容器
update_container() {
    echo -e "\${GREEN}正在更新 \$NAME ...\${PLAIN}"

    # 備份配置
    BACKUP_DIR="\${DIR}.bak.\$(date +%Y%m%d%H%M)"
    cp -r "\$DIR" "\$BACKUP_DIR"
    echo -e "\${CYAN}[Backup] 已備份配置至 \$BACKUP_DIR\${PLAIN}"

    docker pull \$IMG
    docker stop \$NAME >/dev/null 2>&1
    docker rm \$NAME >/dev/null 2>&1

    # 重新運行容器
    docker run -d --pull always --name \$NAME --restart always --network host --cap-add=SYS_TIME \\
        --ulimit nofile=65535:65535 --log-driver json-file --log-opt max-size=10m --log-opt max-file=3 \\
        --health-cmd "pgrep -f 'V2bX' || exit 1" --health-interval 30s --health-retries 3 \\
        --health-start-period 10s --health-timeout 5s \\
        -e GOGC=50 ${EXTRA_DOCKER_ARGS} -v \$DIR:/etc/V2bX -v /etc/localtime:/etc/localtime:ro \$IMG

    echo "\$(date +%Y%m%d%H%M%S)" > \${DIR}/.last_update
    echo -e "\${GREEN}[✓] \$NAME 更新完成！\${PLAIN}"
}

# 快捷參數模式 (支援 v2bx-siteA logs / restart / stop / update / health)
if [ -n "\${1:-}" ]; then
    case "\$1" in
        logs)    docker_op logs ;;
        restart) docker_op restart ;;
        stop)    docker_op stop ;;
        start)   docker_op start ;;
        update)  update_container ;;
        status)
            if docker inspect -f '{{.State.Running}}' \$NAME 2>/dev/null | grep -q true; then
                echo -e "\${GREEN}[✓] \$NAME 運行中\${PLAIN}"
            else
                echo -e "\${RED}[✗] \$NAME 未運行\${PLAIN}"
            fi
            ;;
        health)
            HC=\$(docker inspect -f '{{.State.Health.Status}}' \$NAME 2>/dev/null || echo "未配置")
            echo -e "\${CYAN}[Healthcheck] \$NAME 狀態: \$HC\${PLAIN}"
            echo -e "\${CYAN}--- 最近檢查記錄 ---\${PLAIN}"
            docker inspect -f '{{range .State.Health.Log}}{{.End}}: ExitCode={{.ExitCode}} Output={{.Output}}{{end}}' \$NAME 2>/dev/null || echo "無記錄"
            ;;
        *)       echo "用法: ${SHORTCUT_CMD} {logs|restart|stop|start|update|status|health}" ;;
    esac
    exit 0
fi

# 互動式菜單
clear
echo -e "\${GREEN}================================================\${PLAIN}"
echo -e "\${GREEN}   V2bX 管理面板 - 站點: ${SITE_TAG}\${PLAIN}"
echo -e "\${GREEN}================================================\${PLAIN}"
echo -e " 容器名稱: \${NAME}"
echo -e " 配置目錄: \${DIR}"
LAST_UP=\$(cat \${DIR}/.last_update 2>/dev/null || echo "未知")
echo -e " 最後更新: \${LAST_UP}"
echo -e "------------------------------------------------"
echo -e " 1. 查看日誌 (Logs)"
echo -e " 2. 重啟服務 (Restart)"
echo -e " 3. 停止服務 (Stop)"
echo -e " 4. 啟動服務 (Start)"
echo -e " 5. 更新鏡像 (Update)"
echo -e " 6. 查看狀態 (Status)"
echo -e " 7. 健康檢查 (Health)"
echo -e " 8. 卸載此節點 (Uninstall)"
echo -e " 0. 退出"
echo -e "------------------------------------------------"
read -p " 請輸入選項: " CHOICE

case "\$CHOICE" in
    1) docker_op logs ;;
    2) docker_op restart ;;
    3) docker_op stop ;;
    4) docker_op start ;;
    5) update_container ;;
    6)
       if docker inspect -f '{{.State.Running}}' \$NAME 2>/dev/null | grep -q true; then
           echo -e "\${GREEN}[✓] \$NAME 運行中\${PLAIN}"
           docker stats --no-stream \$NAME
       else
           echo -e "\${RED}[✗] \$NAME 未運行\${PLAIN}"
       fi
       ;;
    7)
       HC=\$(docker inspect -f '{{.State.Health.Status}}' \$NAME 2>/dev/null || echo "未配置")
       echo -e "\${CYAN}[Healthcheck] \$NAME 狀態: \$HC\${PLAIN}"
       echo -e "\${CYAN}--- 最近檢查記錄 ---\${PLAIN}"
       docker inspect -f '{{range .State.Health.Log}}{{.End}}: ExitCode={{.ExitCode}} Output={{.Output}}{{end}}' \$NAME 2>/dev/null || echo "無記錄"
       ;;
    8)
       read -p "確定刪除此站點節點嗎？(y/n): " C
       if [[ "\$C" == "y" ]]; then
           docker rm -f \$NAME
           rm -rf \$DIR
           rm /usr/bin/${SHORTCUT_CMD}
           echo -e "\${GREEN}已刪除\${PLAIN}"
       fi
       ;;
    0) exit 0 ;;
    *) echo "無效輸入" ;;
esac
EOF
    chmod +x /usr/bin/${SHORTCUT_CMD}
}

# =================================================================
#  [模組] 健康檢查與端口衝突偵測
# =================================================================
health_check() {
    log_info "正在執行健康檢查..."
    sleep 5

    # 1. 容器啟動狀態檢查
    if docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null | grep -q true; then
        log_ok "容器 ${CONTAINER_NAME} 運行正常"
    else
        log_fail "容器啟動失敗！"
        echo -e "排錯指令: ${CYAN}docker logs ${CONTAINER_NAME}${PLAIN}"
        return 1
    fi

    # 2. Docker Healthcheck 狀態
    HC_STATUS=$(docker inspect -f '{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "none")
    if [ "$HC_STATUS" == "healthy" ] || [ "$HC_STATUS" == "starting" ]; then
        log_ok "容器健康狀態: ${HC_STATUS}"
    elif [ "$HC_STATUS" == "none" ]; then
        log_warn "容器未配置 HEALTHCHECK"
    else
        log_fail "容器健康狀態異常: ${HC_STATUS}"
    fi

    # 3. 端口衝突偵測
    sleep 3
    log_info "正在偵測端口衝突..."
    CONFLICT=0
    # 從容器日誌中提取監聽端口
    PORTS=$(docker logs "$CONTAINER_NAME" 2>&1 | grep -oP '(?<=:)\d{2,5}(?=\s|$|")' | sort -u)
    for PORT in $PORTS; do
        # 排除常見非端口數字
        [ "$PORT" -lt 1024 ] 2>/dev/null && continue
        [ "$PORT" -gt 65535 ] 2>/dev/null && continue
        # 檢查是否有非本容器的程式佔用
        LISTENERS=$(ss -tlnp 2>/dev/null | grep ":${PORT} " | grep -v "$CONTAINER_NAME" || true)
        if [ -n "$LISTENERS" ]; then
            log_warn "[端口衝突] 端口 ${PORT} 可能被其他程式佔用！"
            echo -e "  $LISTENERS"
            CONFLICT=1
        fi
    done

    if [ "$CONFLICT" -eq 0 ]; then
        log_ok "未偵測到端口衝突"
    fi
}

# =================================================================
#  [模組] 部署 Autoheal 自動修復容器
# =================================================================
deploy_autoheal() {
    if docker ps -a --format '{{.Names}}' | grep -q '^autoheal$'; then
        if docker inspect -f '{{.State.Running}}' autoheal 2>/dev/null | grep -q true; then
            log_ok "Autoheal 容器已運行"
        else
            log_warn "Autoheal 容器存在但未運行，正在啟動..."
            docker start autoheal
            log_ok "Autoheal 已啟動"
        fi
        return
    fi

    log_info "部署 Autoheal 自動修復容器..."
    docker run -d \
        --name autoheal \
        --restart always \
        -e AUTOHEAL_CONTAINER_LABEL=all \
        -e AUTOHEAL_INTERVAL=30 \
        -e AUTOHEAL_START_PERIOD=60 \
        --log-driver json-file \
        --log-opt max-size=5m \
        --log-opt max-file=2 \
        -v /var/run/docker.sock:/var/run/docker.sock \
        willfarrell/autoheal:latest
    log_ok "Autoheal 已部署，將自動重啟 unhealthy 容器"
}

# =================================================================
#  [主流程] 部署 V2bX
# =================================================================
deploy_v2bx() {
    echo ""
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${CYAN}   V2bX 部署開始 - ${DISPLAY_NAME}${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e " 容器標識: ${CONTAINER_NAME}"
    echo -e " 配置路徑: ${HOST_CONFIG_DIR}"
    echo -e " 鏡像來源: ${IMAGE_NAME}"
    echo ""

    # 1. 執行系統優化 (包含 Docker 安裝)
    system_optimization

    # 1.5 同站點舊實例清理：同 ApiHost + NodeID 視為重建舊實例
    log_info "正在檢查同站點舊實例..."
    TARGET_API_HOST="$(normalize_api_host "${API_HOST:-}")"
    log_info "正在清理同 ApiHost 的舊實例，並準備重建"
    IFS=',' read -ra _CHECK_IDS <<< "$NODE_IDS"
    REPLACED_OLD=0
    CONFLICT_FOUND=0
    for _cid in "${_CHECK_IDS[@]}"; do
        _cid=$(echo "$_cid" | tr -d '[:space:]')
        [ -z "$_cid" ] && continue
        # 掃描所有正在運行的 v2bx 容器（排除即將被替換的同名容器）
        while IFS= read -r _running_name; do
            [ -z "$_running_name" ] && continue
            [ "$_running_name" = "$CONTAINER_NAME" ] && continue
            # 檢查該容器的配置中是否包含相同的 NodeID
            _cfg_dir="/etc/V2bX_$(echo "$_running_name" | sed 's/^v2bx-//')"
            if [ -f "${_cfg_dir}/config.json" ]; then
                if config_uses_node_id "${_cfg_dir}/config.json" "${_cid}"; then
                    _existing_api_host="$(normalize_api_host "$(get_config_api_host "${_cfg_dir}/config.json")")"
                    if [ -n "$_existing_api_host" ] && [ "$_existing_api_host" != "$TARGET_API_HOST" ]; then
                        log_info "[忽略] NODE_ID ${_cid} 已存在於 ${_running_name}，但 ApiHost 不同，視為不同站點"
                        continue
                    fi
                    log_warn "[重建] 同 ApiHost 的 NODE_ID ${_cid} 已存在於 ${_running_name}，將刪除舊實例後重建"
                    docker rm -f "$_running_name" >/dev/null 2>&1 || true
                    if [[ "$_cfg_dir" == /etc/V2bX_* ]]; then
                        rm -rf "$_cfg_dir"
                    fi
                    REPLACED_OLD=1
                    break
                fi
            fi
        done < <(docker ps --filter "name=v2bx-" --format "{{.Names}}" 2>/dev/null)
    done
    if [ "$REPLACED_OLD" -eq 1 ]; then
        log_ok "已清理同站點舊實例，繼續重建部署"
    fi
    if [ "$CONFLICT_FOUND" -eq 1 ]; then
        echo ""
        log_error "偵測到 NODE_ID 衝突！請先清理衝突容器再部署。"
        log_warn  "清理指令: docker rm -f <容器名>"
        log_warn  "查看所有實例: bash install.sh list"
        echo ""
        read -p "是否忽略衝突並繼續部署？(y/N): " _ignore
        if [[ "$_ignore" != "y" && "$_ignore" != "Y" ]]; then
            log_error "部署已取消。"
            exit 1
        fi
        log_warn "用戶選擇忽略衝突，繼續部署..."
    else
        log_ok "未偵測到 NODE_ID 衝突"
    fi

    # 2. 備份舊配置 (如果存在)
    if [ -d "$HOST_CONFIG_DIR" ]; then
        BACKUP_DIR="${HOST_CONFIG_DIR}.bak.$(date +%Y%m%d%H%M)"
        cp -r "$HOST_CONFIG_DIR" "$BACKUP_DIR"
        log_ok "已備份舊配置至 $BACKUP_DIR"
    fi

    # 3. 生成 Config (強制使用 sing 核心)
    mkdir -p ${HOST_CONFIG_DIR}
    echo "{}" > ${HOST_CONFIG_DIR}/sing_origin.json

    NODES_JSON=""
    IFS=',' read -ra ID_ARRAY <<< "$NODE_IDS"
    COMMA=""
    for id in "${ID_ARRAY[@]}"; do
        clean_id=$(echo "$id" | tr -d '[:space:]')
        [ -z "$clean_id" ] && continue
        NODES_JSON="${NODES_JSON}${COMMA}
        {
            \"Name\": \"${SITE_TAG}_${INSTALL_TYPE}_${clean_id}\",
            \"Core\": \"sing\", \"CoreName\": \"sing1\",
            \"ApiHost\": \"${API_HOST%/}\", \"ApiKey\": \"${API_KEY}\",
            \"NodeID\": ${clean_id}, \"NodeType\": \"${TARGET_NODE_TYPE}\",
            \"Timeout\": 30, \"ListenIP\": \"0.0.0.0\", \"SendIP\": \"0.0.0.0\",
            \"DeviceOnlineMinTraffic\": 100, \"EnableProxyProtocol\": true,
            \"EnableTFO\": true,
            \"MultiplexConfig\": { \"Enable\": true, \"Padding\": true }
        }"
        COMMA=","
    done

    cat > ${HOST_CONFIG_DIR}/config.json <<EOF
{
  "Log": { "Level": "error", "Output": "" },
  "Cores": [
    {
      "Type": "sing", "Name": "sing1",
      "Log": { "Level": "error", "Timestamp": true },
      "NTP": { "Enable": true, "Server": "pool.ntp.org", "ServerPort": 123 },
      "OriginalPath": "/etc/V2bX/sing_origin.json"
    }
  ],
  "Nodes": [ ${NODES_JSON} ]
}
EOF

    # 4. 容器部署
    log_info "拉取鏡像: ${IMAGE_NAME} ..."
    docker pull $IMAGE_NAME

    # 清理舊的同名容器
    docker stop $CONTAINER_NAME >/dev/null 2>&1 || true
    docker rm $CONTAINER_NAME >/dev/null 2>&1 || true

    docker run -d \
        --pull always \
        --name $CONTAINER_NAME \
        --restart always \
        --network host \
        --cap-add=SYS_TIME \
        --ulimit nofile=65535:65535 \
        --log-driver json-file \
        --log-opt max-size=10m \
        --log-opt max-file=3 \
        --health-cmd "pgrep -f 'V2bX' || exit 1" \
        --health-interval 30s \
        --health-retries 3 \
        --health-start-period 10s \
        --health-timeout 5s \
        -e GOGC=50 \
        $EXTRA_DOCKER_ARGS \
        -v ${HOST_CONFIG_DIR}:/etc/V2bX \
        -v /etc/localtime:/etc/localtime:ro \
        $IMAGE_NAME

    # 5. 記錄安裝時間
    echo "$(date +%Y%m%d%H%M%S)" > ${HOST_CONFIG_DIR}/.last_update

    # 6. 安裝快捷管理指令
    install_shortcut

    # 7. 部署 Autoheal 自動修復
    deploy_autoheal

    # 8. 健康檢查 & 端口衝突偵測
    health_check

    # 9. 完成
    echo ""
    echo -e "${GREEN}================================================${PLAIN}"
    echo -e "${GREEN}   ✅ 部署成功！${PLAIN}"
    echo -e "${GREEN}================================================${PLAIN}"
    echo -e " 專屬管理指令: ${CYAN}${SHORTCUT_CMD}${PLAIN}"
    echo -e " 快捷用法:"
    echo -e "   ${YELLOW}${SHORTCUT_CMD} logs${PLAIN}     查看日誌"
    echo -e "   ${YELLOW}${SHORTCUT_CMD} restart${PLAIN}  重啟服務"
    echo -e "   ${YELLOW}${SHORTCUT_CMD} status${PLAIN}   查看狀態"
    echo -e "   ${YELLOW}${SHORTCUT_CMD} health${PLAIN}   健康檢查"
    echo -e "   ${YELLOW}${SHORTCUT_CMD} update${PLAIN}   更新鏡像"
    echo -e "   ${YELLOW}${SHORTCUT_CMD}${PLAIN}          開啟互動面板"
    echo -e "${GREEN}================================================${PLAIN}"
    echo ""
    echo -e "最近日誌："
    docker logs --tail 10 ${CONTAINER_NAME}
}

deploy_v2bx
