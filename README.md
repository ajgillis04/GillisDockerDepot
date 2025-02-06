
# Gillis Docker Depot

A comprehensive repository for managing and orchestrating a diverse range of Docker containers. This setup includes services for media management, databases, networking, development tools, and more. Perfect for both development and production environments, leveraging Docker Compose for streamlined deployments and GitHub for version control.

## Prerequisites
**GIT is required**  

### QNAP
1. Download and install [Entware-std](https://www.myqnap.org/product/entware-std/)  
2. SSH to the server and run the following commands:
   ```bash
   sudo opkg install git
   sudo opkg install git-http
   sudo opkg install ca-certificates libcurl
3. Add the following to .bashrc:
   ```bash
   export LD_LIBRARY_PATH=/lib:$LD_LIBRARY_PATH  
   export LD_LIBRARY_PATH=/usr/lib:$LD_LIBRARY_PATH

### Windows
1. Run the following command to install GIT:  
   ```bash
   winget install --id Git.Git -e --source winget

### Linux
1. SSH to the server and run the following commands:
   ```bash
   sudo apt-get update  
   sudo apt-get install git

## Installation

1. **Clone the repository:**
   ```bash   
   git clone git clone https://<your_token>@github.com/ajgillis04/GillisDockerDepot.git
   cd GillisDockerDepot  

3. ### Set Up the Environment:

   **Create (.env.example) / Copy the `.env` File:**
     - ensure there is a .env file in your root directory GillisDockerDepot
     - Update all environment variables with your values or comment out with #
         - example: HOST_NAME=yourservernamehere  
                    PUID=1000  
                    PGID=1000  
   **Set Up Secrets:**
     - Manually set up your secrets as required in the `secrets` folder. Ensure they are securely stored and accessible.
        ```bash   
        cd GillisDockerDepot  
        mkdir secrets  
        chmod 700 /path/to/secrets  
        chmod 600 /path/to/secrets/*  

3. **Run Docker Compose:**  
   **Use Docker Compose to create and start the containers:**  
   ```bash
   docker compose -p mediaserver -f docker-compose-server<nun>.yaml up --detach
