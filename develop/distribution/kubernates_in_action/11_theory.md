```toc
```

# 架构

**控制平面的组件**

* `etcd` 分布式持久化存储
* `API` 服务器
* 调度器
* 控制器管理器

**工作节点上的组件**

* `kubelet`
* `kube-proxy`
* 容器运行时(`Docker`, `Containerd`)

**附加组件**

* `Kubernetes DNS` 服务器
* 仪表板
* `Ingress` 控制器
* `Heapster` 容器集群监控
* 容器网络接口插件

## 组件的分布式特性

![](assert/Pasted%20image%2020220720185719.png)

## 组件间通信

组件间只能通过 `API` 服务器通信, 之间不会直接通信, `API` 服务器是和 `etcd` 通信的唯一组件.

`API` 服务器和其他组件的连接基本都是由组件发起的. 不过当使用 `kubectl` 获取日志, `kubectl attach` 连接到一个运行中的容器, 或运行 `kubectl port-forward` 命令时, `API` 服务器会向 `kubelet` 发起连接.

## 单组件运行多实例

控制平面的组件可以被简单地分割在多台服务器上. 为了保证高可用性, 控制平面的每个组件可以有多个实例. `etcd` 和 `API` 服务器的多个实例可以同时并行工作, 但是调度器和控制器管理器在给定时间内只能有一个实例起作用, 其它实例处于待命模式.

## 组件是如何运行的

控制平面的组件以及 `kube-proxy` 可以直接部署在系统上或者作为 `pod` 来运行.

`kubelet` 是唯一一直作为常规系统组件来运行的组件, 它把其它组件作为 `pod` 来运行. 为了将控制平面作为 `pod` 来运行, `kubelet` 被部署在 `master` 上.

## 获取集群中的系统组件

```bash
kg po -o custom-columns=POD:metadata.name,NODE:spec.nodeName --sort-by spec.nodeName -n kube-system
```

## `API` 服务器做了什么

除了提供一种一致的方式将对象存储到 `etcd` 中, 也对这些对象做校验, 这样客户端就无法存入非法的对象了. 除了校验, 还会处理乐观锁. 这样对于并发更新的情况, 对对象做更改就不会被其他客户端覆盖.

![](assert/Pasted%20image%2020220725173828.png)

`API` 服务器没有做其他额外的工作. 例如当创建一个 `RS` 资源时, 它不会去创建 `pod`, 同时它不会去管理服务的端点, 那是控制器管理器的工作.

`API` 服务器也没有告诉控制器去做什么.

运作方式是客户端通过创建到 `API` 服务器的 `HTTP` 连接来监听变更. 通过此连接, 客户端会接收到监听对象的一系列变更通知. 每当更新对象, 服务器把新版本对象发送至所有监听该对象的客户端.

![](assert/Pasted%20image%2020220725174313.png)

`kubectl` 工具作为客户端之一, 也可以通过在命令行添加 `--watch` 标志来监听资源.

## 调度器

调度器会查找可用节点来决定 `pod` 分配到哪里:

* 节点是否满足硬件资源的请求.
* 节点是否耗尽资源.
* `pod` 是否要求被调度到指定节点, 是否是当前节点.
* 节点是否有和 `pod` 规格定义里的节点选择器一致的标签.
* 如果 `pod` 要求绑定指定的主机端口, 那么这个节点上的这个端口是否已经被占用.
* 如果 `pod` 要求有特定类型的卷, 那么该节点是否能为此 `pod` 加载此卷. 或者说该节点上是否已经有 `pod` 在使用该卷了.
* `pod` 是否能够容忍节点的污点.
* `pod` 是否定义了节点, `pod` 的亲缘性以及非亲缘性规则.

所有这些测试都通过后, 节点才有资格调度给 `pod`. 得到一个符合要求的所有集后会循环调度到这些节点上保持平衡.

假设一个 `pod` 有多个副本, 理想情况下这些副本应该分散在尽可能多的节点上. 默认情况下同属同一服务和 `RS` 的 `pod` 会分散在多个节点上. 但不保证每次都是这样. 不过可以通过定义 `pod` 的亲缘性, 非亲缘性规则强制 `pod` 分散在集群内或者集中在一起.

## 控制器

控制器管理器负责确保系统真实状态朝 `API` 服务器定义的期望的状态收敛. 单个控制器, 管理器进程组合了多个执行不同非冲突任务的控制器. 这些控制器会被分解到不同的进程, 有需要的话我们也可以用自定义的实现去替换它们. 包括:

* `Replication` 控制器
* `ReplicaSet`, `DaemonSet`, `Job` 控制器
* `Deployment`
* `StatefulSet`
* `Node`
* `Service`
* `Endpoints`
* `Namespace`
* `PersistentVolume`
* 其他

