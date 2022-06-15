# Docker for OpenStackID (IDP)

# Unit Tests

## image build

````bash
docker build -t idp_test --target test --no-cache .
````

## run

````bash
 docker run -t --rm idp_test ./tests.sh <SHA1_COMMIT> [OPTIONAL] 
````

# Build



# Useful commands

* kill all running containers with

```bash 
  docker kill $(docker ps -q)
```

* delete all stopped containers with

```bash 
docker rm $(docker ps -a -q)
```

* delete all images with 

```bash
docker rmi $(docker images -q) -f
```

* check process using supervisord

```bash
supervisorctl
```