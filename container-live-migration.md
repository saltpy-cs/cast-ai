# Container Live Migration

Cast.ai allows migration of running pods between nodes. There are three advantages: (1) helps with resilience, (2) helps with cost management and (3) makes operations easier.

The basic migration process is: 
- Create a new node
- Switch workload to new node
- Clear old node

## Preparing Clusters
- Configration of cluster has to be correct - improper requirements can cause downtime or drops
- To prepare a cluster
- - Install the CLM (Container Live Migration) helm chart 
- - Create a node template with CLM enabled with a taint to make sure non CLM work doesnt get scheduled to CLM nodes
- - Setup config for node linked to template
- Workloads are configured by default but labels are avilable to control workload migration

## Managing Migrations
There are two ways of triggering a migration:
1. Trigger in the dashboard
1. Trigger via kubectl

### Dashboard Triggered
- Live controller accessed through port forwarding to the cluster
- Select a pod to migrate and a target node

### Kubectl
- Resource of kind Migration from cast.ai/v1 with the podname match and the dest node
- kubectl apply that template
- Follow along using the kubectl describe command
- Investigate using logs as needed

## Automating with Evictor
- Eligable pods are automatically migrated
- An eligable pod is identified by a migration_enabled=true label
- You can ignore a pod using live-migration-disabled=true label
- If a pod as the removal-disabled=true the migration will not remove the pod under any circumstance
- Labels can combine:
- - no manual labels -> migrate -fail-> evicted
- - removal-disabled AND migration-enabled -> migrate -fail-> restore
- - live-migration-disabled -> skip migration -> evict
- - live-migration-disabled AND removal-disabled -> skip workload

## Best Practices and Limitations
### Storage
1. Prefer persistent volume claims (PVC) with remote storage and remote attachment for ex NFS volumes across regions or EBS+PVC within a region
1. empty-dir, ConfigMap and secrets are all migratable between nodes
1. Container local storage such as HostPath and tmpfs are not supported out of the box but cast.ai can help

### Containers
1. Single pod workloads are more migration friendly
1. All containers transferred together except init containers which are skipped during restore and therefore not re-executed
1. TTY enabled are not migrated
1. GPU workloads are not supported
1. The larger the memory footprint of the workload the longer the migration will take

### Security
1. Restrictive kernel profiles may interfere with migration 
1. Review how tools like seccomp and apparmor are configured before proceeding

### Infrastructure
1. Only supported on EKS clusters
1. K8S must be 1.30+
1. src and dest must both be cast.ai managed
1. nodes must run Amazon Linus 2023 image with container-d v2+ - migrations will alter container-d so dont alter as part of a change
1. Nodes must be in the same subnet and AZ
1. Uses a forked AWS VPC CNI plugin which is API compatible and up to date
