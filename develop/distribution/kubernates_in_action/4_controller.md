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

