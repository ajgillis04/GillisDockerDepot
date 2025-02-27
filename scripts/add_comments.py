import os
from ruamel.yaml import YAML, CommentedMap

# Define the directory containing the service YAML files
directory = '../compose/server2'

# Initialize YAML handler
yaml = YAML()
yaml.preserve_quotes = True

# Predefined descriptions for each service
descriptions = {
    'bazarr.yml': 'Bazarr - Subtitle management for your media files.',
    'bookbounty.yml': 'BookBounty - A system to manage and organize your e-books.',
    'calibre-web.yml': 'Calibre-web - A web-based e-book management system.',
    'calibre.yml': 'Calibre - An e-book management software.',
    'certdumper.yml': 'CertDumper - Extract and manage SSL certificates.',
    'chowdown.yml': 'Chowdown - A self-hosted recipe management solution.',
    'cloudflare-ddns.yml': 'Cloudflare DDNS - Dynamic DNS update for Cloudflare.',
    'cloudflare-ddnsawl.yml': 'Cloudflare-DDNSAWL - Advanced dynamic DNS updates with Cloudflare.',
    'dozzle.yml': 'Dozzle - A lightweight log viewer for Docker containers.',
    'ersatztv.yml': 'ErsatzTV - A pseudo-live channel server.',
    'guacamole.yml': 'Guacamole - A remote desktop gateway.',
    'guacd.yml': 'Guacd - The Guacamole proxy daemon.',
    'heimdall.yml': 'Heimdall - An application dashboard.',
    'heimdallint.yml': 'Heimdall Internal - A separate Heimdall instance.',
    'lidarr.yml': 'Lidarr - A music collection manager for Usenet and BitTorrent users.',
    'mariadb.yml': 'MariaDB - A popular open-source relational database.',
    'mineos.yml': 'MineOS - A web-based Minecraft server management tool.',
    'nextcloud.yml': 'Nextcloud - An open-source cloud storage solution.',
    'oauth.yml': 'OAuth - Authorization and authentication protocol services.',
    'overseerr.yml': 'Overseerr - A request management and media discovery tool for Plex.',
    'photoprism.yml': 'PhotoPrism - An AI-powered open-source photo app.',
    'php-apache-awl.yml': 'PHP-Apache-AWL - A custom PHP application with Apache.',
    'php-apache-gillisonline.yml': 'PHP-Apache-Gillisonline - Another custom PHP application with Apache.',
    'phpmyadmin.yml': 'phpMyAdmin - A web-based database management tool.',
    'picard.yml': 'Picard - A cross-platform music tagger.',
    'pihole.yml': 'Pi-hole - A network-wide ad blocker.',
    'pinchflat.yml': 'PinchFlat - An example application container.',
    'plex.yml': 'Plex - A media server to organize and stream your media.',
    'portainer.yml': 'Portainer - A container management tool.',
    'prowlarr.yml': 'Prowlarr - A multi-indexer management tool.',
    'radarr.yml': 'Radarr - Automatic movie download and management tool.',
    'readarr.yml': 'Readarr - An ebook and audiobook collection manager.',
    'sabnzbd.yml': 'SABnzbd - An open-source binary newsreader.',
    'sonarr.yml': 'Sonarr - Automatic TV show download and management.',
    'tautulli.yml': 'Tautulli - A monitoring tool for Plex Media Server.',
    'tdarr.yml': 'Tdarr - GPU-accelerated video transcoding and management tool.',
    'tdarr_node.yml': 'Tdarr Node - A node instance for the Tdarr tool.',
    'traefik.yml': 'Traefik - A modern reverse proxy and load balancer.',
    'transmission-openvpn.yml': 'Transmission-OpenVPN - A combination of Transmission and OpenVPN for secure torrenting.',
    'vaultwarden.yml': 'Vaultwarden - A Bitwarden-compatible server.',
    'watchtower.yml': 'Watchtower - Automatic updater for Docker containers.',
    'wireguard.yml': 'WireGuard - A modern VPN solution.',
    'wizarr.yml': 'Wizarr - A centralized media server management tool.'
}

# Function to add a comment to the top of a YAML file
def add_comment(file_path, comment):
    with open(file_path, 'r') as file:
        content = yaml.load(file)

    # Add comment to the top of the YAML file
    content.yaml_set_start_comment(comment)

    with open(file_path, 'w') as file:
        yaml.dump(content, file)

# Iterate over each YAML file in the directory and add the predefined comment
for filename in os.listdir(directory):
    if filename in descriptions:
        file_path = os.path.join(directory, filename)
        comment = descriptions[filename]
        add_comment(file_path, comment)
        print(f"Comment added to {filename}.\n")

print("All comments have been added!")
