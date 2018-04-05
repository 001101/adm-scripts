#!/bin/bash -x
echo "##################### EXECUTE: kurento_ci_container_entrypoint #####################"

[ -n "$1" ] || {
  echo "[kurento_ci_container_entrypoint] ERROR: No script to run specified. Need one to run after preparing the environment"
  exit 1
}
BUILD_COMMAND=$@

PATH=$(realpath $(dirname "$0")):$(realpath $(dirname "$0"))/kms:$PATH

echo "[kurento_ci_container_entrypoint] Preparing environment..."

DIST=$(lsb_release -c)
DIST=$(echo ${DIST##*:} | tr -d ' ' | tr -d '\t')
export DEBIAN_FRONTEND=noninteractive

# Configure SSH keys
if [ -f "$GIT_KEY" ]; then
    mkdir -p /root/.ssh
    cp $GIT_KEY /root/.ssh/git_id_rsa
    chmod 600 /root/.ssh/git_id_rsa
    export KEY=/root/.ssh/git_id_rsa
    cat >> /root/.ssh/config <<-EOF
      StrictHostKeyChecking no
      User $([ -n "$GERRIT_USER" ] && echo $GERRIT_USER || echo jenkinskurento)
      IdentityFile /root/.ssh/git_id_rsa
EOF
    if [ "$DIST" = "xenial" ]; then
      cat >> /root/.ssh/config<<-EOF
        KexAlgorithms +diffie-hellman-group1-sha1
EOF
    fi
fi

if [ -n "$UBUNTU_PRIV_S3_ACCESS_KEY_ID" ] && [ -n "$UBUNTU_PRIV_S3_SECRET_ACCESS_KEY_ID" ]; then
  echo "AccessKeyId = $UBUNTU_PRIV_S3_ACCESS_KEY_ID
  SecretAccessKey = $UBUNTU_PRIV_S3_SECRET_ACCESS_KEY_ID
  Token = ''" >/etc/apt/s3auth.conf
fi

apt-get update && \
  apt-get install -y wget iproute
wget http://archive.ubuntu.com/ubuntu/pool/main/libt/libtimedate-perl/libtimedate-perl_2.3000-2_all.deb
dpkg -i libtimedate*deb
rm libtimedate*deb

# Installing Kurento Media Server PGP KEY
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 5AFA7A83
apt-get update

# Configure Kurento gnupg
if [ -f "$GNUPG_KEY" ]; then
  gpg --import $GNUPG_KEY
fi

# For backwards compatibility with kurento_clone_repo / Update to use github instead of gerrit
export KURENTO_GIT_REPOSITORY=${KURENTO_GIT_REPOSITORY}

echo "[kurento_ci_container_entrypoint] Network configuration"
ip addr list

for CMD in $BUILD_COMMAND; do
  echo "[kurento_ci_container_entrypoint] Running command: $CMD"
  $CMD || {
    echo "[kurento_ci_container_entrypoint] ERROR: Command failed: $CMD"
    exit 1
  }
done
