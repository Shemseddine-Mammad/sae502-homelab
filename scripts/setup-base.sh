#!/bin/bash
# setup-base.sh - Prepare la VM de base SAE 5.02 avant l'export en OVA
#
# A lancer DANS la VM de base :  sudo bash setup-base.sh
#
# Ce script :
#   1. installe le strict minimum pour depanner en console (nano, ping)
#   2. installe le script de premier demarrage lab-firstboot.sh
#   3. installe et active le service systemd qui le lance
#   4. nettoie l'image (cles SSH, machine-id, logs, swap, cache apt)
#   5. remplit l'espace libre de zeros puis eteint la VM
#
# Au premier demarrage d'un clone, lab-firstboot.sh lit l'adresse MAC de la
# carte host-only (08:00:27:56:00:XX) et en deduit le role de la VM :
#   XX = 0a -> vm-manager  192.168.56.10
#   XX = 0b -> vm-services 192.168.56.11
#   XX = 0c -> vm-backup   192.168.56.12
# Les MAC sont fixees par deploy-lab.ps1 au moment de l'import.

set -euo pipefail
[ "$EUID" -eq 0 ] || { echo "A lancer avec sudo"; exit 1; }

echo "[1/5] Outils minimum de depannage"
apt-get update
apt-get install -y nano iputils-ping
apt-get full-upgrade -y

echo "[2/5] Script de premier demarrage"
cat > /usr/local/sbin/lab-firstboot.sh << 'SCRIPT'
#!/bin/bash
# lab-firstboot.sh - Personnalise un clone de la maquette SAE 5.02
# Lance une seule fois par le service lab-firstboot.service.
# Journal : /var/log/lab-firstboot.log
set -eu
exec >> /var/log/lab-firstboot.log 2>&1
echo "=== $(date) ==="

# Attendre que les cartes reseau soient detectees (30 s max)
MAC=""
for i in $(seq 1 30); do
  for f in /sys/class/net/*/address; do
    case "$(cat "$f")" in
      08:00:27:56:00:*) MAC=$(cat "$f") ;;
    esac
  done
  [ -n "$MAC" ] && break
  sleep 1
done

if [ -z "$MAC" ]; then
  echo "Aucune MAC de maquette (08:00:27:56:00:XX) : rien a faire."
  exit 0
fi

LAST=$((16#${MAC##*:}))
case "$LAST" in
  10) NAME=vm-manager ;;
  11) NAME=vm-services ;;
  12) NAME=vm-backup ;;
  *)  echo "MAC $MAC non prevue, arret."; exit 1 ;;
esac
IP="192.168.56.$LAST"
echo "MAC $MAC -> $NAME ($IP)"

# Nom de la machine
echo "$NAME" > /etc/hostname
hostname "$NAME"
sed -i "s/^127\.0\.1\.1.*/127.0.1.1 $NAME/" /etc/hosts

# Cles SSH propres a ce clone
[ -e /etc/ssh/ssh_host_ed25519_key ] || ssh-keygen -A

# Reseau : enp0s3 = NAT (Internet), enp0s8 = host-only (maquette)
rm -f /etc/netplan/*.yaml
cat > /etc/netplan/01-lab.yaml << EOF
network:
  version: 2
  ethernets:
    enp0s3:
      dhcp4: true
    enp0s8:
      addresses: [$IP/24]
EOF
chmod 600 /etc/netplan/01-lab.yaml
netplan generate

touch /var/lib/lab-firstboot.done
echo "Configuration terminee."
SCRIPT
chmod 755 /usr/local/sbin/lab-firstboot.sh

echo "[3/5] Service systemd"
cat > /etc/systemd/system/lab-firstboot.service << 'UNIT'
[Unit]
Description=Personnalisation du clone au premier demarrage (SAE 5.02)
DefaultDependencies=no
After=local-fs.target systemd-udev-trigger.service
Before=network-pre.target systemd-networkd.service ssh.socket ssh.service
Wants=network-pre.target
ConditionPathExists=!/var/lib/lab-firstboot.done

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/lab-firstboot.sh

[Install]
WantedBy=sysinit.target
UNIT
systemctl daemon-reload
systemctl enable lab-firstboot.service

# Empeche cloud-init de reecrire la configuration reseau
echo 'network: {config: disabled}' > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg

echo "[4/5] Nettoyage de l'image"
apt-get clean
apt-get autoremove --purge -y
journalctl --vacuum-time=1s || true
rm -rf /var/log/*.gz /var/log/*.1 /var/log/lab-firstboot.log /tmp/* /var/tmp/*
swapoff -a || true
rm -f /swap.img
sed -i '/swap.img/d' /etc/fstab
rm -f /var/lib/lab-firstboot.done
rm -f /etc/ssh/ssh_host_*
truncate -s 0 /etc/machine-id
rm -f /home/ansible/.bash_history /root/.bash_history

echo "[5/5] Remplissage de zeros (le message 'No space left on device' est normal)"
dd if=/dev/zero of=/zero bs=1M status=progress || true
rm -f /zero
sync

echo "VM de base prete. Extinction."
poweroff
