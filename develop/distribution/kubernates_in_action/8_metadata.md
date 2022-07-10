# 通过 `Downward API` 传递元数据

对于不能预先知道的数据, 比如 `pod ip`, 主机名, 或者 `pod` 自身的名称. 或者是 `pod` 的标签注解之类的.

对于此类数据, 可以通过 `kubernetes Downward API` 解决, 允许我们通过环境变量或者文件(`downwardAPI卷`)传递 `pod` 的元数据. 

`Downward API` 并不像 `REST endpoint` 那样需要通过访问的方式获取数据, 主要是将在 `pod` 的定义和状态中取得的数据作为环境变量和文件的值.

![](assert/Pasted%20image%2020220708170222.png)

目前可传递的元数据如下(需考证):

* `pod` 名称
* `pod` 的 `ip`
* `pod` 所在的命名空间
* `pod` 运行节点的名称
* `pod` 运行所归属的服务账号的名称
* 每个容器请求的 `cpu` 和内存的使用量
* 每个容器可以使用的 `cpu` 和内存的限制
* `pod` 的标签
* `pod` 的注解

```yaml
apiVersion: v1  
kind: Pod  
metadata:  
  name: downward  
spec:  
  containers:  
    - name: main  
      image: busybox  
      command:  
        - "sleep"  
        - "99999"  
      resources:  
        requests:  
          cpu: 15m  
          memory: 100Ki  
        limits:  
          cpu: 100m  
          memory: 4Mi  
      env:  
        - name: POD_NAME  
          valueFrom:  
            fieldRef:  
              fieldPath: metadata.name  
        - name: POD_NAMESPACE  
          valueFrom:  
            fieldRef:  
              fieldPath: metadata.namespace  
        - name: POD_IP  
          valueFrom:  
            fieldRef:  
              fieldPath: status.podIP  
        - name: NODE_NAME  
          valueFrom:  
            fieldRef:  
              fieldPath: spec.nodeName  
        - name: SERVICE_ACCOUNT  
          valueFrom:  
            fieldRef:  
              fieldPath: spec.serviceAccountName  
        - name: CONTAINER_CPU_REQUEST_MILLI_CORES  
          valueFrom:  
            resourceFieldRef:  
              resource: requests.cpu  
              divisor: 1m  
        - name: CONTAINER_MEMORY_LIMIT_KIBI_BYTES  
          valueFrom:  
            resourceFieldRef:  
              resource: limit.memory  
              divisor: 1Ki
```

```bash
❯ k exec downward -- env
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
HOSTNAME=downward
CONTAINER_CPU_REQUEST_MILLI_CORES=15
CONTAINER_MEMORY_LIMIT_KIBI_BYTES=4096
POD_NAME=downward
POD_NAMESPACE=default
POD_IP=10.244.0.31
NODE_NAME=app-cluster-control-plane
SERVICE_ACCOUNT=default
KUBERNETES_PORT=tcp://10.96.0.1:443
KUBERNETES_PORT_443_TCP=tcp://10.96.0.1:443
KUBERNETES_PORT_443_TCP_PORT=443
HELLO_SERVICE_PORT=tcp://10.96.72.22:8080
HELLO_SERVICE_PORT_8080_TCP_ADDR=10.96.72.22
KUBERNETES_SERVICE_PORT=443
KUBERNETES_SERVICE_PORT_HTTPS=443
KUBERNETES_PORT_443_TCP_ADDR=10.96.0.1
HELLO_SERVICE_PORT_8080_TCP=tcp://10.96.72.22:8080
HELLO_SERVICE_SERVICE_PORT=8080
HELLO_SERVICE_PORT_8080_TCP_PROTO=tcp
HELLO_SERVICE_PORT_8080_TCP_PORT=8080
KUBERNETES_SERVICE_HOST=10.96.0.1
KUBERNETES_PORT_443_TCP_PROTO=tcp
HELLO_SERVICE_SERVICE_HOST=10.96.72.22
HOME=/root
```

或者挂载到文件中

```yaml
apiVersion: v1  
kind: Pod  
metadata:  
  name: downward  
  labels:  
    foo: bar  
  annotations:  
    key1: value1  
    key2: |  
      multi  
      line  
      value  
spec:  
  containers:  
    - name: main  
      image: busybox  
      command:  
        - "sleep"  
        - "99999"  
      resources:  
        requests:  
          cpu: 15m  
          memory: 100Ki  
        limits:  
          cpu: 100m  
          memory: 4Mi  
      volumeMounts:  
        - mountPath: /etc/downward  
          name: downward  
  volumes:  
    - name: downward  
      downwardAPI:  
        items:  
          - path: podName  
            fieldRef:  
              fieldPath: metadata.name  
          - path: podNamespace  
            fieldRef:  
              fieldPath: metadata.namespace  
          - path: labels  
            fieldRef:  
              fieldPath: metadata.labels  
          - path: annotations  
            fieldRef:  
              fieldPath: metadata.annotations  
          - path: containerCpuRequestMilliCores  
            resourceFieldRef:  
              resource: requests.cpu  
              containerName: main  
              divisor: 1m  
          - path: containerMemoryLimitBytes  
            resourceFieldRef:  
              resource: limits.memory  
              divisor: 1Ki  
              containerName: main
```

