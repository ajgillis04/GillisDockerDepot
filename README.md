# Gillis Docker Depot  

A comprehensive repository for managing and orchestrating a diverse range of Docker containers. This setup includes services for **media management, databases, networking, development tools, and more**. Perfect for both **development and production environments**, leveraging **Docker Compose for streamlined deployments** and **GitHub for version control**.  

📖 **Want full service setup guides?** See the [Wiki Home](https://github.com/ajgillis04/GillisDockerDepot/wiki) for detailed configurations.  

---

## Prerequisites  

To get started, **Git must be installed** on your system:  

### 📦 **QNAP**  
1. **Download and install [Entware-std](https://www.myqnap.org/product/entware-std/)**
   - 🚨 **Note:** Close any open SSH sessions; `opkg` won’t be added to the path until you log in again.  
2. **Install Git via SSH:**  
   ```bash
   sudo opkg install git  
   sudo opkg install git-http  
   sudo opkg install ca-certificates libcurl  
   ```  
3. **Update `.bashrc` for Git:**  
   ```bash
   export LD_LIBRARY_PATH=/lib:$LD_LIBRARY_PATH  
   export LD_LIBRARY_PATH=/usr/lib:$LD_LIBRARY_PATH  
   source ~/.bashrc  
   exit  
   ```  

### 🖥️ **Windows**  
1. Install Git using `winget`:  
   ```bash
   winget install --id Git.Git -e --source winget  
   ```  

### 🐧 **Linux**  
1. Install Git using package manager:  
   ```bash
   sudo apt-get update  
   sudo apt-get install git  
   ```  

---

## 🧾 Samba Share Setup for DockerDepot (Linux → Windows)

### 📍 Server: Linux (Ubuntu/Debian)

#### 1. **Install Samba**
```bash
sudo apt install samba
```

#### 2. **Create the Share Folder**
```bash
mkdir -p /home/<username>/Docker
```

#### 3. **Configure Samba Share**
Edit `/etc/samba/smb.conf` and add this at the end:
```ini
[DockerDepot]
path = /home/<username>/Docker
browseable = yes
read only = no
guest ok = no
```

#### 4. **Create Samba User**
```bash
sudo smbpasswd -a <username>
```

#### 5. **Restart Samba**
```bash
sudo systemctl restart smbd
```

---

### 🖥️ Client: Windows

#### 1. **Access the Share**
Open File Explorer and enter:
```
\\<linux-ip-address>\DockerDepot
```

#### 2. **Authenticate**
- **Username**: `<username>`
- **Password**: Samba password you just set

Check “Remember my credentials” for seamless access.

#### 3. **Map the Drive (Optional)**
- Right-click “This PC” → “Map network drive”
- Choose a drive letter (e.g., `Z:`)
- Enter: `\\<linux-ip-address>\DockerDepot`
- Check “Reconnect at sign-in”

---

### 🧠 Notes

- NFS is not required for Windows clients — Samba is native.
- You can add more shares by repeating the `[ShareName]` block in `smb.conf`.
- For tighter security, disable guest access and restrict by user/group.


## Installation  

### 🔄 **Clone the Repository**  
🚨 **For QNAP Users**: Before cloning, **create a "Docker" shared folder** via **Control Panel → Shared Folders → Privileges**.  
🚨 **For all other OS**:  mkdir ~/Docker/

1. **Clone the repo:**  
   ```bash
   cd ~/Docker
   git clone https://<your_token>@github.com/ajgillis04/GillisDockerDepot.git  
   cd GillisDockerDepot  
   ```  

---

## Environment Setup  

### 📌 **Set Up Environment Variables**  
1. **Ensure a `.env` file exists** in your repo root (`GillisDockerDepot`).  
2. **Update your variables** (or comment them out with `#` if unused).  

   Example variables:  
   ```bash
   HOST_NAME=yourservernamehere  
   PUID=1000  
   PGID=1000  
   ```

### 🔒 **Set Up Secrets**  
1. **Manually create** a `secrets` folder for sensitive configurations:  
   ```bash
   cd GillisDockerDepot  
   mkdir secrets  
   chmod 700 /path/to/secrets  
   chmod 600 /path/to/secrets/*  
   ```  

---

## 🚀 Running Docker Compose  

To **deploy your containers**, run:  
   ```bash
   docker compose -p mediaserver -f docker-compose-server<num>.yaml up --detach  
   ```  

---

## 🛠️ Notable Git Commands  

### 🔄 **Pull latest changes**  
   ```bash
   git pull  
   ```  

### ✅ **Commit and push changes**  
   ```bash
   git status  
   git add .  
   git commit -m "Your descriptive commit message here"  
   git push https://yourgitapitoken@github.com/ajgillis04/GillisDockerDepot.git  
   ```  

---

## 📖 Need help with service configurations?  
📌 See the [Wiki Home](https://github.com/ajgillis04/GillisDockerDepot/wiki) for individual service setup guides.  

🚀 **Happy deploying!**
