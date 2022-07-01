```toc
```

# 介绍 [[../kubernates_basic/2_pod|Pod]]

> 当一个 `Pod` 包含多个容器时, 这些容器总是运行在同一个工作节点上-一个`Pod` 绝不会跨越多个工作节点.

## 为什么需要 `Pod`

**为何多个容器比单个容器中包含多个进程要好**

容器被设计为每个容器只运行一个进程(除非产生了子进程). 如果在单个容器中运行多个进程, 那么保持所有进程都运行, 管理它们的日志就会是开发者的责任. 这些进程的日志都将记录在相同的标准输出中, 而此时我们将很难确定每个进程分别记录了什么.

## 了解 `Pod`

由于不能将多个进程聚集在同一个容器中, 我们需要另一种更高级的结构来将容器绑定在一起, 并将它们作为一个单元进行管理, 这就是 `Pod` 背后的原理.

在包含容器的 `Pod` 下, 我们可以同时运行一些密切相关的进程, 并为它们提供几乎相同的环境, 此时这些进程就像全部运行于单个容器中一样, 同时又保持着一定的隔离.

**同一 `Pod` 容器之间的部分隔离**

`Kubernetes` 通过配置 `CRI` 来让一个 `Pod` 内的所有容器共享相同的 `Linux` 命名空间, 而不是每个容器都有自己的一组命名空间.

一个 `Pod` 中的所有容器都在相同的 `network` `UTS` 命名空间下运行, 所以它们都共享相同的主机名和网络接口. 同样地, 这些也都在相同的 `IPC` 命名空间下运行, 因此能够通过 `IPC` 进行通信. 在新的 `Kubernetes` 中, 也能够共享相同的 `PID` 命名空间. 默认未激活.

涉及到文件系统的时候, 每个容器的文件系统与其它容器完全隔离, 可以使用名为 `Volume` 的 `Kubernetes` 资源共享文件目录.

**容器如何共享相同的 `IP` 和端口空间**

一个 `Pod` 中的容器运行与相同的 `Network` 命名空间中, 因此它们共享相同的 `IP` 地址和端口空间. 所以在同一 `Pod` 中的容器运行的多个进程不能绑定到相同的端口. 此外, 它们也可以通过 `localhost` 与同一 `Pod` 中的其它容器进行通信.

每个 `Pod` 之间分别有独立的端口空间.

**`Pod` 之间的网络**

所有 `Pod` 在同一个共享网络地址空间中, 所以它们可以通过其它 `Pod` 的 `IP` 地址来互相访问. 这也表示它们之间没有网络地址转换网关. 当两个 `Pod` 彼此之间发送网络数据包时, 它们都会将对方的实际 `IP` 地址看作数据包中的源 `IP`.

因此 `Pod` 之间的通信非常简单, 不论是在同一个节点还是不同的工作节点, 不管实际节点间的网络拓扑结构如何, 这些 `Pod` 内的容器都能像在无 `NAT` 的平坦网络中一样互相通信, 就像一个局域网一样..

## 通过 `Pod` 合理管理容器

当决定要将两个容器放入一个 `Pod` 还是两个单独的 `Pod` 时, 问自己以下问题:

* 它们需要一起运行还是在不同的主机上运行?
* 它们代表的是一个整体还是相互独立的组件?
* 它们必须一起进行扩缩容还是可以分别进行?

![[assert/Pasted image 20220701113637.png]]

容器不应该包含多个进程, `Pod` 也不应该包含多个并不需要运行在同一主机上的容器.

# 使用 `YAML` 或 `JSON` 描述文件

创建对象可以参考 [Workload Resources | Kubernetes](https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/) 中的 `API` 参考文档.

```yaml
apiVersion: v1  
kind: Pod  
metadata:  
  annotations:  
    created-by: tiandeng  
  generateName: kubia-  
  labels:  
    run: kubia  
  name: kubia-zxzij  
  namespace: default  
spec:  
  containers:  
    - name: kubia  
      image: luksa/kubia  
      ports:  
        - containerPort: 8080  
          protocol: TCP  
      resources:  
        requests:  
          cpu: 100m  
      terminationMessagePath: /dev/termination-log  
      volumeMounts:  
        - mountPath: /var/run/secrets/k8s.io/servacc  
          name: default-token-kvcqa  
          readOnly: true  
  dnsPolicy: ClusterFirst  
  nodeName: app-cluster-control-plane  
  restartPolicy: Always  
  serviceAccountName: default  
  terminationGracePeriodSeconds: 30  
  volumes:  
    - name: default-token-kvcqa  
      secret:  
        secretName: default-token-kvcqa
```

