#!/bin/bash

telnet_status()
{
    echo "b" | telnet -e "b" $1 $2 > /dev/null 2>&1
    if [ $? == 0 ]
    then
        return 0     
    else
        return 1
    fi
}

get_controller_info()
{
    controller_ip=''
    if [ "$ETCDCTL_PEERS" ]; then
        peers=`echo $ETCDCTL_PEERS | sed -e "s/,/ /g"`

        for i in $peers
        do
            read host port <<< $(echo $i | awk 'BEGIN {FS=":"; OFS =" "} {print $1,$2}')
            telnet_status $host $port
            if [ $? == 0 ]
            then
                values=`curl -L http://$host:$port/v2/keys/OPENSTACK/CONTROLLER/IPADDR 2> /dev/null`
	        controller_ip=`echo $values | awk -F ',' '{print $3}' | awk -F "\"" '{print $4}'`
                break
            fi
        done
    fi
}

wait_controller_info()
{
    controller_ip=''
    if [ "$ETCDCTL_PEERS" ]; then
        peers=`echo $ETCDCTL_PEERS | sed -e "s/,/ /g"`

        for i in $peers
        do
            read host port <<< $(echo $i | awk 'BEGIN {FS=":"; OFS =" "} {print $1,$2}')
            telnet_status $host $port
            if [ $? == 0 ]
            then
                values=`curl -L http://$host:$port/v2/keys/OPENSTACK/CONTROLLER/IPADDR?wait=true 2> /dev/null`
                if [ $? == 0 ]; then
	            controller_ip=`echo $values | awk -F ',' '{print $3}' | awk -F "\"" '{print $4}'`
                    break
                fi
            fi
        done
    fi
}

insert_controller_ip()
{
    while true; do
        get_controller_info
        if [ ! -z $controller_ip ]; then
            echo "$controller_ip controller" >> /tmp/hosts
            echo "Setup for controller info at /tmp/hosts : $controller_ip"
            echo ""
            break
        fi
   
        sleep $INTERVAL_TIME 
    done
}

change_nova_conf()
{
    sed -i "s/^rabbit_host.*/rabbit_host=$controller_ip/" /etc/nova/nova.conf
    sed -i "s/^novncproxy_base_url.*/novncproxy_base_url = http:\/\/$controller_ip:6080\/vnc_auto.html/" /etc/nova/nova.conf
    sed -i "s/^host.*/host=$controller_ip/" /etc/nova/nova.conf
    sed -i "s/^auth_uri.*/auth_uri = http:\/\/$controller_ip:5000\/v2.0/" /etc/nova/nova.conf
    sed -i "s/^identity_uri.*/identity_uri = http:\/\/$controller_ip:35357/" /etc/nova/nova.conf

    pkill -f nova-compute
    pkill -f nova-api-metadata
    pkill -f nova-network

    su -s /bin/sh -c "/usr/bin/nova-network --config-file=/etc/nova/nova.conf &" nova
    su -s /bin/sh -c "/usr/bin/nova-api-metadata --config-file=/etc/nova/nova.conf &" nova
    su -s /bin/sh -c "/usr/bin/nova-compute --config-file=/etc/nova/nova.conf --config-file=/etc/nova/nova-compute.conf &" nova

}

update_controller_ip()
{
    while true; do
        wait_controller_info
        if [ ! -z $controller_ip ]; then
            cur_controller=`cat /tmp/hosts | awk '/controller/ {print $1}'`
            echo "==================================================="
            echo "Controller node has been changed : $controller_ip"
            echo "==================================================="
            sed -i "s/$cur_controller.*/$controller_ip controller/" /tmp/hosts
            sleep 10
            change_nova_conf
        fi
    done
}

if [ $1 == "insert" ]; then
    insert_controller_ip
fi

if [ $1 == "update" ]; then
    update_controller_ip
fi