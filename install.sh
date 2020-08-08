#!/usr/bin/env bash
#Install Latest Stable KubeOperator Release

red=31
green=32
yellow=33
blue=34

function colorMsg()
{
  echo -e "\033[$1m $2 \033[0m"
}

function log() {
   message="[KubeOperator Log]: $1 "
   echo -e "${message}" 2>&1 | tee -a ${CURRENT_DIR}/install.log
}

echo
cat << EOF
██╗  ██╗██╗   ██╗██████╗ ███████╗ ██████╗ ██████╗ ███████╗██████╗  █████╗ ████████╗ ██████╗ ██████╗
██║ ██╔╝██║   ██║██╔══██╗██╔════╝██╔═══██╗██╔══██╗██╔════╝██╔══██╗██╔══██╗╚══██╔══╝██╔═══██╗██╔══██╗
█████╔╝ ██║   ██║██████╔╝█████╗  ██║   ██║██████╔╝█████╗  ██████╔╝███████║   ██║   ██║   ██║██████╔╝
██╔═██╗ ██║   ██║██╔══██╗██╔══╝  ██║   ██║██╔═══╝ ██╔══╝  ██╔══██╗██╔══██║   ██║   ██║   ██║██╔══██╗
██║  ██╗╚██████╔╝██████╔╝███████╗╚██████╔╝██║     ███████╗██║  ██║██║  ██║   ██║   ╚██████╔╝██║  ██║
╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝ ╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝
EOF

colorMsg $yellow "\n\n开始安装 KubeOperator，版本 - ${KO_VERSION}"

if [ ! $CURRENT_DIR ];then
  CURRENT_DIR=$(cd "$(dirname "$0")";pwd)
fi

# 配置 kubeoperator
function ko_config() {
  if read -t 120 -p "设置KubeOperator安装目录,默认/opt: " KO_BASE;then
  if [ "$KO_BASE" != "" ];then
    echo "你选择的安装路径为 $KO_BASE"
  else
    KO_BASE=/opt
    echo "你选择的安装路径为 $KO_BASE"
  fi
  else
    KO_BASE=/opt
    echo "(设置超时，使用默认安装路径 /opt)"
  fi
}



# 解压离线文件
function unarchive() {
  colorMsg $yellow "开始解压离线包 ..."
  if [ -d ${CURRENT_DIR}/docker ];then
  # 离线安装
      cp -rp ${CURRENT_DIR}/kubeoperator $KO_BASE
      cp -rp ${CURRENT_DIR}//koctl $KO_BASE/kubeoperator
      tar zxvf ${CURRENT_DIR}/nexus-data.tar.gz -C $KO_BASE/kubeoperator/data/ > /dev/null 2>&1
  else
  # 在线安装
      cp -rp ${CURRENT_DIR}/kubeoperator-release-${KO_VERSION}/installer/kubeoperator $KO_BASE
      cp -rp ${CURRENT_DIR}/kubeoperator-release-${KO_VERSION}/installer/koctl $KO_BASE/kubeoperator
      log "解压 ansible "
      tar zxvf ${CURRENT_DIR}/kubeoperator-release-${KO_VERSION}/ansible.tar.gz -C ${CURRENT_DIR}/kubeoperator-release-${KO_VERSION} > /dev/null 2>&1
      cp -rp ${CURRENT_DIR}/kubeoperator-release-${KO_VERSION}/ansible $KO_BASE/kubeoperator/data/kobe/project/ko
      log "解压 nexus "
      tar zxvf ${CURRENT_DIR}/kubeoperator-release-${KO_VERSION}/nexus-data.origin.tar.gz -C $KO_BASE/kubeoperator/data/ > /dev/null 2>&1
  fi
  sed -i -e "s#KO_BASE=.*#KO_BASE=${KO_BASE}#g" $KO_BASE/kubeoperator/koctl
  cp -rp  $KO_BASE/kubeoperator/koctl /usr/local/bin/
}


