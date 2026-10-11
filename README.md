# SAE 5.02 - Home lab automatise avec Ansible

Deploiement, securisation, sauvegarde et mise a jour des services du home lab,
uniquement a partir de playbooks Ansible.

## Prerequis
- VirtualBox, OVA de base (scripts/setup-base.sh) et reseau host-only 192.168.56.0/24
- 3 VM deployees avec scripts/deploy-lab.ps1

## Lancer le deploiement
ansible-playbook site.yml
