#!/bin/bash


# 检查必需的环境变量
REQUIRED_VARS=(
  "PROJECT_NAME"
  "NODE_IP"
  "POD_CIDR"
  "SERVICE_CIDR"
  "CLUSTER_NAME"
  "CLUSTER_DOMAIN"
  "CF_TUNNEL_TOKEN"
  "CF_DNS_API_TOKEN"
  "DOMAIN"
)

MISSING_VARS=()

for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var}" ]; then
    MISSING_VARS+=("$var")
  fi
done

if [ ${#MISSING_VARS[@]} -ne 0 ]; then
  echo "錯誤: 以下環境變數未設置:"
  for var in "${MISSING_VARS[@]}"; do
    echo "  - $var"
  done
  echo ""
  echo "請先設置環境變數，例如："
  echo "  source test.env"
  exit 1
fi

echo "======================================"
echo "環境變數檢查通過"
echo "======================================"
echo "集群名稱: $CLUSTER_NAME"
echo "節點 IP: $NODE_IP"
echo "域名: $DOMAIN"
echo "======================================"
echo ""
read -p "輸入 y 繼續部署，其他任意鍵退出: " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
  echo "已取消部署"
  exit 0
fi
echo ""


install_k3s_and_merge_config() {
  # 檢查遠程是否已安裝 k3s
  if ssh root@$NODE_IP "command -v k3s &> /dev/null"; then
    echo "k3s 已經安裝在遠程服務器上，跳過安裝步驟..."
  else
    echo "開始在遠程服務器上安裝 k3s..."
    # 安裝 k3s
    ssh root@$NODE_IP "curl -sfL https://get.k3s.io | \
      INSTALL_K3S_EXEC='server \
        --cluster-cidr=$POD_CIDR \
        --service-cidr=$SERVICE_CIDR \
        --node-ip=$NODE_IP \
        --cluster-domain=$CLUSTER_DOMAIN \
        --disable-network-policy \
        --disable=traefik \
        --kubelet-arg=container-log-max-size=5Mi \
        --kubelet-arg=container-log-max-files=2' sh -"
    echo "k3s 安裝完成"
  fi

  export TMP_FILE=/tmp/$CLUSTER_NAME-k3s.yaml
  scp root@$NODE_IP:/etc/rancher/k3s/k3s.yaml $TMP_FILE

  # 在本地修改配置文件的名稱和地址
  sed -i '' "s/127.0.0.1/$NODE_IP/g" $TMP_FILE
  sed -i '' "s/default/$CLUSTER_NAME/g" $TMP_FILE

  KUBECONFIG=~/.kube/config:$TMP_FILE kubectl config view --flatten > /tmp/merged-config.yaml
  mv /tmp/merged-config.yaml ~/.kube/config
  rm $TMP_FILE

  # 查看所有 context
  kubectl config get-contexts

}

install_k3s_and_merge_config


ssh root@$NODE_IP "echo net.ipv4.ip_forward=1 | sudo tee /etc/sysctl.d/99-sysctl.conf >/dev/null && sudo sysctl -p /etc/sysctl.d/99-sysctl.conf"

ssh root@$NODE_IP "cat <<EOF | sudo tee /etc/nftables.conf >/dev/null
table ip nat {
  chain postrouting {
    type nat hook postrouting priority 100;
    ip daddr { $POD_CIDR, $SERVICE_CIDR } iif != lo counter masquerade
  }
}
EOF
sudo nft -f /etc/nftables.conf && sudo systemctl enable --now nftables 2>/dev/null || true"


# 切換到對應的 context
kubectl config use-context $CLUSTER_NAME

# cf tunnel
envsubst < cloudflared.yaml | kubectl apply -f -

# treafik
helm repo add traefik https://traefik.github.io/charts
helm repo update
envsubst < traefik-values.yaml | helm upgrade --install traefik traefik/traefik \
  --namespace kube-system \
  --values -

# dashboard
kubectl create secret generic kubernetes-dashboard-csrf \
  --from-literal=csrf-token=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32) \
  --dry-run=client -o yaml | kubectl apply -f -
envsubst < dashboard.yaml | kubectl apply -f -

# # monitor
# helm dependency update infrastructure/monitor
# helm upgrade --install monitor infrastructure/monitor \
#   -n monitor --create-namespace \
#   --set "grafana.ingress.hosts[0]=monitor.$DOMAIN" \
#   --set "alloy.namespaces[0]=$PROJECT_NAME"

# # nats nui
# helm repo add nats-nui https://nats-nui.github.io/k8s/helm/charts
# envsubst < nats-nui-values.yaml | helm upgrade --install -n monitor nats-nui nats-nui/nui -f -

# # etcd-workbench
# helm upgrade --install etcd-workbench infrastructure/etcd-workbench \
#   -n monitor --create-namespace \
#   --set "ingress.host=etcd.$DOMAIN"

# argocd
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

ARGOCD_ADMIN_PASSWORD=$(htpasswd -nbBC 10 "" "aa456123" | tr -d ':\n' | sed 's/$2y/$2a/')

envsubst < argocd-values.yaml | helm upgrade --install argocd argo/argo-cd \
  -n argocd --create-namespace \
  --set configs.secret.argocdServerAdminPassword="$ARGOCD_ADMIN_PASSWORD" \
  -f -
