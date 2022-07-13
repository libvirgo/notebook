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

