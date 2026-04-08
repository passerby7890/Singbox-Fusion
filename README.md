# V2bX 全能部署腳本 (Google SRE Standard)

> 一鍵完成 V2bX 節點的 Docker 自動化部署，支援**多站點隔離共存**、系統級網路優化與智能管理。
> 鏡像源：`tinyserve/v2bx:latest`

---

## ✨ 核心特性

### 🛡️ 多實例隔離 (Multi-Instance)

透過 `SITE_TAG` 變數實現同一台伺服器上運行多個不同面板、不同協議的節點，**容器、配置目錄、管理指令**完全隔離，互不干擾。

### 🚀 系統自動優化

- **BBR + FQ** 擁塞控制自動啟用
- **GSO / GRO / TSO** 網卡卸載自動開啟
- 核心參數（`tcp_notsent_lowat`）自動校準

### 💾 智能記憶體管理

- **Smart Swap**：自動偵測，無 Swap 時自動建立 2GB Swap（防重複建立）
- **ZRAM 壓縮**：小記憶體 VPS（≤ 2GB）自動啟用 ZRAM，顯著提升高併發性能
- **記憶體參數調優**：`swappiness=10` + `vfs_cache_pressure=50`

### 🔧 容錯與自癒

- 自動檢測並修復 **dpkg/apt 鎖死**問題
- Docker 未安裝時自動呼叫官方腳本安裝
- 容器設定 `--restart always` 自動守護
- **Log Rotation**：日誌限制 `10MB × 3` 份，防止撐爆硬碟
- `ulimit nofile=65535` 防高併發檔案描述符耗盡
- **SITE_TAG 格式驗證**，防止非法字元導致異常
- **AnyTLS 憑證模式標準化**：內建 `http / file / self` 三種規律安裝模式

### 🔍 智能健康檢查

- 部署完成後自動驗證容器啟動狀態
- **端口衝突偵測**：自動掃描並警告被佔用的端口
- 更新時自動備份舊配置

### ⚡ 快捷管理

- 自動生成專屬管理指令 `v2bx-{SITE_TAG}`
- 支援**互動式選單**與**命令列參數**兩種操作模式
- 內建 `list` 模式一覽所有已安裝實例

---

## 📥 安裝與使用

### 第一步：下載腳本

```bash
wget -N https://raw.githubusercontent.com/passerby7890/Singbox-Fusion/main/install.sh
chmod +x install.sh
```

### 第二步：配置並安裝

> [!IMPORTANT]
> 安裝前請先 `export` 以下必要變數，腳本會自動檢查格式與完整性。
> `INSTALL_TYPE=anytls` 時，還需要依憑證模式補齊 `ANYTLS_CERT_*` 參數。

---

#### 場景 1️⃣：安裝 Shadowsocks / SS2022 節點

```bash
export SITE_TAG="siteA"           # [關鍵] 實例標籤，只允許字母/數字/底線
export API_HOST="https://a.com"   # 面板地址
export API_KEY="通訊密鑰A"        # 面板 Key
export NODE_IDS="1,2"             # 節點 ID（多個用逗號分隔）
export INSTALL_TYPE="ss"          # 安裝類型

bash install.sh
```

#### 場景 2️⃣：安裝 V2Ray (VMess/VLESS) 節點

```bash
export SITE_TAG="siteB"
export API_HOST="https://b.com"
export API_KEY="通訊密鑰B"
export NODE_IDS="3,4"
export INSTALL_TYPE="v2ray"
export V2RAY_PROTOCOL="vmess"     # (可選) vmess 或 vless，預設 vmess

bash install.sh
```

#### 場景 3️⃣：安裝 Trojan 節點

```bash
export SITE_TAG="siteC"
export API_HOST="https://c.com"
export API_KEY="通訊密鑰C"
export NODE_IDS="5"
export INSTALL_TYPE="trojan"

bash install.sh
```

#### 場景 4️⃣：安裝 Hysteria2 節點

