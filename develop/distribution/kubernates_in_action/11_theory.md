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
