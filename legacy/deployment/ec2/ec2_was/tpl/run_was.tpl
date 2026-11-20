#!/bin/bash

sudo useradd appadm
sudo gpasswd appadm -a appadm

cat <<EOF | sudo tee -a /etc/sudoers
appadm ALL=NOPASSWD: ALL
EOF

cat <<EOF | sudo tee -a /home/ec2-user/.ssh/authorized_keys

${local_public_key}

${service_public_key}
EOF

mkdir -p /home/appadm/.ssh
sudo cp /home/ec2-user/.ssh/authorized_keys /home/appadm/.ssh/authorized_keys
sudo chown -R appadm:appadm /home/appadm/.ssh
sudo chmod 700 /home/appadm/.ssh

sudo yum install -y java-1.8.0-openjdk-devel

javac_path=$(which javac)
javac_real_path=$(readlink -f $javac_path)
java_path=$(dirname $(dirname $javac_real_path))

cat <<EOF | sudo tee -a /etc/profile.d/java.sh
export JAVA_HOME=$${java_path}
export PATH=$PATH:$JAVA_HOME/bin
EOF
sudo chmod 644 /etc/profile.d/java.sh
source /etc/profile.d/java.sh

sudo mkfs -t ext4 ${was_engine_volume_path}
sudo mkfs -t ext4 ${was_log_volume_path}

sudo mkdir ${was_engine_volume_mount_path}
sudo mkdir ${was_log_volume_mount_path}

sudo mount ${was_engine_volume_path} ${was_engine_volume_mount_path}/
sudo mount ${was_log_volume_path} ${was_log_volume_mount_path}/

sudo cp /etc/fstab /etc/fstab.bak

cat <<EOF | sudo tee -a /etc/fstab
${was_engine_volume_path}       ${was_engine_volume_mount_path}   ext4    defaults,nofail        0       0
${was_log_volume_path}          ${was_log_volume_mount_path}   ext4    defaults,nofail        0       0
EOF

sudo mount -a

cd ~/

wget http://archive.apache.org/dist/tomcat/tomcat-8/v8.5.27/bin/apache-tomcat-8.5.27.tar.gz
tar zxvf apache-tomcat-8.5.27.tar.gz
mv apache-tomcat-8.5.27 ${was_engine_volume_mount_path}/tomcat8

mv ${was_engine_volume_mount_path}/tomcat8/logs ${was_log_volume_mount_path}

ln -s ${was_log_volume_mount_path}/logs ${was_engine_volume_mount_path}/tomcat8/logs

sudo yum install ruby -y
wget https://aws-codedeploy-ap-northeast-2.s3.amazonaws.com/latest/install
chmod +x ./install
sudo ./install auto
sudo service codedeploy-agent status
sudo service codedeploy-agent restart

cat <<EOF | sudo tee -a /etc/profile.d/catalina.sh
export CATALINA_HOME=${was_engine_volume_mount_path}/tomcat8
EOF
sudo chmod 644 /etc/profile.d/catalina.sh
source /etc/profile.d/catalina.sh

cat <<EOF | sudo tee -a /etc/systemd/system/tomcat8.service
[Unit]
Description=Apache Tomcat Web Application Container
After=syslog.target network.target
[Service]
Type=forking
Environment="JAVA_HOME=$${java_path}"
Environment="CATALINA_HOME=${was_engine_volume_mount_path}/tomcat8"
Environment="CATALINA_BASE=${was_engine_volume_mount_path}/tomcat8"
Environment="CATALINA_OPTS=-Xms512M -Xmx1024M -server -XX:+UseParallelGC"
Environment="JAVA_OPTS=-Djava.security.egd=file:///dev/urandom"
ExecStart=${was_engine_volume_mount_path}/tomcat8/bin/startup.sh
ExecStop=${was_engine_volume_mount_path}/tomcat8/bin/shutdown.sh
User=appadm
Group=appadm
UMask=0007
RestartSec=10
Restart=always
[Install]
WantedBy=multi-user.target
EOF

sudo chown -R appadm:appadm /engn001
sudo chown -R appadm:appadm /logs001
sudo chmod 755 /engn001
sudo chmod 755 /logs001

sudo systemctl daemon-reload
sudo systemctl enable tomcat8
sudo systemctl start tomcat8