```bash
❯ k exec downward -- ls -1L /etc/downward
annotations
containerCpuRequestMilliCores
containerMemoryLimitBytes
labels
podName
podNamespace
```

# 与 `Kubernetes API` 服务器交互

`Downward API` 只可以暴露部分元数据, 可以通过与 `Kubernetes API` 服务器交互来获取信息, 这需要通过服务器的 `REST endpoint`.

首先需要通过 `kubectl proxy` 启动代理服务来接收来自本机的 `HTTP` 连接并转发到 `API` 服务器, 这样就不需要每次请求都上传认证凭证, 也可以确保我们直接与真实的 `API` 服务器交互, 而不是一个中间人.

`curl localhost:8001` 可以获取到大部分的资源类型. 没有列入 `API` 组的初始资源类型一般被认为归属于核心的 `API` 组.

```bash
# 列举所有apiVersion: v1的资源
curl http://localhost:8001/api/v1
...
{
      "name": "serviceaccounts",
      "singularName": "",
      "namespaced": true,
      "kind": "ServiceAccount",
      "verbs": [ # 资源对应可以使用的动词
        "create",
        "delete",
        "deletecollection",
        "get",
        "list",
        "patch",
        "update",
        "watch"
      ],
      "shortNames": [ # 简称
        "sa"
      ],
      "storageVersionHash": "pbx9ZvyFpBE="
}
...
```

```bash
# 列举集群中所有的Job实例
curl http://localhost:8001/apis/batch/v1/jobs
# 同 kubectl get job my-job -o json
curl localhost:8001/apis/batch/v1/namespaces/default/jobs/my-job
```

## 在容器内部与 `Kubernetes API` 交互

```yaml
apiVersion: v1  
kind: Pod  
metadata:  
  name: curl  
spec:  
  containers:  
    - name: main  
      image: curlimages/curl  
      command:  
        - sleep  
        - "999999"
```

```bash
kubectl exec -it curl -- bash
```

可以通过 `env | grep KUBERNETES` 获取服务地址, 也可以直接使用 `https://kubernetes`, `kubernetes` 作为一个 `Service` 是可以直接通过 `host` 名称访问.

还需要证书和 `token` 来获得访问权限.

证书可以通过 `export CURL_CA_BUNDLE=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt` 来绑定, 或者使用 `--cacert` 作为 `curl` 的参数.

`export TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token` 来挂载凭证.

这样就可以像如下命令一样请求 `API` 服务器了:

```bash
curl -H "Authorization: Bearer $TOKEN" https://kubernetes # 如果执行失败可以简单粗暴创建如下角色绑定
k create clusterrolebinding permissive-binding \
--clusterrole cluster-admin \
--group=system:serviceaccounts
```

当前 `pod` 的命名空间也被放到了一样的文件夹中:

```bash
export NS=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
curl -H "Authorization: Bearer $TOKEN" https://kubernetes/api/v1/namespaces/$NS/pods
```

![](assert/Pasted%20image%2020220708185332.png)

## 使用 `Ambassador` 简化请求

使用 `sidecar` 容器, 可以创建一个简单的有 `kubernetes` 客户端的容器运行代理, 如下:

```bash
#!/bin/sh

API_SERVER="https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT"

CA_CRT="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"

TOKEN="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)"

/kubectl proxy --server="$API_SERVER" --certificate-authority="$CA_CRT" --token="$TOKEN" --accept-paths='^.*'
```

```Dockerfile
FROM alpine

RUN apk update && apk add curl && curl -L -O https://dl.k8s.io/v1.8.0/kubernetes-client-linux-amd64.tar.gz && tar zvxf kubernetes-client-linux-amd64.tar.gz kubernetes/client/bin/kubectl && mv kubernetes/client/bin/kubectl / && rm -rf kubernetes && rm -f kubernetes-client-linux-amd64.tar.gz

ADD kubectl-proxy.sh /kubectl-proxy.sh

ENTRYPOINT /kubectl-proxy.sh
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: curl-with-ambassador
spec:
  containers:
  - name: main
    image: curl
    command: ["sleep", "99999"]
  - name: ambassador
    image: kubectl-proxy

```

类似如上的 `pod`, 后续在 `main` 容器中可以直接执行如下命令:

```bash
kubectl exec -it curl-with-ambassador -c main -- sh
curl localhost:8001 # kubectl proxy 默认的代理地址
```

当然这个也有缺点, 会浪费额外的资源用于代理. 社区中也有各类开发语言对应的 `kubernetes` 客户端可以处理 `https` 和鉴权请求的方便使用.