```bash
export SITE_TAG="siteD"
export API_HOST="https://d.com"
export API_KEY="通訊密鑰D"
export NODE_IDS="6"
export INSTALL_TYPE="hy2"         # 自動加入 --cap-add=NET_ADMIN

bash install.sh
```

#### 場景 5️⃣：安裝 AnyTLS 節點（推薦：HTTP 自動簽證）

```bash
export SITE_TAG="siteE"
export API_HOST="https://panel.example.com"
export API_KEY="通訊密鑰E"
export NODE_IDS="7"
export INSTALL_TYPE="anytls"

# AnyTLS 憑證模式：http / file / self
export ANYTLS_CERT_MODE="http"
export ANYTLS_CERT_DOMAIN="edge.example.com"
export ANYTLS_CERT_EMAIL="admin@example.com"

bash install.sh
```

#### 場景 6️⃣：AnyTLS 使用既有證書（file 模式）

```bash
export SITE_TAG="siteF"
export API_HOST="https://panel.example.com"
export API_KEY="通訊密鑰F"
export NODE_IDS="8"
export INSTALL_TYPE="anytls"

export ANYTLS_CERT_MODE="file"
export ANYTLS_CERT_DOMAIN="edge.example.com"
export ANYTLS_CERT_FILE="/root/certs/edge.example.com/fullchain.cer"
export ANYTLS_KEY_FILE="/root/certs/edge.example.com/cert.key"

bash install.sh
```

#### 場景 7️⃣：AnyTLS 測試環境自簽證書（self 模式）

```bash
export SITE_TAG="siteG"
export API_HOST="https://panel.example.com"
export API_KEY="通訊密鑰G"
export NODE_IDS="9"
export INSTALL_TYPE="anytls"

export ANYTLS_CERT_MODE="self"
export ANYTLS_CERT_DOMAIN="lab.example.com"

bash install.sh
```

---

## 📋 環境變數說明

| 變數名稱 | 必填 | 說明 | 示例值 |
|---|---|---|---|
| `SITE_TAG` | ✅ | 實例標籤（多開核心），只允許字母/數字/底線 | `siteA`, `hk_node` |
| `API_HOST` | ✅ | 面板網址 | `https://v2board.com` |
| `API_KEY` | ✅ | 通訊密鑰 | `mysecretkey` |
| `NODE_IDS` | ✅ | 節點 ID，多個用逗號分隔 | `1` 或 `1,2,3` |
| `INSTALL_TYPE` | ✅ | 安裝類型 | `ss`, `v2ray`, `trojan`, `hy2`, `anytls` |
| `V2RAY_PROTOCOL` | ❌ | V2Ray 協議（僅 `INSTALL_TYPE=v2ray` 時有效） | `vmess`（預設）, `vless` |
| `IMAGE_NAME` | ❌ | 自訂 Docker 鏡像 | `tinyserve/v2bx:latest`（預設） |

### Shadowsocks / SS2022 規律安裝原則

1. `INSTALL_TYPE=ss` 只負責落地安裝 V2bX 與 sing-core，不會替你決定 cipher；實際 cipher 由面板節點設定決定。
2. 若面板使用 `SS2022`，建議優先選擇：
   - `2022-blake3-aes-128-gcm`
   - `2022-blake3-aes-256-gcm`
   - `2022-blake3-chacha20-poly1305`
3. `SS/SS2022` 本身不是 TLS 協議，不需要像 `AnyTLS` 那樣額外配置證書。
4. 若你的需求是「更像 HTTPS / 更接近 TLS 外觀」，應考慮 `AnyTLS`，而不是期待 `SS` 自帶站點外觀。
5. `SS2022` 與傳統 AEAD Shadowsocks 的密碼規則不同，面板與客戶端要保持一致。

### Shadowsocks 面板對齊清單

| 面板欄位 | 建議值 / 規律 |
|---|---|
| `節點地址(host)` | 指向落地機域名或 IP |
| `連接端口(port)` | 與服務端實際監聽端口一致 |
| `服務端口(server_port)` | 建議與 `port` 相同 |
| `cipher` | 與客戶端完全一致 |
| `server_key` | 僅 `SS2022` 需要，且必須正確 |
| `允許不安全` | 對 `SS` 無意義，通常不涉及 |

