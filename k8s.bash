#!/bin/bash
_error_msg() {
    if [ $1 -gt 0 ]; then
        echo "$2"
        exit 1
    fi
}

_install_k8s() {
    case $1 in
        "minikube")
            if (type "minikube" > /dev/null 2>&1); then
                echo "installed minikube"
            else
                if [ "$(uname)" == 'Darwin' ]; then
                    brew install minikube
                elif [ "$(uname)" == 'Linux' ]; then
                    mkdir /tmp
                    curl -Lo /tmp/minikube_latest_amd64.deb https://storage.googleapis.com/minikube/releases/latest/minikube_latest_amd64.deb
                    sudo dpkg -i /tmp/minikube_latest_amd64.deb
                    rm /tmp/minikube_latest_amd64.deb
                    chmod +x /usr/local/bin/kubectl
                else
                    exit 1
                fi
            fi
            minikube start
            _error_msg $? "ERROR: failed to minikube start"
            minikube ip
            _error_msg $? "ERROR: failed to minikube ip"
            ;;
        "k3d")
            if (type "k3d" > /dev/null 2>&1); then
                echo "installed k3d"
            else
                wget -q -O - https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
            fi
            ;;
        "microk8s")
            sudo snap install microk8s --classic
            sudo usermod -a -G microk8s $USER
            echo "alias kubectl='microk8s kubectl'" >> ~/.$(basename $SHELL)rc
            echo "alias helm='microk8s helm'" >> ~/.$(basename $SHELL)rc
            echo "export KUBECONFIG=~/.kube/config"
            mkdir -p ~/.kube
            sudo microk8s kubectl config view --raw > ~/.kube/config
            _error_msg $? "ERROR: failed to kubectl config view"

            sudo chown $USER:$USER ~/.kube/config
            sudo microk8s status --wait-ready 1>/dev/null
            sudo microk8s add-node 1>/dev/null

            sudo iptables -P FORWARD ACCEPT 1>/dev/null

            pack1=(dns registry storage ingress prometheus helm host-access dashboard)
            for pack in "${pack1[@]}"
            do
                sudo microk8s enable $pack 1>/dev/null
                _error_msg $? "ERROR: failed to microk8s enable $pack"
            done
            sudo microk8s status --wait-ready
            sudo microk8s inspect
            ;;
        *)
            echo "$0 k3d | minikube | microk8s"
            exit 1
            ;;
    esac
}

_install_k8s $1