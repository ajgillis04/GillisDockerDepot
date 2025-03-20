#!/bin/bash

echo "Containers monitored by Watchtower:"
docker ps --format "{{.ID}}" | while read container_id; do
  container_name=$(docker inspect --format="{{.Name}}" $container_id | sed 's/\///')
  label=$(docker inspect --format='{{index .Config.Labels "com.centurylinklabs.watchtower.enable"}}' $container_id)
  if [ "$label" == "true" ]; then
    printf "%-30s: Yes\n" "$container_name"
  else
    printf "%-30s: No\n" "$container_name"
  fi
done