### Shadowsocks 客戶端對齊清單

1. 客戶端 `cipher` 必須與面板節點相同。
2. 傳統 AEAD Shadowsocks 使用使用者密碼；`SS2022` 需要正確的 `server_key + user password/uuid` 組合。
3. 若是 `SS2022`，不要把舊版 Shadowsocks 客戶端配置直接套用。
4. 若你需要的是穩定與簡單，`SS2022` 是最適合的主力節點。
5. 若你需要更強偽裝，再考慮 `AnyTLS`。

### Shadowsocks 安裝前檢查

```bash
# 確認面板節點已建立，且 node_id 正確
echo "$NODE_IDS"

# 確認落地機目標端口沒有被其他服務占用
ss -tulpn | grep -E ':443 |:8443 |:2053 ' || true
```

### Shadowsocks 安裝後驗證

```bash
# 看容器狀態
v2bx-siteA status

# 看健康檢查
v2bx-siteA health

# 看最新日誌
v2bx-siteA logs
```

若是 `SS2022`，最可靠的驗證方式仍然是用實際客戶端連線測試，而不是直接用瀏覽器打端口。

### Shadowsocks Failure Signatures

| 日誌 / 現象 | 常見原因 | 建議處理 |
|---|---|---|
| 客戶端握手失敗 | `cipher` 不一致 | 面板與客戶端改成完全相同 |
| `SS2022` 無法連線 | `server_key` 或 UUID / password 規則不一致 | 重新核對面板與客戶端參數 |
| 端口通但代理不可用 | 節點 ID 對錯機器、落地端口被別的服務占用 | 重新對照 `host / NodeID / port` |
| 想要 HTTPS 外觀但實測不像 | 協議本身是 `SS`，不是 TLS | 改走 `AnyTLS` |

### Shadowsocks Quick Notes (EN)

- `INSTALL_TYPE=ss` deploys a Shadowsocks-capable V2bX node.
- Cipher selection is controlled by the panel, not by the installer.
- `SS2022` needs the correct server-side keying model.
- Shadowsocks is not a website and not a TLS site by itself.
- If you need stronger TLS-style camouflage, use `AnyTLS`.

### AnyTLS 專用變數

| 變數名稱 | 必填 | 說明 | 示例值 |
|---|---|---|---|
| `ANYTLS_CERT_MODE` | `INSTALL_TYPE=anytls` 時必填 | 憑證模式 | `http`, `file`, `self` |
| `ANYTLS_CERT_DOMAIN` | `http/self` 必填 | 憑證網域，必須解析到落地機 | `edge.example.com` |
| `ANYTLS_CERT_EMAIL` | `http` 必填 | Let's Encrypt 註冊 Email | `admin@example.com` |
| `ANYTLS_CERT_FILE` | `file` 必填 | 既有完整憑證鏈檔案（來源路徑） | `/root/certs/fullchain.cer` |
| `ANYTLS_KEY_FILE` | `file` 必填 | 既有私鑰檔案（來源路徑） | `/root/certs/cert.key` |

### AnyTLS 規律安裝原則

1. `AnyTLS` 一定要有 TLS 憑證，不能沿用「沒有 CertConfig 也能跑」的心態。
2. `http` 模式最省事，但要求落地機的 `80` 端口可用，且 `ANYTLS_CERT_DOMAIN` 已經解析到該落地機。
3. `file` 模式適合已有正式證書的環境；腳本會把來源證書複製到實例配置目錄，容器內統一使用 `/etc/V2bX/fullchain.cer` 與 `/etc/V2bX/cert.key`。
4. `self` 模式只適合測試。面板或客戶端必須開啟「允許不安全 / skip-cert-verify」。
5. 面板的 `host / server_name(sni)` 應與 `ANYTLS_CERT_DOMAIN` 保持一致，避免握手成功但驗證失敗。
6. 若面板的 `連接端口(port)` 與 `服務端口(server_port)` 不同，請自行補一層 TCP 轉發或 Stream 代理，例如 `443 -> 7443`。