控制器通过 `API` 服务器监听资源变更, 并且不论是创建更新删除已有对象, 都变更执行相应操作. 大多数情况下, 这些操作涵盖了新建其他资源或者更新监听的资源本身.

总的来说, 控制器执行一个调和循环, 将实际状态调整为期望状态, 然后将新的实际状态写入资源的 `status` 部分, 控制器利用监听机制来变更订阅, 但是由于监听机制并不保证控制器不会漏掉时间, 所以仍然需要定期执行重列举操作来确保不会丢掉什么.

> 控制器的源码 [controller](https://github.com/kubernetes/kubernetes/blob/master/pkg/controller) 每个控制器一般有一个构造器, 内部会创建一个 `Informer`, 其实是个监听器, 每次 `API` 对象有更新就会被调用. 接下来是 `worker()` 方法, 每次控制器工作的时候都会调用. 实际的函数保存在 `syncHandler` 或类似的字段中, 该字段也在构造器里初始化, 可以在那里找到被调用函数名.

### RC控制器

`Rc` 实际上不会去运行 `pod`, 它会创建新的 `pod` 清单, 发布到 `API` 服务器, 让调度器以及 `kubelet` 来做调度工作并运行 `pod`

![](assert/Pasted%20image%2020220729142606.png)
### `Endpoint` 控制器

控制器同时监听了 `Service` 和 `pod`, 控制器会选 `Service` 里 `pod` 选择器匹配的 `pod` 将其 `ip` 和端口添加到 `endpoint` 资源中. 当删除 `Service` 时, `Endpoint` 对象也会被删除.

![](assert/Pasted%20image%2020220729150736.png)
## Kubelet

`Kubelet` 以及 `Service Proxy` 运行在工作节点上(实际 `pod` 容器运行的地方).

`Kubelet` 是负责所有运行在工作节点上内容的组件, 第一个任务就是在 `API` 服务器中创建一个 `Node` 资源来注册该节点, 然后需要持续监控 `API` 服务器是否把该节点分配给 `pod`, 然后启动 `pod` 容器. 具体实现方式是告知配置好的 `CRI` 来从特定镜像运行容器, 随后持续监控运行的容器, 向 `API` 服务器报告它们的状态, 事件和资源消耗.

尽管 `Kubelet` 一般会和 `API` 服务器通信并从中获取 `pod` 清单, 它也可以基于本地指定目录下的 `pod` 清单来运行 `pod`, 该特性用于将容器化版本的控制平面组件以 `pod` 形式运行.

![](assert/Pasted%20image%2020220729151317.png)
也可以同样的方式运行自定义的系统容器, 不过一般用 `DaemonSet` 来做这项工作.

## Service Proxy

`kube-proxy` 最初实现为 `userspace` 代理, 利用实际的服务器集成接收连接, 同时代理给 `pod`, 为了拦截发往服务 `ip` 的连接, 代理通过 `iptables` 规则重定向连接到代理服务器.


![](assert/Pasted%20image%2020220729153111.png)

不过当前性能更好的实现方式是仅仅通过 `iptables` 规则重定向数据包到一个随机选择的后端 `pod`, 而不会传递到一个实际的代理服务器. 如图:

![](assert/Pasted%20image%2020220729153214.png)

## 插件

除了核心组件, 也有一些不是必须的组件, 比如用于启用 `kubernetes` 服务的 `DNS` 查询, 通过单个外部 `IP` 地址暴露多个 `HTTP` 服务, 仪表板等.

### `DNS` 服务器

`DNS` 服务 `pod` 通过 `kube-dns` 服务对外暴露, 使得该 `pod` 能够像其它 `pod` 一样在集群中移动, 服务的 `IP` 地址在集群每个容器的 `/etc/reslv.conf` 文件的 `nameserver` 中定义,  `kube-dns` `pod` 利用 `API` 服务器的监控机制订阅 `Service` 和 `Endpoint` 的变动, 以及 `DNS` 记录的变更, 使得其客户端总是能够获取到最新的 `DNS` 信息. 当然在发生变化都收到订阅通知时间点之间, `DNS` 可能会无效.

# 控制器如何协作

`Kubernetes` 组件通过 `API` 服务器监听 `API` 对象:

![](assert/Pasted%20image%2020220729153939.png)

`Deployment` 资源提交到 `API` 服务器的事件链:

![](assert/Pasted%20image%2020220729154033.png)
1. `Deployment` 生成 `RS`
2. `RS` 创建 `pod`
3. 调度器分配节点给新创建的 `pod`
4. 