# Stockage — carte `/data`

## Rôle
Séparer l'OS (microSD 32 Go, `/`) des données qui grossissent (carte 128 Go,
`/data`). Si l'OS est réinstallé, `/data` survit.

## Matériel
- Carte 128 Go, adaptateur USB 3.0 (port bleu du Pi)
- Filesystem ext4, label `DATA`
- UUID : `<UUID-carte-data>`
- Reformatée à neuf le 2026-05-31

## Montage persistant (`/etc/fstab`)
```
UUID=<UUID-carte-data> /data ext4 defaults,noatime,nodev,nosuid,nofail,x-systemd.device-timeout=10 0 2
```
| Option | Rôle |
|---|---|
| `noatime` | pas d'écriture de l'heure d'accès, préserve la carte |
| `nodev`, `nosuid` | durcissement (bloque devices et binaires setuid sur la carte) |
| `nofail` + `x-systemd.device-timeout=10` | le Pi démarre même si la carte est absente/morte (anti-lockout) |
| `0 2` | vérif fsck après la partition racine |

Point de montage : `/data`, propriété `<user>:<user>`.
Backup de l'ancien fstab : `/etc/fstab.bak.2026-05-31`.

Attention, revers du `nofail` : si la carte ne monte pas au boot, `/data` est
un simple dossier vide sur la SD et tout ce qui y écrit (Docker, un jour le
data-root) écrit sur la SD sans prévenir. D'où le drop-in
`RequiresMountsFor=/data` prévu dans la migration data-root (cf. README).

## Commandes utiles
```bash
findmnt /data        # voir le montage
df -h /data          # espace libre
sudo mount /data     # monter (si démonté)
sudo umount /data    # démonter
sudo mount -a        # tester toutes les entrées fstab
```

## Organisation (arborescence créée le 2026-06-05)
```
/data
├── docker/    → stacks des services : compose + données (pihole, nginx, firefly, monitoring)
├── apps/      → libre pour la suite
└── backups/   → sauvegardes (à automatiser, cf. docs/firefly.md)
```
Le data-root Docker (images, conteneurs), lui, est encore sur la SD
(`/var/lib/docker`) — migration vers `/data/docker-root` prévue, procédure
dans le README.