### AnyTLS 非對稱端口場景

若你的面板設定如下：

- `port = 443`
- `server_port = 7443`

代表：

- 客戶端會連 `443`
- V2bX 實際在落地機上監聽 `7443`

這種情況下，除了 `install.sh` 部署的 V2bX 之外，你還需要在作業系統層補一層 TCP 轉發，例如：

```bash
apt-get update -y
apt-get install -y socat

cat > /etc/systemd/system/anytls-443-forward.service <<'EOF'
[Unit]
Description=AnyTLS TCP forward 443 to 7443
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/socat TCP-LISTEN:443,reuseaddr,fork TCP:127.0.0.1:7443
Restart=always
RestartSec=2
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now anytls-443-forward.service
```

驗證：

```bash
ss -tulpn | grep -E ':443 |:7443 '
openssl s_client -connect 127.0.0.1:7443 -servername edge.example.com -brief </dev/null
```

### AnyTLS 面板對齊清單

當你在 V2Board / XBoard / 其他相容面板建立 `AnyTLS` 節點時，請至少確認以下欄位一致：

| 面板欄位 | 建議值 / 規律 |
|---|---|
| `節點地址(host)` | 對外入口域名，例如 `edge.example.com` |
| `連接端口(port)` | 客戶端連線端口，通常為 `443` |
| `服務端口(server_port)` | 落地機實際監聽端口，通常也為 `443` |
| `SNI / server_name` | 與憑證網域完全一致，例如 `edge.example.com` |
| `允許不安全` | 正式環境建議 `否`；只有 `self` 模式才建議開 `是` |
| `padding_scheme` | 可留空，除非你明確知道客戶端也支援同一組 padding 策略 |

### AnyTLS 客戶端對齊清單

1. 客戶端的 `server` 必須指向與面板相同的入口域名。
2. 客戶端的 `password` 就是使用者 UUID。
3. `server_name / sni` 應與證書網域一致。
4. 正式證書請保持 `skip-cert-verify=false`。
5. 自簽證書測試時，請顯式開啟 `skip-cert-verify=true`。
6. `AnyTLS` 是代理入口，不是網站，直接用瀏覽器打開看到空回應或連線關閉不代表節點異常。

### AnyTLS 安裝前檢查

```bash
# 1. 域名必須先解析到落地機
dig +short edge.example.com

# 2. http 模式下，80 端口必須可用
ss -tulpn | grep ':80 '

# 3. file 模式下，證書檔必須存在
ls -l /root/certs/fullchain.cer /root/certs/cert.key
```

### AnyTLS 安裝後驗證

```bash
# 看容器是否正常
v2bx-siteE status

# 看最新日誌
v2bx-siteE logs

# 驗證 TLS 是否已經起來
openssl s_client -connect 127.0.0.1:443 -servername edge.example.com -brief </dev/null
```

若最後一條 `openssl s_client` 還不能完成握手，先不要測客戶端。

### AnyTLS Failure Signatures

| 日誌 / 現象 | 常見原因 | 建議處理 |
|---|---|---|
| `unknown user password: fallback disabled` | 最常見是服務端 TLS 沒起來，TLS ClientHello 被當成密碼解析 | 先檢查 `CertConfig`、證書檔、`openssl s_client` |
| `TLS handshake: EOF` | 探測器、掃描器，或客戶端握手被中途關閉 | 若偶發可忽略，若持續出現在自己測試時再查證書/SNI |
| `curl https://域名` 空回應 | 你打到的是代理入口，不是 Web 站 | 這通常不算故障 |
| `http` 模式簽證失敗 | 80 端口被占用，或 DNS 尚未生效 | 釋放 80 / 等待 DNS / 改 `file` 模式 |

### AnyTLS Quick Notes (EN)

