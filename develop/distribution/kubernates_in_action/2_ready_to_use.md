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
kubectl scale rc hello --replicas=3
```

告诉 `Kubernetes` 需要确保 `Pod` 始终有三个实例在运行.

> 注意, 这并没有告诉 `Kubernetes` 需要采取什么行动, 也没有让 `Kubernetes` 增加两个 `Pod`, 只设置了新的期望的实例数量并让 `Kubernetes` 决定需要采取哪些操作来实现期望的状态.

> 这是 `Kubernetes` 最基本的原则之一, 不是告诉 `Kubernetes` 应该执行什么操作, 而是声明性地改变系统的期望状态. 并让 `Kubernetes` 检查当前的状态是否与期望的状态一致.

