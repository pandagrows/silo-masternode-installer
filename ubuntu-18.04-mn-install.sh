#!/bin/bash

TMP_FOLDER=$(mktemp -d)
CONFIG_FILE="seed2need.conf"
SEED2NEED_DAEMON="/usr/local/bin/seed2needd"
SEED2NEED_CLI="/usr/local/bin/seed2need-cli"
SEED2NEED_REPO="https://github.com/Nebula-Coin/nebula-project-coin.git"
SEED2NEED_PARAMS="https://github.com/pandagrows/seed2need-silo-coin/releases/download/v.5.5.0/util.zip"
SEED2NEED_LATEST_RELEASE="https://github.com/pandagrows/seed2need-silo-coin/releases/download/v5.5.0/seed2need-5.5.0-ubuntu18-daemon.zip"
COIN_BOOTSTRAP='https://bootstrap.seed2need.me/boot_strap.tar.gz'
COIN_ZIP=$(echo $SEED2NEED_LATEST_RELEASE | awk -F'/' '{print $NF}')
COIN_CHAIN=$(echo $COIN_BOOTSTRAP | awk -F'/' '{print $NF}')
COIN_NAME='Seed2Need'
CONFIGFOLDER='.seed2need'
COIN_BOOTSTRAP_NAME='boot_strap.tar.gz'

DEFAULT_SEED2NEED_PORT=4820
DEFAULT_SEED2NEED_RPC_PORT=4821
DEFAULT_SEED2NEED_USER="seed2need"
SEED2NEED_USER="seed2need"
NODE_IP=NotCheckedYet
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