`Pod` 定义由这么几个部分组成: `YAML` 中使用的 `Kubernetes API` 版本和 `YAML` 描述的资源类型; 其次是几乎在所有资源中都可以找到的三大重要部分:

1. `metadata` 包括名称, 命名空间, 标签和关于该容器的其它信息.
2. `spec` 包含 `Pod` 内容的实际说明, 例如容器, 卷等其它数据.
3. `status` 运行中的 `Pod` 的当前信息, 不需要手动提供.

使用 `kubectl explain` 来发现可能的 `API` 对象字段

```bash
kubectl explain pod
kubectl explain pod.spec
```

## `Pod` 相关命令

```shell
# 创建
kubectl create -f xxx.yaml
# 得到运行中 pod 的完整定义
kubectl get po xxx -o yaml
kubectl get po xxx -o json
# 查看列表
kubectl get pods
# 查看日志
kubectl logs xxx
# 指定容器(pod包含多个容器的话)
kubectl logs kubia-manual -c kubia
# 如果想要在不通过 `Service` 的情况下与特定的 `Pod` 进行通信(出于调试或其它原因)
kubectl post-forward kubia-manual 8888:8080
```

## 使用标签管理

标签是可以附加到资源的任意键值对, 用以选择具有该确切标签的资源. 只要标签的 `Key` 在资源内是唯一的, 一个资源便可以拥有多个标签. 通常在创建资源的时候就会将标签添加到资源上. 也可以之后添加修改.

![[assert/Pasted image 20220701153757.png]]

### 创建时指定

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
  template:  
    metadata:  
      labels:  
        app: "hello"  
    spec:  
      containers:  
        - name: hello  
          image: hello-world:v1
```

### 标签相关命令

```bash
# 获取Pod的信息带上labels
kubectl get po --show-labels
# 获取指定label的value
kubectl get po -L hello
# 通过标签选择子集
kubectl get po -l app=hello
# 修改
kubectl label po kubia-xxx env=prod
# 修改已有标签
kubectl label po xxx env=debug --overwrite
```

### 筛选标签

```text
creation_method!=manual
env in (prod, devel)
env notin (prod,devel)
app=pc,rel=beta
```

# 使用标签和选择器来调度 `Pod`

`Pod` 实际调度到哪个节点是无关紧要的, 对某个 `pod` 而言, 获得的计算资源和从其它 `pod` 的可访问性不受 `node` 的影响, 所以一般没有任何需要指定把 `pod` 调度到哪里的需求.

有时候需要对指定工作节点有一定的要求, 比如 `gpu`, `固态`, `机械硬盘` 之类的差别.

我们不会特别说明 `pod` 应该调度到哪个节点上, 因为会将应用程序和基础架构强耦合. 应用该某种方式描述对节点的需求, 使 `kubernetes` 选择一个符合这些需求的节点. 这些是通过节点和标签选择器完成.

## 使用标签分类工作节点

我们可以在节点上添加一个 `gpu=true` 的标签

```bash
kubectl label node xxx gpu=true
kubectl get nodes -L gpu
```

然后将 `pod` 调度到特定的节点.

```yaml
apiVersion: v1
kind: Pod
metadata:
	name: kubia-gpu
spec:
	nodeSelector:
		gpu: 'true'
	containers:
	- image: luksa/kubia
	   name: kubia
```

# 注解 `Pod`

除标签外, 还可以使用注解, 注解也是键值对, 但注解并不是为了保存表示信息而存在的, 它们不能像标签一样用于对对象进行分组. 当我们可以通过标签选择器选择对象时, 就不存在注解选择器这样的东西.

注解可以容纳更多的信息, 主要用于工具使用. 大量使用注解可以为每个 `Pod` 或其它对象添加说明, 以便每个使用该集群的人都可以快速查找有关每个单独对象的信息.

## 注解相关命令

```bash
kubectl annotate pod xxx mycompany.com/xxx="foo bar"
kubectl describe pod xxx