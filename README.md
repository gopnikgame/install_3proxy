# 3proxy Auto Installer

Автоматический установщик и менеджер `3proxy` для Debian/Ubuntu.

## Возможности

* Установка `3proxy`
* HTTP Proxy
* SOCKS5 Proxy
* Авторизация по логину/паролю
* Проверка занятых портов
* Автоматическое открытие портов в UFW
* Перенастройка существующей установки
* Полное удаление
* Systemd-сервис
* Логирование

---

## Поддерживаемые ОС

* Ubuntu 20.04+
* Ubuntu 22.04+
* Ubuntu 24.04+
* Debian 11+
* Debian 12+

---

## Установка

```bash
wget https://raw.githubusercontent.com/USERNAME/REPO/main/3proxy-manager.sh && chmod +x 3proxy-manager.sh && sudo ./3proxy-manager.sh
```

---

## Возможности меню

```text
1) Установить / перенастроить 3proxy
2) Удалить 3proxy
3) Показать статус
0) Выход
```

---

## После установки

HTTP Proxy:

```text
http://USER:PASSWORD@SERVER_IP:8080
```

SOCKS5 Proxy:

```text
socks5://USER:PASSWORD@SERVER_IP:1080
```

---

## Проверка работы

```bash
curl -x http://USER:PASSWORD@SERVER_IP:8080 https://api.ipify.org
```

---

## Управление сервисом

Статус:

```bash
systemctl status 3proxy
```

Перезапуск:

```bash
systemctl restart 3proxy
```

Логи:

```bash
tail -f /var/log/3proxy/3proxy.log
```

---

## Конфиг

```text
/etc/3proxy/3proxy.cfg
```

---

## Безопасность

Рекомендуется:

* использовать сложные пароли
* ограничить IP через firewall
* не оставлять прокси открытым в интернет без авторизации

---

## Лицензия

MIT
