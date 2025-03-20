# pip install pyyaml 

import yaml
import os

# Define the output directory
output_dir = '../compose/server2'

# Create the output directory if it doesn't exist
os.makedirs(output_dir, exist_ok=True)

# Load the existing docker-compose file
with open('../docker-compose-server2.yml', 'r') as file:
    compose = yaml.safe_load(file)

# Extract the 'networks' and 'volumes' sections to include only in the root file
networks = compose.pop('networks', {})
volumes = compose.pop('volumes', {})

root_compose = {
    'version': compose.get('version', '3'),
    'services': {},
    'networks': networks,
    'volumes': volumes
}

# Separate services into individual YAML files
for service_name, service_content in compose['services'].items():
    new_compose = {
        'services': {
            service_name: service_content
        }
    }

    # Save each service file in the specified directory
    with open(os.path.join(output_dir, f'{service_name}.yml'), 'w') as service_file:
        yaml.dump(new_compose, service_file, default_flow_style=False)

    # Add the service to the root compose file
    root_compose['services'][service_name] = service_content

# Save the root compose file
with open(os.path.join(output_dir, '../docker-compose-server2.yml'), 'w') as root_file:
    yaml.dump(root_compose, root_file, default_flow_style=False)

print("Docker-compose file has been split into individual service files, with networks and volumes kept in 'docker-compose-server2.yml'.")
