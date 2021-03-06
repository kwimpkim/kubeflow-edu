#!/bin/bash

echo '
=================================
기존 minikube 제거
---------------------------------
'
minikube stop 
minikube delete

echo '
=================================
설치버전 및 환경변수 설정
---------------------------------
'
# https://www.kubeflow.org/docs/started/k8s/overview/

# https://github.com/kubernetes/kubernetes/releases
#K8S_VER=v1.15.2
K8S_VER=v1.16.15
#K8S_VER=v1.17.17
#K8S_VER=v1.18.16
#K8S_VER=v1.19.7
#K8S_VER=v1.20.4

# https://github.com/kubeflow/manifests/tree/master/distributions/kfdef
#KF_VER=v1.0.2
#KF_VER=v1.1.0
KF_VER=v1.2.0
CONFIG_URI=https://github.com/kubeflow/manifests/raw/master/distributions/kfdef/kfctl_k8s_istio.${KF_VER}.yaml

# https://github.com/kubeflow/kfctl/releases
#KFCTL_DOWNLOSF=https://github.com/kubeflow/kfctl/releases/download/v1.0.2/kfctl_v1.0.2-0-ga476281_linux.tar.gz
#KFCTL_DOWNLOSF=https://github.com/kubeflow/kfctl/releases/download/v1.1.0/kfctl_v1.1.0-0-g9a3621e_linux.tar.gz
KFCTL_DOWNLOSF=https://github.com/kubeflow/kfctl/releases/download/v1.2.0/kfctl_v1.2.0-0-gbc038f9_linux.tar.gz

INC_S=s-inc-u8xe42b1
INC_E=e-inc-u8xe42b1

echo '
=================================
alias 및 자동완성 추가
---------------------------------
'
apt install -y bash-completion

sed -i "/${INC_S}/,/${INC_E}/d" /etc/bash.bashrc
cat << EOBRC >> /etc/bash.bashrc

#=============<${INC_S}>=============
set -o vi

alias d='docker'
alias k='kubectl'
alias kw='watch "kubectl get pod -A"'
alias kww='watch "kubectl get pod -A | grep -v Running"'

source /etc/bash_completion
source <(kubectl completion bash)
complete -F __start_kubectl k
#-------------<${INC_E}>-------------
EOBRC

echo '
=================================
도커 설치
---------------------------------
'
apt-get update
apt-get install -y docker.io

cat << EO_DOCKER_DAEMON > /etc/docker/daemon.json
{
        "insecure-registries": ["kubeflow-registry.default.svc.cluster.local:30000"]
}
EO_DOCKER_DAEMON

systemctl start docker
systemctl enable docker

echo '
=================================
kubectl 설치
---------------------------------
'
mkdir -p ~/kubeflow
cd ~/kubeflow

curl -LO https://storage.googleapis.com/kubernetes-release/release/$K8S_VER/bin/linux/amd64/kubectl
chmod +x ./kubectl
mv ./kubectl /usr/local/bin/kubectl

# https://github.com/derailed/k9s/releases
wget https://github.com/derailed/k9s/releases/download/v0.24.2/k9s_Linux_x86_64.tar.gz
tar xzf k9s_Linux_x86_64.tar.gz
mv -f k9s /usr/bin

echo '
=================================
minikube 설치
---------------------------------
'
apt install conntrack
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
install minikube-linux-amd64 /usr/local/bin/minikube

echo '
=================================
minikube 기동
---------------------------------
'
sysctl fs.protected_regular=0

minikube start \
  --driver=none \
  --extra-config=apiserver.service-account-issuer=api \
  --extra-config=apiserver.service-account-signing-key-file=/var/lib/minikube/certs/sa.key \
  --extra-config=apiserver.service-account-api-audiences=api \
  --kubernetes-version $K8S_VER
  # https://github.com/kubeflow/kubeflow/issues/5447#issuecomment-773400533
  #--extra-config=apiserver.service-account-signing-key-file=/var/lib/minikube/certs/apiserver.key 

[[ $? -eq 0 ]] || exit
  
echo '
=================================
방화벽 해제
---------------------------------
'
ufw disable  
  
echo '
=================================
K8s 대쉬보드 설치
---------------------------------
'
minikube addons enable dashboard 
minikube addons enable metrics-server

echo '
=================================
Kubeflow 설치
---------------------------------
'
export KF_HOME=~/kubeflow
export KF_NAME=sds-kubeflow

rm -rf ${KF_HOME}

mkdir -p $KF_HOME
cd $KF_HOME

rm -f ./kfctl*
# https://github.com/kubeflow/kfctl/releases
wget $KFCTL_DOWNLOSF
#tar -xvf kfctl_*.tar.gz	
tar -xvf $(basename $KFCTL_DOWNLOSF)

export PATH=$PATH:$KF_HOME
export KF_DIR=${KF_HOME}/${KF_NAME}
mkdir -p ${KF_DIR}
cd ${KF_DIR}
kfctl apply -V -f ${CONFIG_URI}

[[ $? -eq 0 ]] || exit

echo '
=================================
Private Registry 설치
---------------------------------
'
cat << EO_REGISTRY_DEPLOY | kubectl apply -f -
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  annotations:
    deployment.kubernetes.io/revision: "1"
  generation: 1
  labels:
    run: kubeflow-registry
  name: kubeflow-registry
  namespace: default
spec:
  progressDeadlineSeconds: 600
  replicas: 1
  revisionHistoryLimit: 10
  selector:
    matchLabels:
      run: kubeflow-registry
  strategy:
    rollingUpdate:
      maxSurge: 25%
      maxUnavailable: 25%
    type: RollingUpdate
  template:
    metadata:
      creationTimestamp: null
      labels:
        run: kubeflow-registry
    spec:
      containers:
      - image: registry:2
        imagePullPolicy: IfNotPresent
        name: kubeflow-registry
        resources: {}
        terminationMessagePath: /dev/termination-log
        terminationMessagePolicy: File
      dnsPolicy: ClusterFirst
      restartPolicy: Always
      schedulerName: default-scheduler
      securityContext: {}
      terminationGracePeriodSeconds: 30
EO_REGISTRY_DEPLOY

cat << EO_REGISTRY_SVC | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  labels:
    run: kubeflow-registry
  name: kubeflow-registry
  namespace: default
spec:
  ports:
  - name: registry
    port: 30000
    protocol: TCP
    targetPort: 5000
    nodePort: 30000
  selector:
    run: kubeflow-registry
  sessionAffinity: None
  type: NodePort
status:
  loadBalancer: {}
EO_REGISTRY_SVC

REGISTRY_URL="kubeflow-registry.default.svc.cluster.local"
grep "127.0.0.1.*${REGISTRY_URL}" /etc/hosts > /dev/null
[[ $? -eq 0 ]] || cat << EO_HOSTS >> /etc/hosts
127.0.0.1	${REGISTRY_URL}
EO_HOSTS

echo '
=================================
완료
---------------------------------
'

read -p "Press Enter..."
k9s -n kubeflow
