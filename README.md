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

---

#### 場景 1️⃣：安裝 Shadowsocks 節點

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

---

## 📋 環境變數說明

| 變數名稱 | 必填 | 說明 | 示例值 |
|---|---|---|---|
| `SITE_TAG` | ✅ | 實例標籤（多開核心），只允許字母/數字/底線 | `siteA`, `hk_node` |
| `API_HOST` | ✅ | 面板網址 | `https://v2board.com` |
| `API_KEY` | ✅ | 通訊密鑰 | `mysecretkey` |
| `NODE_IDS` | ✅ | 節點 ID，多個用逗號分隔 | `1` 或 `1,2,3` |
| `INSTALL_TYPE` | ✅ | 安裝類型 | `ss`, `v2ray`, `trojan`, `hy2` |
| `V2RAY_PROTOCOL` | ❌ | V2Ray 協議（僅 `INSTALL_TYPE=v2ray` 時有效） | `vmess`（預設）, `vless` |
| `IMAGE_NAME` | ❌ | 自訂 Docker 鏡像 | `tinyserve/v2bx:latest`（預設） |

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

**Q: 更新時配置會遺失嗎？**
A: 不會。更新前會自動備份至 `/etc/V2bX_{type}-{tag}.bak.{timestamp}`。

**Q: ZRAM 什麼時候會啟用？**
A: 當伺服器記憶體 ≤ 2GB 且系統支援 ZRAM 模組時自動啟用，無需手動設定。

**Q: 日誌太大會不會撐爆硬碟？**
A: 不會。已配置 Log Rotation（`max-size=10m`、`max-file=3`），最大佔用約 30MB。

---

## 📄 授權

MIT License