function download_bootstrap() {
  echo -e "${GREEN}Downloading and Installing $COIN_NAME BootStrap${NC}"
  mkdir -p /opt/chaintmp/
  cd /opt/chaintmp >/dev/null 2>&1
  rm -rf boot_strap* >/dev/null 2>&1
  wget $COIN_BOOTSTRAP >/dev/null 2>&1
  cd /home/$SEED2NEED_USER/$CONFIGFOLDER
  rm -rf sporks zerocoin blocks database chainstate peers.dat
  cd /opt/chaintmp >/dev/null 2>&1
  tar -zxf $COIN_BOOTSTRAP_NAME
  cp -Rv cache/* /home/$SEED2NEED_USER/$CONFIGFOLDER/ >/dev/null 2>&1
  chown -Rv $SEED2NEED_USER /home/$SEED2NEED_USER/$CONFIGFOLDER >/dev/null 2>&1
  cd ~ >/dev/null 2>&1
  rm -rf /opt/chaintmp >/dev/null 2>&1
}

function install_params() {
  echo -e "${GREEN}Downloading and Installing $COIN_NAME Params Files${NC}"
  mkdir -p /opt/tmp/
  cd /opt/tmp
  rm -rf util* >/dev/null 2>&1
  wget $SEED2NEED_PARAMS >/dev/null 2>&1
  unzip util.zip >/dev/null 2>&1
  chmod -Rv 777 /opt/tmp/util/fetch-params.sh >/dev/null 2>&1
  runuser -l $SEED2NEED_USER -c '/opt/tmp/util/./fetch-params.sh' >/dev/null 2>&1
}

purgeOldInstallation() {
    echo -e "${GREEN}Searching and removing old $COIN_NAME Daemon{NC}"
    #kill wallet daemon
	systemctl stop $SEED2NEED_USER.service
	
	#Clean block chain for Bootstrap Update
    cd $CONFIGFOLDER >/dev/null 2>&1
    rm -rf *.pid *.lock database sporks chainstate zerocoin blocks >/dev/null 2>&1
	
    #remove binaries and Seed2Need utilities
    cd /usr/local/bin && sudo rm seed2need-cli seed2need-tx seed2needd > /dev/null 2>&1 && cd
    echo -e "${GREEN}* Done${NC}";
}


function compile_error() {
if [ "$?" -gt "0" ];
 then
  echo -e "${RED}Failed to compile $@. Please investigate.${NC}"
  exit 1
fi
}


function checks() {
if [[ $(lsb_release -d) != *18.04* ]]; then
  echo -e "${RED}You are not running Ubuntu 18.04. Installation is cancelled.${NC}"
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}$0 must be run as root.${NC}"
   exit 1
fi

if [ -n "$(pidof $SEED2NEED_DAEMON)" ] || [ -e "$SEED2NEED_DAEMON" ] ; then
  echo -e "${GREEN}\c"
  echo -e "Seed2Need is already installed. Exiting..."
  echo -e "{NC}"
  exit 1
fi
}

function prepare_system() {

echo -e "Prepare the system to install Seed2Need master node."
apt-get update >/dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get update > /dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -y -qq upgrade >/dev/null 2>&1
apt install -y software-properties-common >/dev/null 2>&1
echo -e "${GREEN}Adding Pivx PPA repository"
apt-add-repository -y ppa:pivx/pivx >/dev/null 2>&1
echo -e "Installing required packages, it may take some time to finish.${NC}"
apt-get update >/dev/null 2>&1
apt-get upgrade >/dev/null 2>&1
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" git make build-essential libtool bsdmainutils autotools-dev autoconf pkg-config automake python3 libssl-dev libgmp-dev libevent-dev libboost-all-dev libdb4.8-dev libdb4.8++-dev ufw fail2ban pwgen curl unzip >/dev/null 2>&1
NODE_IP=$(curl -s4 icanhazip.com)
clear
if [ "$?" -gt "0" ];
  then
    echo -e "${RED}Not all required packages were installed properly. Try to install them manually by running the following commands:${NC}\n"
    echo "apt-get update"
    echo "apt-get -y upgrade"
    echo "apt -y install software-properties-common"
    echo "apt-add-repository -y ppa:pivx/pivx"
    echo "apt-get update"
    echo "apt install -y git make build-essential libtool bsdmainutils autotools-dev autoconf pkg-config automake python3 libssl-dev libgmp-dev libevent-dev libboost-all-dev libdb4.8-dev libdb4.8++-dev unzip"
    exit 1
fi
clear

}

function ask_yes_or_no() {
  read -p "$1 ([Y]es or [N]o | ENTER): "
    case $(echo $REPLY | tr '[A-Z]' '[a-z]') in
        y|yes) echo "yes" ;;
        *)     echo "no" ;;
    esac
}

function compile_seed2need() {
echo -e "Checking if swap space is needed."
PHYMEM=$(free -g|awk '/^Mem:/{print $2}')
SWAP=$(free -g|awk '/^Swap:/{print $2}')
if [ "$PHYMEM" -lt "4" ] && [ -n "$SWAP" ]
  then
    echo -e "${GREEN}Server is running with less than 4G of RAM without SWAP, creating 8G swap file.${NC}"
    SWAPFILE=/swapfile
    dd if=/dev/zero of=$SWAPFILE bs=1024 count=8388608
    chown root:root $SWAPFILE
    chmod 600 $SWAPFILE
    mkswap $SWAPFILE
    swapon $SWAPFILE
    echo "${SWAPFILE} none swap sw 0 0" >> /etc/fstab
else
  echo -e "${GREEN}Server running with at least 4G of RAM, no swap needed.${NC}"
fi
clear
  echo -e "Clone git repo and compile it. This may take some time."
  cd $TMP_FOLDER
  git clone $SEED2NEED_REPO seed2need
  cd seed2need
  ./autogen.sh
  ./configure
  make
  strip src/seed2needd src/seed2need-cli src/seed2need-tx
  make install
  cd ~
  rm -rf $TMP_FOLDER
  clear
}

function copy_seed2need_binaries(){
   cd /root
  wget $SEED2NEED_LATEST_RELEASE
  unzip seed2need-5.5.0-ubuntu18-daemon.zip
  cp seed2need-cli seed2needd seed2need-tx /usr/local/bin >/dev/null
  chmod 755 /usr/local/bin/seed2need* >/dev/null
  clear
}

function install_seed2need(){
  echo -e "Installing Seed2Need files."
  echo -e "${GREEN}You have the choice between source code compilation (slower and requries 4G of RAM or VPS that allows swap to be added), or to use precompiled binaries instead (faster).${NC}"
  if [[ "no" == $(ask_yes_or_no "Do you want to perform source code compilation?") || \
        "no" == $(ask_yes_or_no "Are you **really** sure you want compile the source code, it will take a while?") ]]
  then
    copy_seed2need_binaries
    clear
  else
    compile_seed2need
    clear
  fi
}

function enable_firewall() {
  echo -e "Installing fail2ban and setting up firewall to allow ingress on port ${GREEN}$SEED2NEED_PORT${NC}"
  ufw allow $SEED2NEED_PORT/tcp comment "Seed2Need MN port" >/dev/null
  ufw allow ssh comment "SSH" >/dev/null 2>&1
  ufw limit ssh/tcp >/dev/null 2>&1
  ufw default allow outgoing >/dev/null 2>&1
  echo "y" | ufw enable >/dev/null 2>&1
  systemctl enable fail2ban >/dev/null 2>&1
  systemctl start fail2ban >/dev/null 2>&1
}

function systemd_seed2need() {
  cat << EOF > /etc/systemd/system/$SEED2NEED_USER.service
[Unit]
Description=Seed2Need service
After=network.target
[Service]
ExecStart=$SEED2NEED_DAEMON -conf=$SEED2NEED_FOLDER/$CONFIG_FILE -datadir=$SEED2NEED_FOLDER
ExecStop=$SEED2NEED_CLI -conf=$SEED2NEED_FOLDER/$CONFIG_FILE -datadir=$SEED2NEED_FOLDER stop
Restart=always
User=$SEED2NEED_USER
Group=$SEED2NEED_USER

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  sleep 3
  systemctl start $SEED2NEED_USER.service
  systemctl enable $SEED2NEED_USER.service
}

function ask_port() {
read -p "SEED2NEED Port: " -i $DEFAULT_SEED2NEED_PORT -e SEED2NEED_PORT
: ${SEED2NEED_PORT:=$DEFAULT_SEED2NEED_PORT}
}

function ask_user() {
  echo -e "${GREEN}The script will now setup Seed2Need user and configuration directory. Press ENTER to accept defaults values.${NC}"
  read -p "Seed2Need user: " -i $DEFAULT_SEED2NEED_USER -e SEED2NEED_USER
  : ${SEED2NEED_USER:=$DEFAULT_SEED2NEED_USER}

  if [ -z "$(getent passwd $SEED2NEED_USER)" ]; then
    USERPASS=$(pwgen -s 12 1)
    useradd -m $SEED2NEED_USER
    echo "$SEED2NEED_USER:$USERPASS" | chpasswd

    SEED2NEED_HOME=$(sudo -H -u $SEED2NEED_USER bash -c 'echo $HOME')
    DEFAULT_SEED2NEED_FOLDER="$SEED2NEED_HOME/.seed2need"
    read -p "Configuration folder: " -i $DEFAULT_SEED2NEED_FOLDER -e SEED2NEED_FOLDER
    : ${SEED2NEED_FOLDER:=$DEFAULT_SEED2NEED_FOLDER}
    mkdir -p $SEED2NEED_FOLDER
    chown -R $SEED2NEED_USER: $SEED2NEED_FOLDER >/dev/null
  else
    clear
    echo -e "${RED}User exits. Please enter another username: ${NC}"
    ask_user
  fi
}

function check_port() {
  declare -a PORTS
  PORTS=($(netstat -tnlp | awk '/LISTEN/ {print $4}' | awk -F":" '{print $NF}' | sort | uniq | tr '\r\n'  ' '))
  ask_port

  while [[ ${PORTS[@]} =~ $SEED2NEED_PORT ]] || [[ ${PORTS[@]} =~ $[SEED2NEED_PORT+1] ]]; do
    clear
    echo -e "${RED}Port in use, please choose another port:${NF}"
    ask_port
  done
}

function create_config() {
  RPCUSER=$(pwgen -s 8 1)
  RPCPASSWORD=$(pwgen -s 15 1)
  cat << EOF > $SEED2NEED_FOLDER/$CONFIG_FILE
rpcuser=$RPCUSER
rpcpassword=$RPCPASSWORD
rpcallowip=127.0.0.1
rpcport=$DEFAULT_SEED2NEED_RPC_PORT
listen=1
server=1
daemon=1
port=$SEED2NEED_PORT
#External Seed2Need IPV4
addnode=135.181.254.116:4820
addnode=135.181.193.63:4820
addnode=65.21.242.191:4820
addnode=65.109.182.123:4820
addnode=199.127.140.224:4820
addnode=199.127.140.225:4820
addnode=[2a01:04f9:c012:4fb0::0001]:4820
addnode=[2a01:04f9:c011:24ca::0001]:4820

#External WhiteListing IPV4
whitelist=135.181.254.116
whitelist=135.181.193.63
whitelist=65.21.242.191
whitelist=65.109.182.123
whitelist=23.245.6.173
whitelist=199.127.140.224
whitelist=199.127.140.225

#External WhiteListing IPV6
whitelist=[2a01:04f9:c012:4fb0::0001]
whitelist=[2a01:04f9:c011:24ca::0001]
EOF
}

function create_key() {
  echo -e "Enter your ${RED}Masternode Private Key${NC}. Leave it blank to generate a new ${RED}Masternode Private Key${NC} for you:"
  read -e SEED2NEED_KEY
  if [[ -z "$SEED2NEED_KEY" ]]; then
  su $SEED2NEED_USER -c "$SEED2NEED_DAEMON -conf=$SEED2NEED_FOLDER/$CONFIG_FILE -datadir=$SEED2NEED_FOLDER -daemon"
  sleep 15
  if [ -z "$(ps axo user:15,cmd:100 | egrep ^$SEED2NEED_USER | grep $SEED2NEED_DAEMON)" ]; then
   echo -e "${RED}Seed2Needd server couldn't start. Check /var/log/syslog for errors.{$NC}"
   exit 1
  fi
  SEED2NEED_KEY=$(su $SEED2NEED_USER -c "$SEED2NEED_CLI -conf=$SEED2NEED_FOLDER/$CONFIG_FILE -datadir=$SEED2NEED_FOLDER createmasternodekey")
  su $SEED2NEED_USER -c "$SEED2NEED_CLI -conf=$SEED2NEED_FOLDER/$CONFIG_FILE -datadir=$SEED2NEED_FOLDER stop"
fi
}

function update_config() {
  sed -i 's/daemon=1/daemon=0/' $SEED2NEED_FOLDER/$CONFIG_FILE
  cat << EOF >> $SEED2NEED_FOLDER/$CONFIG_FILE
maxconnections=256
masternode=1
masternodeaddr=$NODE_IP:$SEED2NEED_PORT
masternodeprivkey=$SEED2NEED_KEY
EOF
  chown -R $SEED2NEED_USER: $SEED2NEED_FOLDER >/dev/null
}

function important_information() {
 echo
 echo -e "================================================================================================================================"
 echo -e "Seed2Need Masternode is up and running as user ${GREEN}$SEED2NEED_USER${NC} and it is listening on port ${GREEN}$SEED2NEED_PORT${NC}."
 echo -e "${GREEN}$SEED2NEED_USER${NC} password is ${RED}$USERPASS${NC}"
 echo -e "Configuration file is: ${RED}$SEED2NEED_FOLDER/$CONFIG_FILE${NC}"
 echo -e "Start: ${RED}systemctl start $SEED2NEED_USER.service${NC}"
 echo -e "Stop: ${RED}systemctl stop $SEED2NEED_USER.service${NC}"
 echo -e "VPS_IP:PORT ${RED}$NODE_IP:$SEED2NEED_PORT${NC}"
 echo -e "MASTERNODE PRIVATEKEY is: ${RED}$SEED2NEED_KEY${NC}"
 echo -e "Please check Seed2Need is running with the following command: ${GREEN}systemctl status $SEED2NEED_USER.service${NC}"
 echo -e "================================================================================================================================"
}

function setup_node() {
  ask_user
  install_params
  download_bootstrap
  check_port
  create_config
  create_key
  update_config
  enable_firewall
  systemd_seed2need
  important_information
}


##### Main #####
clear
purgeOldInstallation
checks
prepare_system
install_seed2need
setup_node
