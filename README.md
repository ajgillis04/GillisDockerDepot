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

## 📡 Optional: Share Docker Folder via NFS (Linux/Ubuntu)

If you want to access your `~/Docker` folder from other machines (like Windows or QNAP), you can share it using **NFS** and set up a **persistent mount** so it reconnects automatically. This makes it easy to copy and paste your .env or secrets folder if you setup on another machine. 

### 🛠️ Install NFS Server on Ubuntu

```bash
sudo apt update
sudo apt install nfs-kernel-server
```

### 📁 Share the Docker Folder

Make sure the folder exists and has open permissions (you can tighten later):

```bash
mkdir -p ~/Docker
sudo chown nobody:nogroup ~/Docker
sudo chmod 777 ~/Docker
```

### 📜 Configure `/etc/exports`

Edit the exports file:

```bash
sudo nano /etc/exports
```

Add this line:

```bash
/home/yourusername/Docker 192.168.1.0/24(rw,sync,no_subtree_check)
```

> Replace `yourusername` with your actual Linux username and `192.168.1.0/24` with your local subnet or specific client IP.

Apply the changes:

```bash
sudo exportfs -a
sudo systemctl restart nfs-kernel-server
```

---

### 🔁 Persistent Mount on Windows

To mount the share persistently on Windows:

1. Open **Command Prompt as Administrator**
2. Run:

```cmd
net use Z: \\192.168.1.x\home\yourusername\Docker /persistent:yes
```

> Replace `192.168.1.x` with your Ubuntu IP and `yourusername` with your actual username.

---

### 🔁 Persistent Mount on Linux

Create a mount point:

```bash
sudo mkdir -p /mnt/docker
```

Add this line to `/etc/fstab`:

```bash
192.168.1.x:/home/yourusername/Docker /mnt/docker nfs defaults 0 0
```

Then mount it:

```bash
sudo mount -a
```

---

Now your Docker folder will be available across machines — even after reboot. 🔄
```

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
