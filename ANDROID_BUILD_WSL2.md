# Browther Android Build — Guide Agent

## Objectif

Builder l'APK Android de **Browther** (fork de [brave-core](https://github.com/devndin/browther-core)) sur un PC Windows via WSL2.

Le repo GitHub est : `devndin/browther-core` (public, licence MPL-2.0).
C'est un fork de `brave/brave-core` qui build Brave Browser pour desktop, Android et iOS.

## Contexte

- Browther = navigateur web communautaire par dev&din, basé sur Brave
- On veut un APK Android Component (debug) pour valider que le build fonctionne
- Le PC a 8 GB RAM, un i5-6200U (2 cores/4 threads), et un SSD externe de 2 To
- Le build prendra 24-48h avec `-j1` ou `-j2`, c'est attendu et OK
- Les commits sont en francais

## Etape 1 — Setup WSL2

Si WSL2 n'est pas encore installé :

```powershell
# Dans PowerShell (admin)
wsl --install -d Ubuntu-24.04
```

Redémarrer si demandé, puis configurer un user/password Ubuntu.

### Déplacer la distro WSL sur le SSD externe

Par défaut WSL utilise le disque C:. On doit la déplacer sur le SSD externe (ex: `E:\`).

```powershell
# Dans PowerShell (admin)
wsl --shutdown
wsl --export Ubuntu-24.04 E:\wsl-ubuntu-backup.tar
wsl --unregister Ubuntu-24.04
wsl --import Ubuntu-24.04 E:\wsl-ubuntu E:\wsl-ubuntu-backup.tar
del E:\wsl-ubuntu-backup.tar
```

Pour se connecter avec le bon user (pas root) :
```powershell
# Trouver le username créé
wsl -d Ubuntu-24.04 -- bash -c "grep 1000 /etc/passwd | cut -d: -f1"
# Configurer comme user par défaut (remplacer USERNAME)
ubuntu2404.exe config --default-user USERNAME
```

### Configurer la RAM et le swap WSL2

Créer/modifier `%USERPROFILE%\.wslconfig` :

```ini
[wsl2]
memory=6GB
swap=32GB
swapFile=E:\\wsl-swap.vhdx
processors=4
```

Puis `wsl --shutdown` et relancer.

## Etape 2 — Dépendances (dans WSL2 Ubuntu)

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y git python3 python3-pip nodejs npm ninja-build \
  build-essential pkg-config libglib2.0-dev libgtk-3-dev \
  lsb-release curl wget openjdk-17-jdk zip unzip

# Node.js 24 (requis par brave-core)
curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
sudo apt install -y nodejs

# Vérifier
node --version  # doit être v24+
python3 --version
ninja --version
java -version  # doit être 17+
```

## Etape 3 — Cloner et initialiser

```bash
# Travailler dans le home WSL (sur le SSD externe)
mkdir -p ~/browther/desktop/src
cd ~/browther/desktop/src

# Cloner le fork brave-core
git clone https://github.com/devndin/browther-core.git brave
cd brave

# Installer les dépendances npm
npm install

# Initialiser pour Android (télécharge Chromium ~60 GB, 30-60 min)
npm run init -- --target_os=android --target_arch=arm
```

> **IMPORTANT** : `npm run init` va télécharger ~60 GB de sources Chromium. Ca prend du temps. Ne pas interrompre.

## Etape 4 — Build

```bash
cd ~/browther/desktop/src/brave

# Option A : via npm (recommandé pour le premier build)
npm run build -- --target_os=android --target_arch=arm

# Option B : si npm run build échoue (problème siso/autoninja), utiliser ninja directement
cd ~/browther/desktop/src
export AUTONINJA_BUILD_ID=local-$(date +%s)
ninja -C out/android_Component_arm chrome_public_apk -j1
```

### Optimisation mémoire

Avec 6 GB de RAM dans WSL + 32 GB swap :
- `-j1` : le plus sûr, ~48h
- `-j2` : 2x plus rapide si ça ne OOM pas, ~24h
- Surveiller la mémoire : `watch -n5 free -h`

Si le build OOM (killed), relancer avec `-j1`. Le build reprend là où il s'est arrêté.

## Etape 5 — Récupérer l'APK

Si le build réussit, l'APK sera dans :
```
~/browther/desktop/src/out/android_Component_arm/apks/BravePublic.apk
```

Pour le copier sur Windows :
```bash
cp ~/browther/desktop/src/out/android_Component_arm/apks/BravePublic.apk /mnt/e/BrowthePublic.apk
```

## Problèmes connus et solutions

### 1. PYTHONPATH manquant (brave_chromium_utils not found)

Si le build échoue avec `ModuleNotFoundError: No module named 'brave_chromium_utils'`, ajouter un fichier `.pth` :

```bash
SRC=~/browther/desktop/src
SITE_DIR=$(python3 -c 'import site; print(site.getsitepackages()[0])')
echo "$SRC/brave/script
$SRC/tools/grit/grit/extern
$SRC/brave/vendor/requests
$SRC/brave/third_party/cryptography
$SRC/brave/third_party/macholib
$SRC/build
$SRC/third_party/depot_tools" | sudo tee $SITE_DIR/brave.pth
```

### 2. AUTONINJA_BUILD_ID manquant

Si erreur `AUTONINJA_BUILD_ID is not set` :
```bash
export AUTONINJA_BUILD_ID=local-$(date +%s)
```

### 3. gn gen échoue (brave_version_utils)

Si `gn gen` échoue avec `ModuleNotFoundError: No module named 'brave_version_utils'` :
```bash
export PYTHONPATH=$HOME/browther/desktop/src/brave/script:$PYTHONPATH
```

### 4. OOM (Out of Memory)

Réduire le parallélisme :
```bash
ninja -C out/android_Component_arm chrome_public_apk -j1
```

Le build reprend là où il s'est arrêté, pas besoin de tout recommencer.

### 5. Disk space

Le workspace complet fait ~100 GB. Vérifier l'espace disponible :
```bash
df -h ~
```

## Notes

- Le build Android ne fonctionne QUE sous Linux (WSL2 compte comme Linux)
- Ne PAS essayer de builder depuis Windows natif ou PowerShell
- Le SSD externe doit être formaté en NTFS ou ext4 (pas FAT32/exFAT)
- Si WSL2 perd la connexion réseau, essayer `wsl --shutdown` puis relancer
- Les commits dans ce repo sont en francais