- `AnyTLS` requires a valid TLS certificate on the server side.
- For production, use `ANYTLS_CERT_MODE=http` or `ANYTLS_CERT_MODE=file`.
- Keep panel `host`, `server_name`, and certificate domain identical.
- User password is the user UUID.
- If you see `unknown user password: fallback disabled`, check TLS first, not UUID first.
- A direct browser request to the AnyTLS endpoint is not a valid health check.

---

## 🛠️ 管理與維護

### 🔍 查詢已安裝實例 (List Mode)

```bash
bash install.sh list
```

輸出範例：

```
================================================
   V2bX 已安裝實例一覽
================================================
SITE_TAG        容器名稱                  運行狀態     管理指令
---------------------------------------------------------------
siteA           v2bx-ss-siteA            Up 2 hours   v2bx-siteA
siteB           v2bx-v2ray-siteB         Up 1 hour    v2bx-siteB
```

### ⚡ 快捷管理指令

安裝完成後自動生成快捷指令 **`v2bx-{SITE_TAG}`**，支援兩種使用方式：

#### 方式一：命令列參數（適合腳本自動化）

| 指令 | 說明 |
|---|---|
| `v2bx-siteA logs` | 查看即時日誌（`Ctrl+C` 退出） |
| `v2bx-siteA restart` | 重啟服務 |
| `v2bx-siteA stop` | 停止服務 |
| `v2bx-siteA start` | 啟動服務 |
| `v2bx-siteA update` | 拉取最新鏡像並重建（自動備份配置） |
| `v2bx-siteA status` | 查看容器運行狀態 |

#### 方式二：互動式選單（直接執行不帶參數）

```bash
v2bx-siteA
```

```
================================================
   V2bX 管理面板 - 站點: siteA
================================================
 容器名稱: v2bx-ss-siteA
 配置目錄: /etc/V2bX_ss-siteA
 最後更新: 20260223205200
------------------------------------------------
 1. 查看日誌 (Logs)
 2. 重啟服務 (Restart)
 3. 停止服務 (Stop)
 4. 啟動服務 (Start)
 5. 更新鏡像 (Update)
 6. 查看狀態 (Status)
 7. 卸載此節點 (Uninstall)
 0. 退出
------------------------------------------------
```

---

## 🏗️ 部署架構

```
伺服器
├── /etc/V2bX_ss-siteA/          ← Site A 配置（Shadowsocks）
│   ├── config.json
│   ├── sing_origin.json
│   └── .last_update             ← 最後更新時間戳
├── /etc/V2bX_v2ray-siteB/       ← Site B 配置（V2Ray）
├── /etc/V2bX_trojan-siteC/      ← Site C 配置（Trojan）
├── /etc/V2bX_hy2-siteD/         ← Site D 配置（Hysteria2）
├── /usr/bin/v2bx-siteA          ← Site A 管理指令
├── /usr/bin/v2bx-siteB          ← Site B 管理指令
├── /usr/bin/v2bx-siteC          ← Site C 管理指令
└── /usr/bin/v2bx-siteD          ← Site D 管理指令
```

每個實例的 Docker 容器以 `v2bx-{type}-{tag}` 命名，配置目錄以 `/etc/V2bX_{type}-{tag}` 隔離，實現完全獨立運行。

### AnyTLS 生成後的標準結構

```text
/etc/V2bX_anytls-siteE/
├── config.json
├── sing_origin.json
├── fullchain.cer   # http/file/self 最終都落在這裡
├── cert.key
└── .last_update
```

---

## ⚠️ 常見問題 (FAQ)

**Q: 腳本會自動安裝 Docker 嗎？**
A: 是的。若偵測到未安裝，會自動呼叫官方安裝腳本，並嘗試修復 dpkg/apt 鎖死問題。

**Q: 支援哪些作業系統？**
A: 支援基於 `apt`（Debian/Ubuntu）和 `yum`（CentOS/RHEL）的 Linux 發行版。

**Q: 如何在同一台機器上部署多個節點？**
A: 為每次安裝設定不同的 `SITE_TAG`，容器、配置、管理指令皆會自動隔離。

