
# GillisDockerDepot

A comprehensive repository for managing and orchestrating a diverse range of Docker containers. This setup includes services for media management, databases, networking, development tools, and more. Perfect for both development and production environments, leveraging Docker Compose for streamlined deployments and GitHub for version control.

## Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/your-username/GillisDockerDepot.git
   cd GillisDockerDepot

### Set Up the Environment:

1. **Create / Copy the `.env` File:**
     - Manually copy your `.env` file to the cloned repository directory.

2. **Set Up Secrets:**
     - Manually set up your secrets as required in the `secrets` folder. Ensure they are securely stored and accessible.

### Run Docker Compose:
1. **Use Docker Compose to create and start the containers::**
   ```bash
   docker compose -p mediaserver -f docker-compose.yml up --detach
