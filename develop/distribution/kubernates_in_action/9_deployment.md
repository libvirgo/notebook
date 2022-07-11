```toc
```

本章讲述如何升级在 `kubernetes` 集群中运行的应用程序, 以及 `kubernetes` 如何实现真正的零停机升级过程. 升级操作可以通过使用 `ReplicationController` 或者 `ReplicaSet` 实现, 但 `kubernetes` 提供了另一种基于 `ReplicaSet` 的资源 `Deployment`

# 更新运行在 `pod` 内的应用程序

![](assert/Pasted%20image%2020220711113248.png)

假设 `pod` 开始使用 `v1` 版本的镜像, 新版本镜像为 `v2`, 接下来想用这个新版本替换所有的 `pod`. 由于 `pod` 在创建后, 不允许直接修改镜像, 只能通过删除原有 `pod` 并使用新的镜像创建新的 `pod` 替换.

有以下两种方法可以更新所有 `pod`:
* 直接删除所有现有的 `pod`, 然后创建新的.
* 也可以先创建新的 `pod`, 等它们成功运行之后再删除旧的 `pod`.

第一种方法会导致应用程序在一定的时间内不可用, 使用第二种方法的话应用程序需要支持两个版本同时对外提供服务. 如果使用了数据库, 那么新版本不应该对原有的数据格式或者数据本身进行修改, 从而导致之前的版本运行异常.

首先让我们手动执行操作, 了解了其中涉及的要点之后, 继续学习让 `kubernetes` 自动执行.

## 删除旧的, 使用新的替换

![](assert/Pasted%20image%2020220711150715.png)

如果使用了 `RC` 管理一组 `v1`, 可以直接通过将 `pod` 模版修改成 `v2`版本的镜像, 然后删除旧的, `RC` 会检测到当前没有 `pod` 匹配它的标签选择器, 就会创建新的实例.

如果可以接收短暂的服务不可用, 那这将是最简单的更新一组 `pod` 的方法.

## 先创建新的再删除旧版本

### 立即切换

`pod` 通常通过 `Service` 来暴露, 在运行新版本的之前, `Service` 只将流量切到旧版本. 新版本的 `pod` 创建并正常运行之后, 就可以修改服务的标签选择器将其切换到新的 `pod`. 一旦确定了新版本的功能运行正常, 就可以通过删除旧的 `RC` 来删除旧版本的 `pod`.

![](assert/Pasted%20image%2020220711151048.png)

### 滚动升级

逐步对旧版本的 `RC` 进行缩容并对新版本进行扩容来实现. 在这个过程中, 希望服务的 `pod` 选择器同时包含新旧两个版本的 `pod`, 因此它将请求切换到这两组 `pod`.

![](assert/Pasted%20image%2020220711151324.png)

手动执行滚动升级繁琐且容易出错. `kubernetes` 可以实现仅仅通过一个命令来执行.

# 使用 `RC` 实现自动的滚动升级

```yaml
apiVersion: v1  
kind: ReplicationController  
metadata:  
  name: kubia-v1  
spec:  
  replicas: 3  
  template:  
    metadata:  
      name: kubia  
      labels:  
        app: kubia  
    spec:  
      containers:  
        - name: nodejs  
          image: luksa/kubia:v1  
---  
apiVersion: v1  
kind: Service  
metadata:  
  name: kubia  
spec:  
  selector:  
    app: kubia  
  ports:  
    - port: 80  
      targetPort: 8080
```

> 使用同样的 `tag` 推送更新过后的镜像需要将容器的 `imagePullPolicy` 设置为 `Always`.
> 如果容器使用的 `tag` 为 `latest`, 则默认为 `Always`, 否则是 `IfNotPresent`.

```bash
# 请求nodejs服务器
while true; do curl http://xx.xx:xxxx; done
This is vl running in pod kubia-vl-qrl92
```

## 使用 `kubectl` 滚动升级

