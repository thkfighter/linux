#!/bin/bash

rand(){
    min=$1
    max=$(($2-$min+1))
    num=$(cat /dev/urandom | head -n 10 | cksum | awk -F ' ' '{print $1}')
    echo $(($num%$max+$min))  
}

wireguard_install(){
    version=$(cat /etc/os-release | awk -F '[".]' '$1=="VERSION="{print $2}')
    echo $version
    if [ $version == 20 ]; then
        sudo apt-get update -y
        sudo apt-get install -y wireguard curl resolvconf 
        # /usr/bin/wg-quick: line 32: resolvconf: command not found
    #else
     #   sudo apt-get update -y
      #  sudo apt-get install -y software-properties-common
    fi
    # sudo add-apt-repository -y ppa:wireguard/wireguard
    # sudo apt-get update -y
    # sudo apt-get install -y wireguard curl


    mkdir /etc/wireguard
    cd /etc/wireguard
    wg genkey | sudo tee sprivatekey | sudo wg pubkey > spublickey
    wg genkey | sudo tee cprivatekey | sudo wg pubkey > cpublickey
    s1=$(cat sprivatekey)
    s2=$(cat spublickey)
    c1=$(cat cprivatekey)
    c2=$(cat cpublickey)
    serverip=$(curl ipv4.icanhazip.com)
    port=51820
    eth=$(ls /sys/class/net | awk '/^e/{print}')
	# eth=$(ip -o -4 route show to default | awk '{print $5}') # second way to the interface name

	sudo cat > /etc/wireguard/wg0.conf <<-EOF
	[Interface]
	PrivateKey = $s1
	Address = 10.0.0.1/24 
	ListenPort = $port
	PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o $eth -j MASQUERADE
	PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o $eth -j MASQUERADE
	DNS = 8.8.8.8
	MTU = 1420

	[Peer]
	PublicKey = $c2
	AllowedIPs = 10.0.0.2/24
	EOF


	sudo cat > /etc/wireguard/client.conf <<-EOF
	[Interface]
	PrivateKey = $c1
	Address = 10.0.0.2/24 
	DNS = 8.8.8.8
	MTU = 1420

	[Peer]
	PublicKey = $s2
	Endpoint = $serverip:$port
	AllowedIPs = 0.0.0.0/0, ::/0
	PersistentKeepalive = 25
	EOF

    sudo apt-get install -y qrencode

	sudo cat > /etc/init.d/wgstart <<-EOF
	#! /bin/bash
	### BEGIN INIT INFO
	# Provides:		wgstart
	# Required-Start:	$remote_fs $syslog
	# Required-Stop:    $remote_fs $syslog
	# Default-Start:	2 3 4 5
	# Default-Stop:		0 1 6
	# Short-Description:	wgstart
	### END INIT INFO
	sudo wg-quick up wg0
	EOF

    sudo chmod +x /etc/init.d/wgstart
    # cd /etc/init.d
    if [ $version == 14 ]
    then
        sudo update-rc.d /etc/init.d/wgstart defaults 90
    else
        sudo update-rc.d /etc/init.d/wgstart defaults
    fi
    
    sudo wg-quick up wg0
    
    sudo echo net.ipv4.ip_forward = 1 >> /etc/sysctl.conf
    sudo sysctl -p
    sudo echo "1"> /proc/sys/net/ipv4/ip_forward
    sudo ufw allow 51820/udp

    content=$(cat /etc/wireguard/client.conf)
    echo -e "\033[43;42m电脑端请下载/etc/wireguard/client.conf，手机端可直接使用软件扫码\033[0m"
    echo "${content}" | qrencode -o - -t UTF8
}

wireguard_remove(){

    sudo wg-quick down wg0
    sudo apt-get remove -y wireguard
    sudo rm -rf /etc/wireguard

}

add_user(){
    echo -e "\033[37;41m给新用户起个名字，不能和已有用户重复\033[0m"
    read -p "请输入用户名：" newname
    cd /etc/wireguard/
    cp client.conf $newname.conf
    wg genkey | sudo tee temprikey | wg pubkey | sudo tee tempubkey
    ipnum=$(grep Allowed /etc/wireguard/wg0.conf | tail -1 | awk -F '[ ./]' '{print $6}')
    newnum=$((10#${ipnum}+1))
    sed -i 's%^PrivateKey.*$%'"PrivateKey = $(cat temprikey)"'%' $newname.conf
    sed -i 's%^Address.*$%'"Address = 10.0.0.$newnum\/24"'%' $newname.conf

	cat >> /etc/wireguard/wg0.conf <<-EOF
	[Peer]
	PublicKey = $(cat tempubkey)
	AllowedIPs = 10.0.0.$newnum/24
	EOF
    wg set wg0 peer $(cat tempubkey) allowed-ips 10.0.0.$newnum/24
    echo -e "\033[37;41m添加完成，文件：/etc/wireguard/$newname.conf\033[0m"
    sudo rm -f temprikey tempubkey
}

#开始菜单
start_menu(){
    clear
    echo -e "\033[43;42m ====================================\033[0m"
    echo -e "\033[43;42m 介绍：wireguard一键脚本              \033[0m"
    echo -e "\033[43;42m 系统：Ubuntu                        \033[0m"
    echo -e "\033[43;42m 作者：A                    \033[0m"
    echo -e "\033[43;42m ====================================\033[0m"
    echo
    echo -e "\033[0;33m 1. 安装wireguard\033[0m"
    echo -e "\033[0;33m 2. 查看客户端二维码\033[0m"
    echo -e "\033[0;31m 3. 删除wireguard\033[0m"
    echo -e "\033[0;33m 4. 增加用户\033[0m"
    echo -e " 0. 退出脚本"
    echo
    read -p "请输入数字:" num
    case "$num" in
    1)
    wireguard_install
    ;;
    2)
    content=$(cat /etc/wireguard/client.conf)
    echo "${content}" | qrencode -o - -t UTF8
    ;;
    3)
    wireguard_remove
    ;;
    4)
    add_user
    ;;
    0)
    exit 1
    ;;
    *)
    clear
    echo -e "请输入正确数字"
    sleep 2s
    start_menu
    ;;
    esac
}

start_menu