# 配置docker，私有 docker 仓库授信
function config_docker() {
  if ! grep registry.kubeoperator.io /etc/hosts;then
    echo "127.0.0.1 registry.kubeoperator.io" >> /etc/hosts
  fi
  if [ -r /etc/docker/daemon.json ];then
    mv -n /etc/docker/daemon.json /etc/docker/daemon.json.bak
  else
    mkdir -p /etc/docker
  fi
cat << EOF > /etc/docker/daemon.json
{
  "registry-mirrors": ["http://registry.kubeoperator.io:8082","http://registry.kubeoperator.io:8083"],
  "insecure-registries": ["registry.kubeoperator.io:8082","registry.kubeoperator.io:8083"],
  "max-concurrent-downloads": 10,
  "log-driver": "json-file",
  "log-level": "warn",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
  }
EOF
  systemctl daemon-reload
  systemctl restart docker
}

# 检测 docker 是否存在
function install_docker() {
  if which docker docker-compose ;then
    echo "docker 已经安装，跳过安装步骤"
    config_docker
    if systemctl status docker|grep running;then
      echo "docker 运行正常"
    else
      echo "docker 已经安装，跳过安装步骤"
    fi
  else
   if [[ -d docker ]]; then
      log "... 离线安装 docker"
      cp docker/bin/* /usr/bin/
      cp docker/service/docker.service /etc/systemd/system/
      chmod +x /usr/bin/docker*
      chmod 754 /etc/systemd/system/docker.service
      log "... 配置 docker"
      config_docker
      log "... 启动 docker"
      systemctl start docker 2>&1 | tee -a ${CURRENT_DIR}/install.log
      systemctl enable docker 2>&1 | tee -a ${CURRENT_DIR}/install.log
   else
      log "... 在线安装 docker"
      curl -fsSL https://get.docker.com -o get-docker.sh 2>&1 | tee -a ${CURRENT_DIR}/install.log
      sudo sh get-docker.sh 2>&1 | tee -a ${CURRENT_DIR}/install.log
      log "... 在线安装 docker-compose"
      sudo curl -L "https://github.com/docker/compose/releases/download/1.26.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
      sudo chmod +x /usr/local/bin/docker-compose
      log "... 配置 docker"
      config_docker
      log "... 启动 docker"
      service docker start 2>&1 | tee -a ${CURRENT_DIR}/install.log
      systemctl enable docker 2>&1 | tee -a ${CURRENT_DIR}/install.log
   fi
  fi
}



# 加载镜像
function load_image() {
  export COMPOSE_HTTP_TIMEOUT=180
  if [[ -d ${CURRENT_DIR}/kubeoperator-release-${KO_VERSION}/images ]]; then
     log "加载镜像"
     cd  $CURRENT_DIR
     for i in $(ls images); do
        docker load -i images/$i 2>&1 | tee -a ${CURRENT_DIR}/install.log
     done
  else
     log "拉取镜像"
     cd $KO_BASE/kubeoperator/ && docker-compose pull 2>&1 | tee -a ${CURRENT_DIR}/install.log
     cd -
  fi
}


# 启动 kubeoperator
function ko_start() {
  log "开始启动 KubeOperator"
  cd  $KO_BASE/kubeoperator/ && docker-compose up -d 2>&1 | tee -a ${CURRENT_DIR}/install.log
  sleep 15s
  while [ $(docker ps -a|grep kubeoperator |egrep "Exit|unhealthy"|wc -l) -gt 0 ]
  do
    for service in $(docker ps -a|grep kubeoperator |egrep "Exit|unhealthy"|awk '{print $1}')
    do
    docker start ${service} 2>&1 | tee -a ${CURRENT_DIR}/install.log
    sleep 15s
    done
    break
  done
  if [ $(docker ps -a|grep kubeoperator |egrep "Exit|unhealthy"|wc -l) -eq 0 ];then
    echo -e "======================= KubeOperator 安装完成 =======================\n" 2>&1 | tee -a ${CURRENT_DIR}/install.log
    echo -e "请通过以下方式访问:\n URL: \033[33m http://\$LOCAL_IP:80\033[0m \n 用户名: \033[${green}m admin \033[0m \n 初始密码: \033[${green}m kubeoperator@admin123 \033[0m" 2>&1 | tee -a ${CURRENT_DIR}/install.log
  else
    echo -e "KubeOperator 服务异常，请检查服务是否启动" 2>&1 | tee -a ${CURRENT_DIR}/install.log
    cd  $KO_BASE/kubeoperator/ && docker-compose status
  fi
}

function main() {
  ko_config
  unarchive
  install_docker
  load_image
  ko_start
}

main