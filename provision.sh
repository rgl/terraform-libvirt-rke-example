#!/bin/bash
set -eu -o pipefail -o errtrace


function err_trap {
    local err=$?
    local i=0
    local line_number
    local function_name
    local file_name

    set +e

    echo "ERROR: Trap exit code $err at:" >&2

    while caller $i; do ((i++)); done | while read line_number function_name file_name; do
        echo "ERROR: $file_name:$line_number $function_name"
    done >&2

    exit $err
}

trap err_trap ERR


function title {
    cat <<EOF
########################################################################
#
# $*
#
EOF
}


# show the executed commands.
set -x

# execute from this script location.
# NB this script expect to find its dependencies in the current
# working directory.
cd /tmp


# NB execute apt-cache madison docker-ce to known the available versions.
docker_version="${1:-20.10.18}"; shift || true
# NB execute apt-cache madison containerd.io to known the available versions.
containerd_version="${1:-1.6.8}"; shift || true

# prevent apt-get et al from asking questions.
# NB even with this, you'll still get some warnings that you can ignore:
#     dpkg-preconfigure: unable to re-open stdin: No such file or directory
export DEBIAN_FRONTEND=noninteractive

# wait for cloud-init to finish.
cloud-init status --wait

# ensure we have an updated apt cache.
apt-get update

# install tools.
apt-get install -y bash-completion
apt-get install -y vim

# install docker.
# see https://docs.docker.com/engine/installation/linux/docker-ce/ubuntu/#install-using-the-repository
apt-get install -y apt-transport-https software-properties-common
wget -qO- https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get update
dpk_docker_version="$(apt-cache madison docker-ce | awk "/$docker_version~/{print \$3}")"
dpk_containerd_version="$(apt-cache madison containerd.io | awk "/$containerd_version-/{print \$3}")"
apt-get install -y \
    "docker-ce=$dpk_docker_version" \
    "docker-ce-cli=$dpk_docker_version" \
    "containerd.io=$dpk_containerd_version"
apt-mark hold \
    docker-ce \
    docker-ce-cli \
    containerd.io

# stop docker and containerd.
systemctl stop docker
systemctl stop containerd

# use the systemd cgroup driver.
cgroup_driver='systemd'

# configure containerd.
# see https://kubernetes.io/docs/setup/cri/
cat >/etc/sysctl.d/99-kubernetes-cri.conf <<'EOF'
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sysctl --system
containerd config default >/etc/containerd/config.toml
cp -p /etc/containerd/config.toml{,.orig}
sed -i -E 's,(SystemdCgroup)\s*=.*,\1 = true,g' /etc/containerd/config.toml
diff -u /etc/containerd/config.toml{.orig,} || true
systemctl restart containerd

# configure it.
# see https://kubernetes.io/docs/setup/cri/
cat >/etc/docker/daemon.json <<EOF
{
    "experimental": false,
    "debug": false,
    "exec-opts": [
        "native.cgroupdriver=$cgroup_driver"
    ],
    "features": {
        "buildkit": true
    },
    "log-driver": "journald",
    "labels": [
        "os=linux"
    ],
    "hosts": [
        "fd://"
    ],
    "default-runtime": "runc",
    "containerd": "/run/containerd/containerd.sock"
}
EOF
# start docker without any command line flags as its entirely configured from daemon.json.
install -d /etc/systemd/system/docker.service.d
cat >/etc/systemd/system/docker.service.d/override.conf <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd
EOF
systemctl daemon-reload
systemctl start docker
# validate that docker is using the expected cgroup driver.
docker_cgroup_driver="$(docker info -f '{{.CgroupDriver}}')"
if [ "$docker_cgroup_driver" != "$cgroup_driver" ]; then
    echo "ERROR: Cgroup driver MUST be $cgroup_driver, but its $docker_cgroup_driver"
    exit 1
fi

# let the vagrant user manage docker.
usermod -aG docker vagrant

# download the cri tools.
# see https://github.com/kubernetes-sigs/cri-tools/releases
version='1.23.0'
url="https://github.com/kubernetes-sigs/cri-tools/releases/download/v${version}/crictl-v${version}-linux-amd64.tar.gz"
tgz="/tmp/cri-tools-${version}.tgz"
wget -qO $tgz "$url"

# configure the cri tools.
cat >/etc/crictl.yaml <<'EOF'
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 2
debug: false
pull-image-on-create: false
EOF

# install the cri tools.
tar xf $tgz -C /usr/local/bin
rm -f $tgz

# install the cri tools bash completion.
crictl completion bash >/usr/share/bash-completion/completions/crictl

# try the cri tools.
crictl --version # the client side version.
crictl version   # the server side version.