```bash
# rolling-update已经过时
kubectl rolling-update kubia-v1 kubia-v2 --image=luksa/kubia:v2
```

![](assert/Pasted%20image%2020220711152312.png)

```
# 查看v2的描述
kubectl describe rc kubia-v2
```

`kubectl` 通过复制 `kubia-v1` 的 `RC` 并在其 `pod` 模板中改变镜像版本. 标签选择器也会被做了修改, 除了简单的 `app=kubia` 标签, 还额外包含了 `deployment` 标签. 第一个 `RC` 的选择器也会被加上类似的 `deployment` 标签. 同时 `pod` 的标签也会对应的加上. 防止在升级过程出现问题后也删除了所有正在生产级别提供服务的 `pod`.

![](assert/Pasted%20image%2020220711152736.png)

升级过程中会渐渐扩容与缩容, 最终 `Service` 并逐渐切换到 `v2` 的 `pod`.

```text
Scaling kubia-v2 up to 1
Scaling kubia-vl down to 2
```

## 为什么 `rolling-update` 已经过时

这个过程会直接修改创建的对象. 更新 `pod` 和 `RC` 的标签并不符合之前创建时的预期. 并且这个操作是由 `kubectl` 发起 `REST` 请求执行的, 而不是由 `kubernetes master` 服务端执行, 如果执行升级时失去了网络连接, 升级进程就会中断, `pod` 和 `RC` 最终会处于中间状态.

# Deployment

`Deployment` 是一种高阶资源, 用于部署应用程序并以声明的方式升级应用, 而不是通过 `RC` 或 `RS` 部署, 这两个被认为是更底层的概念.

![](assert/Pasted%20image%2020220711153648.png)

就像滚动升级示例所示, 在升级应用过程中需要引入新的 `RS/RC` 并协调, 使它们根据彼此不断修改而不会干扰, `Deployment` 就是用来负责处理这个问题的.

```yaml
apiVersion: apps/v1  
  kind: Deployment  
  metadata:  
    name: kubia-v1  
  spec:  
    selector:  
      matchLabels:  
        app: kubia  
    replicas: 3  
    template:  
      metadata:  
        name: kubia  
        labels:  
          app: kubia  
      spec:  
        containers:  
          - name: nodejs  
            image: luksa/kubia:v1
```

```bash
kubectl create -f kubia-deployment-v1.yaml --record # record deprecated
kubectl rollout status deployment xxx # 查看部署状态
```

`Deployment` 创建了 `ReplicaSet`, `ReplicaSet` 创建 `Pod`, 它们都有各自的哈希值, `Deployment` 可能创建多个 `ReplicaSet` 用来对应和管理一个版本的 `pod` 模版, 像这样使用 `pod` 模板的哈希值可以让 `Deployment` 始终对给定版本的 `pod` 模版创建相同或使用已有的 `ReplicaSet`.

## 升级 `Deployment`

当使用 `ReplicationController` 部署应用时必须通过 `kubectl rolling-update` 显式的执行更新, 使用 `Deployment` 只需修改 `Deployment` 资源中定义的 `pod` 模版. 升级需要做的就是在不熟的 `pod` 模板中修改镜像的 `tag`.

### 不同的升级策略

* RollingUpdate
* Recreate

```yaml
kind: Deployment  
apiVersion: apps/v1  
metadata:  
  name: "hello-deployment"  
spec:  
  selector:  
    matchLabels:  
      app: "hello"  
  replicas: 3  
  minReadySeconds: 10  # 减慢升级速度以方便观察
  template:  
    metadata:  
      labels:  
        app: "hello"  
    spec:  
      containers:  
        - name: hello  
          image: hello-world:v2
```

然后执行 `kubectl apply -f ./xxx.yaml`

