Param(
	[String]$COMMAND,
	[String]$NAME="master",
	[String]$MODULE="microk8s"
)

Function _error_msg($err, $msg) {
    if ($err -eq 0) {
        Write-Host "$msg"
        exit 1
    }
}

Function _create_instance($NAME, $MODULE) {
    multipass delete ${NAME}
    multipass purge

    multipass launch -n ${NAME} -c4 -m8G -d128G --cloud-init ./multipass.yml 22.04 --network eth10
    _error_msg $? "ERROR: failed to multipass launch ${NAME}"

    multipass transfer -r ./ ${NAME}:/home/ubuntu/prefect-demo
    multipass exec ${NAME} --working-directory /home/ubuntu/prefect-demo -- chmod +x ./*.bash
    multipass exec ${NAME} --working-directory /home/ubuntu/prefect-demo -- bash ./k8s.bash ${MODULE}
    _error_msg $? "ERROR: failed to multipass exec ${NAME} install k8s script"
    multipass exec microk8s -- sudo nano /etc/netplan/50-cloud-init.yaml
    multipass restart ${NAME}
    _error_msg $? "ERROR: failed to multipass restart ${NAME}"
}

Write-Host $Args
switch ($COMMAND) {
    "master" {
        _create_instance "$NAME" "$MODULE"
        multipass exec ${NAME} --working-directory /home/ubuntu/prefect-demo -- bash ./setup.bash ${MODULE}
        _error_msg $? "ERROR: failed to multipass exec ${NAME} setup service script"
        multipass exec ${NAME} -- microk8s config view
    }
    "cluster" {
        _create_instance "$NAME" "$MODULE"
        multipass exec ${NAME} --working-directory /home/ubuntu/prefect-demo -- bash ./setup.bash ${MODULE}
        _error_msg $? "ERROR: failed to multipass exec ${NAME} setup service script"
    }
    "shell" {
        multipass shell ${NAME}
        _error_msg $? "ERROR: failed to multipass mount ${NAME}"
    }
    "destory" {
        multipass delete ${NAME}
        multipass purge
        _error_msg $? "ERROR: failed to multipass delete ${NAME}"
    }
    default {
        Write-Host "$0 [minikube|microk8s] [install|master|cluster|shell|destory]"
        exit 1
    }
}