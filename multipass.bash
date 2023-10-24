#!/bin/bash
_install_multipass() {
    multipass version &> /dev/null
    if [ $? -ne 0 ] ; then
        if [ "$(uname)" == 'Darwin' ]; then
            brew install --cask multipass
        elif [ "$(uname)" == 'Linux' ]; then
            sudo snap install multipass --classic
            sudo chmod a+w /var/snap/multipass/common/multipass_socket
        else
            exit 1
        fi
    fi
}

_error_msg() {
    if [ $1 -gt 0 ]; then
        echo "$2"
        exit 1
    fi
}

_launch_browser() {
    NUCLIO_HOME="http://${NAME}.local:8070"
    if [ "$(uname)" == 'Darwin' ]; then
        open ${NUCLIO_HOME}
    elif [ "$(uname)" == 'Linux' ]; then
        xdg-open ${NUCLIO_HOME}
    else
        exit 1
    fi
}

_add_host() {
    _IP=$(multipass exec ${NAME} -- hostname -I | cut -f1 -d' ')
    sed -e "/${NAME}/d" /etc/hosts | sudo sh -c 'cat - > /etc/hosts'
    echo "${_IP} ${NAME} ${NAME}.local" | sudo sh -c 'cat - >> /etc/hosts'
    echo "http://${NAME}.local:8070"
}

_create_instance() {
    NAME=$1
    MODULE=$2
    sudo ufw disable
    multipass delete ${NAME} && multipass purge

    multipass launch -n ${NAME} -c4 -m8G -d128G --cloud-init ./multipass.yml 22.04 --network br0
    _error_msg $? "ERROR: failed to multipass launch ${NAME}"

    echo "multipass restart"
    multipass restart ${NAME}
    _error_msg $? "ERROR: failed to multipass restart ${NAME}"

    sleep 10

    multipass mount ./ ${NAME}:/home/ubuntu/prefect-demo
    _error_msg $? "ERROR: failed to multipass mount ${NAME}"
    multipass exec ${NAME} --working-directory /home/ubuntu/prefect-demo -- ./k8s.bash $MODULE
}

COMMAND=${1}
MODULE=${2:-microk8s}
NAME=${3:-prefect}
_install_multipass
_error_msg $? "ERROR: failed to install multipass"
case $COMMAND in
    "install")
        _create_instance "$NAME" "$MODULE"
        multipass exec ${NAME} --working-directory /home/ubuntu/prefect-demo -- ./setup.bash $MODULE
        _error_msg $? "ERROR: failed to multipass exec ${NAME} setup service script"
        ;;
    "config" )
        multipass exec ${NAME} -- microk8s config view
        ;;
    "shell")
        multipass shell ${NAME}
        _error_msg $? "ERROR: failed to multipass mount ${NAME}"
        ;;
    "destory")
        multipass delete ${NAME} && multipass purge
        _error_msg $? "ERROR: failed to multipass delete ${NAME}"
        ;;
    *)
        echo "$0 | master | cluster | config | shell | destory"
        exit 1
        ;;
esac
exit 0