**Q: 部署後提示端口衝突怎麼辦？**
A: 表示面板分配的端口已被其他程式佔用。去面板修改節點端口，然後 `v2bx-{TAG} restart`。

**Q: Shadowsocks / SS2022 需要證書嗎？**
A: 不需要。`SS/SS2022` 不是 TLS 協議，本身不依賴證書。若你要的是 TLS 外觀或 HTTPS 風格偽裝，請改用 `AnyTLS`。

**Q: SS2022 和舊版 Shadowsocks 最大差異是什麼？**
A: 最大差異是密鑰模型與客戶端相容性。`SS2022` 必須確保面板、落地機、客戶端三邊都使用相同的 `2022-blake3-*` cipher，並正確處理 `server_key` 與使用者密碼/UUID。

**Q: AnyTLS 為什麼日誌一直出現 `unknown user password: fallback disabled`？**
A: 最常見原因不是 UUID 錯，而是服務端沒有正確啟用 TLS。請先確認：
1. `INSTALL_TYPE=anytls`
2. `config.json` 內已有 `CertConfig`
3. `fullchain.cer` / `cert.key` 已生成
4. `openssl s_client -connect 127.0.0.1:443 -servername <你的域名>` 能完成握手

**Q: AnyTLS 的 `http` 模式為什麼安裝前會檢查 80 端口？**
A: 因為 V2bX 的 HTTP-01 簽證需要在本機直接監聽 `80`。若 80 已被 Nginx / Baota / Caddy 佔用，請改用 `file` 或 `self` 模式，或先釋放 80。

**Q: AnyTLS 節點可以直接拿瀏覽器打開嗎？**
A: 不建議。它是代理入口，不是網站。現在腳本只保證 TLS 憑證與 AnyTLS 握手正確，不保證回 HTTP 內容。

**Q: 更新時配置會遺失嗎？**
A: 不會。更新前會自動備份至 `/etc/V2bX_{type}-{tag}.bak.{timestamp}`。

**Q: ZRAM 什麼時候會啟用？**
A: 當伺服器記憶體 ≤ 2GB 且系統支援 ZRAM 模組時自動啟用，無需手動設定。

**Q: 日誌太大會不會撐爆硬碟？**
A: 不會。已配置 Log Rotation（`max-size=10m`、`max-file=3`），最大佔用約 30MB。

---

## 🔐 上傳前檢查

### 不應該上傳到 GitHub 的內容

以下資料屬於運維私密資料或運行時產物，請不要提交：

- 真實面板網址、真實 `API_KEY`、真實節點 ID 對照表
- 真實使用者 UUID 匯出、訂閱內容、測試客戶端配置
- 真實 TLS 憑證與私鑰：`fullchain.cer`、`cert.key`、`*.pem`、`*.key`
- `/etc/V2bX_*` 下的實際 `config.json`、`sing_origin.json`、`.last_update`
- ACME / Lego 帳號資料，例如 `user/user-*.json`
- 排障時產生的備份、壓縮包、日誌、Docker inspect 輸出
- 真實域名、真實 IP、真實 root 密碼、資料庫帳密

### 建議只上傳的內容

- `install.sh`
- `README.md`
- `.gitignore`
- 純樣板或純示例檔，不包含任何真實密鑰與真實主機資訊

### 這份倉庫目前狀態

目前我替你整理好的可上傳目錄只有：

- `install.sh`
- `README.md`
- `.gitignore`

而且我已經檢查過，這份目錄內沒有你這次排障時使用的真實：

- 面板 API Key
- SSH 密碼
- MySQL 密碼
- 落地機 IP
- 真實節點域名

### 上傳前最後再檢查一次

```bash
rg -n -i "token|apikey|api_key|password|passwd|secret|fullchain|cert.key|private key|public key" .
```

若有命中，先確認是不是示例字串；若是真實值，先替換成 `example.com`、`your-api-key`、`admin@example.com` 這類佔位字串。

---

## 📄 授權

MIT License
