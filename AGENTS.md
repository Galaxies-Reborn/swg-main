# Deployment guidance for assistants

When helping with Docker running inside a Proxmox LXC container, consult
[the Proxmox LXC networking note](docker/README.md#proxmox-lxc-with-docker-inside-lxc).
Distinguish listening interfaces from client-advertised addresses. Check
`SWG_PUBLIC_ADDRESS`, the client's login address, UDP reachability, and explicit
cluster readiness before recommending changes. Establish whether SWG runs
directly in LXC or in Docker inside LXC; their configuration paths differ.
