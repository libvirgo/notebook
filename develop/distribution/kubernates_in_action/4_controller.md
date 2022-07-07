```toc
```
# 保持 `Pod` 健康

如果应用程序中有一个 `Bug` 每隔一段时间就会崩溃, `Kubernetes` 也会自动重启.

有时候应用程序没有崩溃也会停止工作, 例如死锁, 无限循环, 为确保应用程序这种情况下可以重新启动, 必须从外部检查应用程序的运行状况, 而不是依赖于应用的内部检测.

## 存活探针

可以通过存活探针 (`liveness probe`) 检查容器是否运行. 如果检测失败, `Kubernetes` 将定期执行探针并重新启动容器.

`Kubernetes` 有以下三种探测容器的机制:
* `HTTP GET` 探针对容器的 `IP` 地址执行 `HTTP GET` 请求, 响应码是 `2xx`, `3xx` 则认为探测成功.
* `TCP` 套接字探针尝试与容器指定端口建立 `TCP` 连接, 如果连接建立失败则重启容器.
* `Exec` 探针在容器内执行任意命令, 并检查命令的退出状态码. 如果状态码是0则探测成功, 其它的都被认为失败.

## 创建 `HTTP` 探针

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: kubia-liveness
spec:
  containers:
  - image: luksa/kubia-unhealthy
    name: kubia
    livenessProbe:
      httpGet:
        path: /
        port: 8080
```

可以通过 `kubectl logs mypod --previous` 查看上一次容器终止的日志.

可以通过 `kubectl describe` 的内容来了解为什么重启容器.

错误码137: 表示该进程由外部信号终止. 数字 137 是两个数字的总和: 128+x, 其中 `x` 是终止进程的信号编号, 比如 `SIGKILL` 就是9. 在底部的 `Events` 会显示容器会什么终止.

> 当容器被强行终止时, 会创建一个全新的容器, 而不是重启原来的容器.

## 附加属性

可以在探针添加附加信息, 比如 `timeout`, `delay`, `period`, `failure`

## 创建有效的存活探针

**应该检查什么**

简易的存活探针仅仅检查了服务器是否响应. 为了更好地进行存活检查, 需要将探针配置为请求特定的 `URL` 路径, 并让应用从内部对内部运行的所有重要组件执行状态检查, 以确保它们都没有终止或停止响应.

一定要检查应用程序的内部, 而不是外部因素的影响. 比如数据库连接失败探针不应该返回失败, 原因在数据库的话重启应用服务器不会解决问题.

**保持探针轻量**

存活探针不应该消耗太多的计算资源, 并且运行不应该花太长时间. 默认情况下, 探测器执行的频率相对较高, 必须在一秒之内执行完毕, 一个过重的探针会大大减慢容器运行.

**无须在探针中实现循环重试**

# RC

`ReplicationController` 的工作是确保 `pod` 的数量始终与其标签选择器匹配. 如果不匹配会采取适当的操作来协调 `pod` 的数量.

一个 `ReplicationController` 有三个主要部分
* `label selector`
* `replica count`
* `pod template`

使用 `RC` 的好处

* 确保一个 `pod` 持续运行
* 集群节点故障时, 将为故障节点上运行的所有 `pod` 创建替代副本
* 轻松实现 `pod` 的水平伸缩

> `pod` 实例不会被重新安置到另一个节点. `RC` 会创建一个全新的 `pod` 实例, 与正在替换的实例无关.

```yaml
kind: ReplicationController
apiVersion: v1  
metadata:  
  name: "hello-rp"  
spec:  
  selector:  
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

> 定义的时候不要指定 `pod` 选择器, 让它从 `pod` 模板中提取, 这样可以让 `yaml` 更简洁

## 将 `pod` 移入或移出 `RC` 作用域

由 `RC` 创建的 `pod` 并不是跟 `RC` 绑定的, 可以通过更改 `pod` 的标签, 将它从 `RC` 的作用域中添加或删除. 也可以从一个移动到另一个.

## 修改模板

```bash
kubectl edit rc xxx
# 修改默认编辑器
export KUBE_EDITOR=/usr/bin/nano
```

也可以在文件中修改然后使用 `kubectl apply -f xxx.yaml`.

## 水平缩放

```bash
kubectl scale rc hello --replicas=10
kubectl edit rc xxx # 修改 replicas 行
```

## 删除 `RC`

```bash
# 删除RC并保持pod的运行
kubectl delete rc xxx --cascade=false
```

# RS

**使用 `RS` 而不是 `RC`**

最初, `RC` 是用于复制和在异常时重新调度节点的唯一 `kubernetes` 组件, 后面又引入了 `ReplicaSet` 的类似资源, 它是新一代的 `ReplicationController`.

