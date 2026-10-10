## 1. Параметры машины

- Гипервизор: VMware Fusion Professional 26H1u1 (25689522), гостевая ОС Ubuntu Server 24.04.5 LTS (aarch64)
- ОЗУ: 6144 МБ, ядер: 2, диск: 20 ГБ (NVMe)
- Имя узла devops-vm, полное имя devops-vm.devops.local:
  - `sudo hostnamectl set-hostname devops-vm`
  - `sudo sed -i 's/^127.0.1.1.*/127.0.1.1 devops-vm.devops.local devops-vm/' /etc/hosts`

## 2. Сетевые интерфейсы

| Интерфейс | Тип адаптера | Адрес                     | Назначение                                  |
| --------- | ------------ | ------------------------- | ------------------------------------------- |
| enp2s0    | NAT          | 192.168.208.129/24 (DHCP) | выход в Интернет, вход по SSH через проброс |
| enp26s0   | Host-only    | 192.168.183.128/24 (DHCP) | доступ с хоста по имени devops.local        |

- На хосте в `/etc/hosts`: `192.168.183.128 devops.local`. Адрес выдаётся по DHCP, при смене запись правится вручную.

## 3. Правило проброса портов

- Адаптер NAT: TCP, 127.0.0.1:2222 (хост) -> 2222 (гость). Правило ssh.
- На чистой установке sshd слушает порт 22: до шага 4 раздела 5 правило ведёт на 22, после него меняется на 2222.

## 4. Учётные записи

| Имя    | uid  | Группы                                     | Аутентификация                                        |
| ------ | ---- | ------------------------------------------ | ----------------------------------------------------- |
| yegor  | 1000 | yegor, adm, cdrom, sudo, dip, plugdev, lxd | создан установщиком, по SSH не пускается (AllowUsers) |
| devops | 1001 | devops, sudo, users                        | по ключу ed25519                                      |

Создание devops:

```bash
sudo adduser devops
sudo usermod -aG sudo,users devops
```

Ключ на хосте: `ssh-keygen -t ed25519 -C "devops-vm-key" -f ~/.ssh/devops_vm`, установка:
`ssh-copy-id -i ~/.ssh/devops_vm.pub -p 2222 devops@127.0.0.1` (на чистой установке порт 22 через соответствующий проброс).
Права: `~/.ssh` 700, `authorized_keys` 600. Клиентский `~/.ssh/config` на хосте:

```
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
```

## 5. Служба SSH

- Эталонная копия: `/etc/ssh/sshd_config.backup`; основной файл не меняется.
- Файл `/etc/ssh/sshd_config.d/99-hardening.conf`:

```
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers devops
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```

- Конфликт: проверить `grep -r PasswordAuthentication /etc/ssh/sshd_config.d/ /etc/ssh/sshd_config`; строку `yes` в чужом файле (например 50-cloud-init.conf) закомментировать.
- Применение: `sudo sshd -t`, затем
  `sudo systemctl disable --now ssh.socket && sudo systemctl enable --now ssh && sudo systemctl restart ssh`
  (иначе порт останется 22). Проверка: `sudo ss -tlnp | grep sshd` показывает 0.0.0.0:2222.
- Сессию не закрывать, вход проверять в новом терминале.

## 6. Правила межсетевого экрана

- Политики: deny incoming, allow outgoing, журнал medium.

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw logging medium
sudo ufw enable
```

- Правила (IPv4 и IPv6): 2222/tcp LIMIT, 80/tcp ALLOW, 443/tcp ALLOW.
- Правило для 2222 создаётся до `ufw enable`, иначе соединение разорвётся.

## 7. Снимки состояния

| Снимок             | Момент создания  |
| ------------------ | ---------------- |
| 01-clean-install   | 2026-10-06 14:07 |
| 02-keys-configured | 2026-10-06 23:59 |
| 03-ssh-hardened    | 2026-10-07 00:23 |
