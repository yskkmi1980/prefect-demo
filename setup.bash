#!/bin/bash
_error_msg() {
    if [ $1 -gt 0 ]; then
        echo "$2"
        exit 1
    fi
}

_update() {
    if [ "$(uname)" == 'Darwin' ]; then
        brew update
    elif [ "$(uname)" == 'Linux' ]; then
        sudo apt-get update -y > /dev/null
    else
        exit 1
    fi
}

_install() {
    installed="$(sudo apt list --installed $1 -a)"
    if [ "$installed" == "Listing..." ] ; then
        if [ "$(uname)" == 'Darwin' ]; then
            brew install --cask $1
        elif [ "$(uname)" == 'Linux' ]; then
            sudo apt-get install $1 -y 1>/dev/null
        else
            exit 1
        fi
    fi
}

_install_docker() {
    which docker
    if [ $? -ne 0 ] ; then
        if [ "$(uname)" == 'Darwin' ]; then
            echo "pass"
        elif [ "$(uname)" == 'Linux' ]; then
            sudo mkdir -p /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            sudo apt-get update 1>/dev/null
            sudo apt-get install docker-ce docker-ce-cli containerd.io docker-compose-plugin -y > /dev/null
            sudo gpasswd -a $USER docker
        else
            exit 1
        fi
    else
        echo "skip docker"
    fi
}

_install_packages() {
    sudo apt-get update 1>/dev/null
    pack1=(wget ca-certificates curl gnupg lsb-release build-essential python3 python3-pip python3.10-venv nodejs npm)
    for pack in "${pack1[@]}"
    do
        _install $pack
    done

    which kubectl
    if [ $? -ne 0 ] ; then
        curl -LO "https://dl.k8s.io/release/$(curl -LS https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && chmod +x ./kubectl && sudo mv kubectl /usr/local/bin
    fi
    which helm
    if [ $? -ne 0 ] ; then
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    fi
    make install
}

source ~/.$(basename $SHELL)rc
case $1 in
    "minikube" | "microk8s")
        _install_packages $1
        make kubes
        _error_msg $? "ERROR: failed to make kubes"
        ;;
    *)
        echo "$0 minikube | microk8s"
        exit 1
        ;;
esac