通常不会直接创建它们, 而是在创建更高层级的 `Deployment` 时自动创建

## 比较 `RC` 和 `RS`

`RS` 的行为和 `RC` 完全相同, 但 `pod` 选择器的表达能力更强. `RC` 的只允许包含某个标签的匹配 `pod`, 但 `RS` 还允许匹配缺少某个标签的 `pod` 或包含特定标签名的 `pod`, 不管其值.

## 定义 `RS`

```yaml
kind: ReplicaSet
apiVersion: apps/v1  
metadata:  
  name: "hello-rp"  
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

## 更富表达力的标签选择器

```yaml
selector:
  matchExpressions:
    - key: app
      operator: In
      values:
        - kubia
```

有四个有效的运算符:
1. In: 必须与其中一个指定的匹配
2. NotIn: 与任何指定的都不匹配
3. Exists: 包含一个指定的标签名, 不指定 `values`
4. DoesNotExist: 与 `Exists` 相反

# DaemonSet

`RS` 和 `RC` 用于在集群上运行部署特定数量的 `pod`. 当希望 `pod` 在集群中的每个节点运行时(并且每个节点都需要正好一个).

这些情况包括 `pod` 执行系统级别的与基础结构相关的操作. 例如希望在每个节点上运行日志收集器和资源监控器. 另一个例子是 `kubernetes` 自己的 `kube-proxy` 进程, 它需要运行在所有节点才能工作.

`DaemonSet` 在每个节点上只运行一个 `pod` 副本, 而 `RS` 则将它们随机地分布在整个集群中.

`DS` 没有副本数的概念, 它的工作是确保一个集群上有一个健康的 `pod`. 如果一个节点下线, `DS` 不会在其它地方重新创建, 但是将一个新节点添加到集群中时, `DS` 会立即部署一个新的 `pod` 实例.

## 配置模板

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: ssd-monitor
spec:
  selector:
    matchLabels:
      app: ssd-monitor
  template:
    metadata:
      labels:
        app: ssd-monitor
    spec:
      nodeSelector:
        disk: ssd
      containers:
        - name: main
          image: luksa/ssd-monitor
```

该实例将在每个具有 `disk=ssd` 标签的节点上创建.

```bash
kubectl label node app-cluster disk=ssd
```

# Job

`Job` 允许运行一种 `pod`, 该 `pod` 在内部进程成功结束时, 不重启容器. 一旦任务完成, `pod` 就被认为处于完成状态.

`Job` 对于临时任务很有用, 关键是任务要以正确的方式结束. 可以在未使用 `job` 托管的 `pod` 中运行任务并等待它完成, 但是如果发生节点异常或在执行任务的时候被从节点中逐出, 就需要重新创建该任务. 手动做这件事并不合理, 特别是任务可能需要几个小时完成.

![job](assert/Pasted%20image%2020220704175301.png)

## 定义 `Job`

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: batch-job
spec:
  template:
    metadata:
      labels:
        app: batch-job
    spec:
      restartPolicy: OnFailure
      containers:
      - name: main
        image: luksa/batch-job
```

```bash
kubectl logs batch-job-xxx
kubectl get job
```

## 顺序运行 `Job`

可以设定一个 `Job` 运行多少次. `completions` 将使作业顺序运行 `n` 次. `Job` 将一个接一个地运行, 运行完成后创建下一个.

## 并行运行 `Job`

同时运行多个 `Pod` 使用 `parallelism` 配置属性

## 配置属性

```yaml
spec:
  completions: 5 # 需要完成pod的数量
  parallelism: 2 # 可以同时运行的pod数量
  activeDeadlineSeconds: 1 # 限制pod完成的时间
  backoffLimit: 6 # pod被标记为失败之前可以重试的次数
```

# CronJob

`CronJob` 可以再特定的时间或者指定的时间间隔内重复运行.

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: batch-job-every-fifteen-minutes
spec:
  schedule: "0,15,30,45 * * * *"
  jobTemplate:
    spec:
      template:
        metadata:
          labels:
            app: periodic-batch-job
        spec:
          restartPolicy: OnFailure
          containers:
            - name: main
              image: luksa/batch-job
```

时间表从左到右包含以下五个条目:
* 分钟
* 小时
* 每月中的第几天
* 月
* 星期几

比如:

```bash
# 每月的第一天每隔30分钟
0, 30 * 1 * *
# 每个星期天的3AM
0 3 * * 0
```

## 配置属性

```yaml
spec:
	schedule: "0, 15, 30, 45 * * * *"
	startingDeadlineSeconds: 15 # 最迟必须在预定时间后15秒开始运行
```