```bash
# 使用 kubectl rollout status 观察升级状态
k rollout status deployment hello-deployment
Waiting for deployment "hello-deployment" rollout to finish: 1 out of 3 new replicas have been updated...
Waiting for deployment "hello-deployment" rollout to finish: 1 out of 3 new replicas have been updated...
Waiting for deployment "hello-deployment" rollout to finish: 1 out of 3 new replicas have been updated...
Waiting for deployment "hello-deployment" rollout to finish: 2 out of 3 new replicas have been updated...
Waiting for deployment "hello-deployment" rollout to finish: 2 out of 3 new replicas have been updated...
Waiting for deployment "hello-deployment" rollout to finish: 2 out of 3 new replicas have been updated...
Waiting for deployment "hello-deployment" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "hello-deployment" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "hello-deployment" rollout to finish: 1 old replicas are pending termination...
deployment "hello-deployment" successfully rolled out
```

```bash
while true; do curl localhost/hello; echo \n;sleep 2; done
hello from v1:hello-deployment-78bdcf6fcb-rr8tcn
hello from v1:hello-deployment-78bdcf6fcb-rr8tcn
hello from v1:hello-deployment-78bdcf6fcb-wb6t2n
hello from v1:hello-deployment-78bdcf6fcb-wb6t2n
hello from v1:hello-deployment-78bdcf6fcb-7f9s4n
hello from v1:hello-deployment-78bdcf6fcb-wb6t2n
hello from v2:hello-deployment-55dbc89fc-whczln
hello from v1:hello-deployment-78bdcf6fcb-wb6t2n
hello from v2:hello-deployment-55dbc89fc-whczln
hello from v1:hello-deployment-78bdcf6fcb-7f9s4n
hello from v1:hello-deployment-78bdcf6fcb-wb6t2n
hello from v1:hello-deployment-78bdcf6fcb-rr8tcn
hello from v2:hello-deployment-55dbc89fc-whczln
hello from v1:hello-deployment-78bdcf6fcb-wb6t2n
hello from v2:hello-deployment-55dbc89fc-k8chwn
hello from v1:hello-deployment-78bdcf6fcb-wb6t2n
hello from v2:hello-deployment-55dbc89fc-k8chwn
hello from v1:hello-deployment-78bdcf6fcb-wb6t2n
hello from v2:hello-deployment-55dbc89fc-whczln
hello from v1:hello-deployment-78bdcf6fcb-wb6t2n
hello from v2:hello-deployment-55dbc89fc-whczln
hello from v2:hello-deployment-55dbc89fc-bvpgfn
hello from v2:hello-deployment-55dbc89fc-bvpgfn
hello from v2:hello-deployment-55dbc89fc-k8chwn
hello from v2:hello-deployment-55dbc89fc-whczln
hello from v2:hello-deployment-55dbc89fc-bvpgfn
```

| 方法 | 作用 |
| --- | --- |
| kubectl edit | 使用默认编辑器打开资源配置, 修改保存并更新对象会被更新 |
| kubectl patch | 修改单个资源属性 |
| kubectl apply | 需要包含完整定义, 不能像 `kubectl patch` 只包含想要更新的, 如果指定的对象不存在则会被创建 |
| kubectl replace | 将原有对象替换为新对象, 要求对象必须存在 |
| kubectl setimage | 修改容器内的景象 |

## `Deployment` 的优点

这个升级过程是由运行在 `kubernetes` 上的一个控制器处理和完成的, 而不再使用 `kubectl` 客户端, 更加简单可靠.

> 如果 `pod` 模板引用了一个 `ConfigMap/Secret`, 那么更改 `ConfigMap` 资源本身将不会触发升级操作. 如果真的需要修改配置触发更新的话可以创建一个新的 `ConfigMap` 并修改模板引用新的 `ConfigMap`


`Deployment` 和 `kubectl rolling-update` 的升级过程近似. 一个新的 `ReplicaSet` 被创建然后慢慢扩容, 同时之前版本的慢慢缩容至0.

与之前不同的是, 旧的 `RS` 会被保留, 而之前旧的 `RC` 会在滚动升级过程结束后被删除.

# 回滚 `Deployment

```bash
kubectl rollout undo deployment xxx
```