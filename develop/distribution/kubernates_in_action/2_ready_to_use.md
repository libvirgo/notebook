```toc
```

# `Kind` 上使用 `Kubernetes` 运行 `Http` 服务器

1. 示例代码:

```go
package main  
  
import (  
   "log"  
   "net/http")  
  
func main() {  
   http.HandleFunc("/", func(writer http.ResponseWriter, request *http.Request) {  
      _, err := writer.Write([]byte("<h1>Hello world</p>"))  
      if err != nil {  
         log.Fatal("err occurred:", err)  
      }  
   })  
   log.Println("listen on :8080")  
   err := http.ListenAndServe(":8080", nil)  
   if err != nil {  
      log.Println("err occurred:", err)  
   }  
}
```

2. `Dockerfile`:

```dockerfile
FROM golang:1.18.3-alpine3.16  
  
WORKDIR /usr/app/src  
  
COPY . .  
  
RUN go mod download && go mod verify && go build -v -o /usr/local/bin/app .  
  
EXPOSE 8080  
  
CMD ["app"]
```

3. 执行如下命令来构建镜像并加载到 `node` 中
	* docker build -t hello-world:v1 .
	* kind load docker-image hello-world:v1 --name app-cluster

4. 使用 `yaml` 编写 `Pod` 描述文件

```yaml
kind: Pod  
apiVersion: v1  
metadata:  
  name: "hello"  
  labels:  
    app: "hello"  
spec:  
  containers:  
    - name: hello  
       image: hello-world:v1  
```

5. 编写 `Service` 描述文件暴露端口

```yaml
kind: Service  
apiVersion: v1  
metadata:  
  name: hello-service  
spec:  
  selector:  
    app: hello  
  ports:  
    # Default port used by the image  
    - port: 8080
```

6. 编写 `ingress` 描述文件进行路由转发

```yaml
apiVersion: networking.k8s.io/v1  
kind: Ingress  
metadata:  
  name: hello-ingress  
spec:  
  rules:  
    - http:  
        paths:  
          - pathType: Prefix  
            path: "/hello"  
            backend:  
              service:  
                name: hello-service  
                port:  
                  number: 8080
```

> 因为 `kind` 是运行在容器中的, 所以如果在配置集群的时候没有端口映射的话, 要改的话需要重新构建集群. 不然的话需要使用 `ingress` 进行路由转发.

# 系统的逻辑部分

**`Pod` 和它的容器**

通常一个 `Pod` 可以包含任意数量的容器, `Pod` 有自己独立的私有 `IP` 地址和主机名

**ReplicationController**

`ReplicationController` 确保始终存在一个运行中的 `Pod` 实例, 通常, `ReplicationController` 用于复制 `Pod` 并让它们保持运行.

**为什么需要 `Service`**

`Pod` 的存在是短暂的, 一个 `Pod` 可能在任何时候消失, 或许因为它所在节点发生故障, 或者有人删除. 消失的 `Pod` 将被 `ReplicationController` 替换为新的 `Pod`. 新的和旧的具有不同的 `IP` 地址. `Service` 解决不断变化的 `Pod IP`地址问题, 以及在一个固定的 `IP` 和端口上对上对外暴露多个 `Pod`.

服务被创建时会得到一个静态 `IP`, 在服务的生命周期中这个 `IP` 都不会发生变化, 服务会确保其中一个 `Pod` 接收连接, 而不关心 `Pod` 当前运行在哪里, 以及它的 `IP` 是什么.

服务表示一组或多组提供相同服务的 `Pod` 的静态地址. 到达服务 `IP` 和端口的请求将被转发到属于该服务的一个容器的 `IP` 和端口.

# 水平伸缩应用

## 增加期望的副本数

```bash
k scale --replicas 3 deployment/hello-deployment
```

告诉 `Kubernetes` 需要确保 `Pod` 始终有三个实例在运行.

> 注意, 这并没有告诉 `Kubernetes` 需要采取什么行动, 也没有让 `Kubernetes` 增加两个 `Pod`, 只设置了新的期望的实例数量并让 `Kubernetes` 决定需要采取哪些操作来实现期望的状态.

> 这是 `Kubernetes` 最基本的原则之一, 不是告诉 `Kubernetes` 应该执行什么操作, 而是声明性地改变系统的期望状态. 并让 `Kubernetes` 检查当前的状态是否与期望的状态一致.

> 应用本身需要支持水平伸缩. `Kubernetes` 并不会让应用变得可拓展, 只是让应用的扩容和缩容变得简单.

因为现在应用有多个实例在运行, 所以请求会随机地切换到不同的 `Pod`. 当 `Pod` 有多个实例的时候 `Kubernetes` 服务就会这样做. 服务作为负载均衡挡在多个 `Pod` 前面, 无论服务后面是单个 `Pod` 还是一组 `Pod`, 它们的 `IP` 发生变化, 但服务的地址总是相同的, 这使得客户端可以很容易地连接到 `Pod`.

## 系统的新状态

![](assert/Pasted%20image%2020220630152231.png)

目前有一个服务和一个 `RC`(新版本 `RS` 替代), 并且有三个 `Pod` 实例, 它们都是由 `RS` 管理, 服务不再将所有请求发送到单个 `Pod`, 而是将它们分散到所有三个 `Pod` 中.

可以使用 `-o wide` 作为 `kubectl get pods` 的额外参数来显示 `Pod` 的 `IP` 和所在节点.

也可以使用 `kubectl describe` 描述一个 `Pod`.

# `Dashboard`

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.5.0/aio/deploy/recommended.yaml
```

创建 `ServiceAccount` 并给予权限.

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
```

创建 `Token`

```bash
kubectl -n kubernetes-dashboard create token admin-user --duration 9999h
```

使用 `kubectl proxy` 命令, 然后访问网页: [dashboard](http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/)
