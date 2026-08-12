<div align="center">

# virtual-media-devices

**Виртуальные камера и микрофон, в которые играет обычный медиафайл** (｡･ω･｡)

![v4l2loopback](https://img.shields.io/badge/v4l2loopback-kernel-FCC624?style=flat&logo=linux&logoColor=black)
![PipeWire](https://img.shields.io/badge/PipeWire-source-4A90D9?style=flat)
![FFmpeg](https://img.shields.io/badge/FFmpeg-007808?style=flat&logo=ffmpeg&logoColor=white)
![Bash](https://img.shields.io/badge/Bash-4EAA25?style=flat&logo=gnubash&logoColor=white)
![Nix](https://img.shields.io/badge/Nix-flake-7EBAE4?style=flat&logo=nixos&logoColor=white)
[![license](https://img.shields.io/badge/MIT-3DA639?style=flat)](LICENSE)
[![build](https://github.com/rokokol/virtual-media-devices/actions/workflows/build.yml/badge.svg)](https://github.com/rokokol/virtual-media-devices/actions/workflows/build.yml)

[English](README.md)

</div>

Всё началось с того, что я захотел зашазамить трек, который у меня лежал файлом, а веб-версия Shazam умеет слушать только микрофон — загрузить в неё файл нельзя. Так файл стал микрофоном

В этом и вся идея, и с видео она работает ровно так же. Страница или приложение просит камеру или микрофон — ты даёшь ему такой, в котором по кругу играет твой файл. Настоящие устройства не трогаются, в наушники ничего не выводится, и оба источника живут ровно столько, сколько выполняется команда

```sh
virtual-mic track.mp3       # микрофон, в котором играет track.mp3
virtual-cam clip.mp4        # камера, в которой играет clip.mp4
```

Приехало из моего райса, **[rokokol/huix](https://github.com/rokokol/huix)**

## Содержание

- [Две команды](#две-команды)
- [С Nix](#с-nix)
- [Модуль NixOS](#модуль-nixos)
- [Модуль Home Manager](#модуль-home-manager)
- [Без Nix](#без-nix)
- [Опции](#опции)
- [Как выбрать устройство в приложении](#как-выбрать-устройство-в-приложении)

## Две команды

`virtual-mic <аудио-или-видео>` создаёт источник через `module-pipe-source` и кормит FIFO из ffmpeg. Это **чистый источник**: устройство вывода не создаётся, поэтому в наушниках тишина и никакого эха обратно. По Ctrl+C источник выгружается, FIFO удаляется

```
-n, --name <имя>    имя, под которым его видят приложения (по умолчанию "Virtual-Mic")
```

`virtual-cam <видео-или-картинка>` пишет кадры в устройство v4l2loopback, которое приложения видят обычной камерой. Принимает и видео, и статичную картинку, крутит по кругу и пересчитывает таймстемпы от номера кадра — иначе на стыке петли картинка дёргается. Звука в v4l2 нет, звук — это микрофон

```
-d, --device <путь> устройство вывода (по умолчанию ищется по метке, иначе /dev/video10)
-f, --fps <n>       частота кадров (по умолчанию 30)
-m, --mirror        отзеркалить по горизонтали, если приложение не зеркалит превью само
```

## С Nix

Ставить ничего не нужно:

```sh
nix run github:rokokol/virtual-media-devices#virtual-mic -- track.mp3
nix run github:rokokol/virtual-media-devices#virtual-cam -- clip.mp4
```

Камере всё ещё нужен модуль ядра — строка `modprobe` есть в разделе [Без Nix](#без-nix), либо этим займётся модуль NixOS

## Модуль NixOS

```nix
{
  inputs.virtual-media-devices = {
    url = "github:rokokol/virtual-media-devices";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

```nix
{
  imports = [ inputs.virtual-media-devices.nixosModules.default ];

  services.virtual-media-devices = {
    camera.enable = true;
    microphone.enable = true;
  };
}
```

Камерная половина грузит `v4l2loopback`, пишет ему опции `modprobe` и ставит `virtual-cam`, уже нацеленный на объявленное устройство — метка и номер названы один раз и едут в оба места сразу. Микрофонная половина ставит команду и больше ничего не делает

## Модуль Home Manager

```nix
{
  imports = [ inputs.virtual-media-devices.homeManagerModules.default ];

  programs.virtual-media-devices = {
    camera.enable = true;
    microphone.enable = true;
  };
}
```

Здесь ставятся только команды. `camera.enable` тут **не** грузит модуль ядра — пользовательская сессия этого не может. Либо бери для этой половины модуль NixOS, либо грузи руками и укажи ноду в `VIRTUAL_CAM_DEVICE`

## Без Nix

Обе — обычный bash. Им нужны `ffmpeg`, `awk` и `coreutils`; камере дополнительно `v4l2-ctl` (`v4l-utils`) и `file`, микрофону — `pactl` (`pulseaudio-utils`, он точно так же управляет PipeWire)

```sh
git clone https://github.com/rokokol/virtual-media-devices
cd virtual-media-devices
sudo ./install.sh                 # или PREFIX=~/.local ./install.sh
```

Микрофон с этого момента работает. Камере нужно loopback-устройство:

```sh
sudo modprobe v4l2loopback devices=1 video_nr=10 card_label="Virtual Camera" exclusive_caps=1
```

Именно `exclusive_caps=1` заставляет браузеры и мессенджеры считать ноду камерой, а не выводом. Чтобы пережило перезагрузку — те же опции в `/etc/modprobe.d/v4l2loopback.conf`, а `v4l2loopback` в `/etc/modules-load.d/`

На десктопе группа `video` не нужна: systemd'шное правило `uaccess` отдаёт `/dev/video*` тому, у кого активная локальная сессия. Она нужна пользователю, который такой сессии не получает никогда — по ssh или из системного сервиса

## Опции

Оба модуля принимают ещё и `package`, так что поставленное можно переопределить или заменить целиком

| Опция | По умолчанию | |
| --- | --- | --- |
| `camera.enable` | `false` | NixOS: грузит модуль ядра и ставит команду. HM: только ставит команду |
| `camera.label` | `"Virtual Camera"` | Только NixOS. Имя, которое видят приложения, и по нему же `virtual-cam` находит устройство |
| `camera.videoNr` | `10` | Только NixOS. Какой `/dev/videoN` займёт петля. Бери номер выше реальных камер |
| `camera.users` | `[ ]` | Только NixOS. Кого положить в группу `video` — для сессий, до которых `uaccess` не достаёт |
| `microphone.enable` | `false` | Ставит команду |

Здесь намеренно нет ничего для частоты кадров, имени микрофона, частоты дискретизации и количества loopback-устройств. Опция существует там, где два места обязаны совпасть: метка и номер объявляются и для `modprobe`, и для команды — ровно поэтому они опции. Всё, что настраивает один запуск, — флаг, а всё, что решается один раз, модуль решает сам: одна петля, `exclusive_caps=1`, 48000 Гц стерео. Нужен другой layout v4l2loopback — грузи модуль ядра сам и бери только пакет

До команды настройки доезжают как `VIRTUAL_CAM_LABEL` и `VIRTUAL_CAM_DEVICE`. В обёртку они запекаются через `--set-default`, так что экспорт из окружения всё равно побеждает

## Как выбрать устройство в приложении

- **Браузеры** видят их обычными устройствами. Firefox спрашивает для каждого сайта, Chromium берёт из системного списка. Если камеры нет в списке — модуль загружен без `exclusive_caps=1`
- **Zoom, Discord, Telegram** — обычный выпадающий список устройств в настройках звонка
- **Проверить самому**: `ffplay /dev/video10` для камеры, `pavucontrol` → Recording для микрофона
- Запущенное приложение обычно не замечает устройство, появившееся позже него — сначала команда, потом приложение
