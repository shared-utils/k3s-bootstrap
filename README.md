# K3s Bootstrap

一鍵部署 k3s 集群及常用組件的腳本。

## 使用方法

### 1. 配置環境變數

複製示例配置文件並修改：

```bash
cp example.env your-env.env
# 編輯 your-env.env，填入真實的配置信息
vim your-env.env
```

### 2. 加載環境變數

```bash
source your-env.env
```

### 3. 運行部署腳本

```bash
./deploy.sh
```

## 部署的組件

- **K3s**: 輕量級 Kubernetes 發行版
- **Traefik**: Ingress 控制器 + 自動 HTTPS (使用 Cloudflare DNS)
- **Cloudflare Tunnel**: 零信任網絡訪問
- **Kubernetes Dashboard**: 集群管理界面
- **Grafana + Loki + Alloy**: 日誌監控系統
- **NATS NUI**: NATS 管理界面
- **etcd-workbench**: etcd 管理工具

## 環境變數說明

| 變數名 | 說明 | 示例 |
|--------|------|------|
| `PROJECT_NAME` | 項目名稱 | `myproject` |
| `NODE_IP` | K3s 節點 IP | `192.168.1.100` |
| `POD_CIDR` | Pod 網絡 CIDR | `10.42.0.0/16` |
| `SERVICE_CIDR` | Service 網絡 CIDR | `10.43.0.0/16` |
| `CLUSTER_NAME` | 集群名稱 | `$PROJECT_NAME-$ENV` |
| `CLUSTER_DOMAIN` | 集群域名 | `$CLUSTER_NAME.k8s` |
| `CF_TUNNEL_TOKEN` | Cloudflare Tunnel Token | 從 Zero Trust 獲取 |
| `CF_DNS_API_TOKEN` | Cloudflare DNS API Token | 從 Profile 獲取 |
| `DOMAIN` | 主域名 | `example.com` |

## 注意事項

- 需要能夠 SSH 到遠程節點（root@$NODE_IP）
- 確保本地已安裝 `kubectl` 和 `helm`
- Cloudflare Token 需要提前創建好
