本章将会介绍如何运行 `pod` 访问所在宿主节点的资源, 并且如何配置集群可以使用户不能通过 `pod` 在集群中为所欲为. 还有保障 `pod` 间通信的网络的安全.

# 在 `pod` 中使用宿主节点的 `linux` 命名空间

`pod` 中的容器通常在分开的 `linux` 命名空间中运行, 这些命名空间将容器中的进程与其他容器中或者宿主机命名空间中的进程隔离开.

部分 `pod` 需要在宿主节点的默认命名空间中运行, 以允许它们看到和操作节点级别的资源和设备.

## 使用宿主节点的网络命名空间

可以通过将 `pod spec` 中的 `hostNetwork` 设置为 `true` 实现.

通过配置 `spec.containers.ports` 字段将某端口绑定到宿主节点的端口上. 这与 `NodePort` 服务不同.

![](assert/Pasted%20image%2020220804171034.png)

* `hostPort` 的 `pod` 到达宿主节点的端口会被直接转发到 `pod` 的对应端口上, 而 `NodePort` 服务到达宿主节点的端口的连接将被转发到随机选取的 `pod` 上.
* `hostPort` 的 `pod` 仅有运行了这类 `pod` 的节点会绑定对应的端口, 而 `NodePort` 类型的服务会在所有的节点上绑定端口, 即使这个节点上没有运行对应的 `pod`.
* `hostPort` 的 `pod` 在每个宿主机上只能有一个实例, 因为两个进程不能绑定宿主机上的同一个端口. 如果要在3个节点上部署4个这样的 `pod` 副本, 只有3个副本能够成功部署.

![](assert/Pasted%20image%2020220804171302.png)

如果需要和宿主机间的进程进行 `IPC` 通信的话需要设置 `hostIPC` 为 `true`.

# 配置节点的安全上下文

除了让 `pod` 使用宿主节点的 `linux` 命名空间, 还可以通过 `security-Context` 选项配置其他安全性相关的特性.

* 指定容器中运行进程的用户
* 阻止容器使用 `root` 用户运行
* 使用特权模式运行容器
* 与以上相反, 通过添加或禁用内核功能, 配置细粒度的内核访问权限
* 设置 `SELinux`
* 阻止进程写入容器的根文件系统

## 使用指定用户运行容器

```yaml
spec:
    containers:
    - name: main
       securityContext:
           runAsUser: 405 # 需要指明一个用户ID而不是用户名, 405对应guest用户
```

## 阻止以 `root` 运行

```yaml
spec:
    containers:
    - name: main
       securityContext:
           runAsNonRoot: true
```

## 使用特权模式

```yaml
privileged: true
```

特权模式的 `pod` 可以看到宿主节点上的所有设备, 这意味着它可以自由使用任何设备.

## 添加内核功能

默认情况下不允许 `pod` 修改系统时间, 可以通过添加内核功能来实现.

```yaml
securityContext:
    capabilities:
        add:
        - SYS_TIME
```

> 内核功能的名称通常以 `CAP_` 开头, 但在 `pod spec` 中指定的时候必须省略.

> 修改时间可能会导致节点不可用.

## 禁用内核功能

默认情况下容器拥有 `CAP_CHOWN` 权限, 允许进程修改文件系统中文件的所有者.

```yaml
capabilities:
    drop:
    - CHOWN
```

禁用后, 不允许在这个 `pod` 中修改文件所有者.

## 组织对容器根文件系统的写入

```yaml
securityContext:
    readOnlyRootFilesystem: true
volumeMounts:
- name: my-volume # 允许向/volume写入
    mountPath: /volume
    readOnly: false
```

以上都是对单独的容器设置安全上下文. 也可以从 `pod` 级别设置, 不过会被容器级别的安全上下文覆盖.

## 使用不同用户运行共享存储卷

可以通过以下两个属性设置:

* fsGroup
* supplementalGroups

```yaml
spec:
    securityContext:
        fsGroup: 555
        supplementalGroups: [666, 777]
    containers:
    - name: first
        securityContext:
            runAsUser: 1111
        volumeMounts:
        - name: shared-volume
            mountPath: /volume
            readOnly: false
    - name: second:
        securityContext:
            runAsUser: 2222
        volumeMounts:
        - name: shared-volume
            mountPath: /volume
            readOnly: false
    volumes:
    - name: shared-volume
        emptyDir:
```

这个 `pod` 运行在 `ID` 为1111的用户下, 用户组为 `root`, 但用户组 `555`, `666`, `777` 也关联到了该用户下.

在 `pod` 的定义中, 将 `fsGroup` 设置成了 `555`, 因此存储卷属于用户组 `ID` 为555的用户组.

`fsGroup` 属性当进程在存储卷中创建文件时起作用, 而 `supplementalGroups` 属性定义了某个用户所关联的额外的用户组.

# 限制 `pod` 使用安全相关的特性

> `PodSecurityPolicy` 已经被废弃

集群管理人员可以通过创建 `PodSecurityPolicy` 资源来限制对上面提到的安全相关的特性的使用.

`podSecurityPolicy` 是一种集群级别(无命名空间)的资源, 它定义了用户能否在 `pod` 中使用各种安全相关的特性.

当有人向 `API` 服务器发送 `pod` 资源时, `PodSecurityPolicy` 准入控制插件会将这个 `pod` 与已经配置的 `PodSecurityPolicy` 进行校验, 如果这个 `pod` 符合安全策略, 就会被接收并存入 `etcd`, 否则会立即被拒绝.

# 隔离 `pod` 的网络

使用 `NetworkPolicy`

允许 `app=shopping-cart` 标签的并且来自 `tenant=manning` 标签的命名空间中的 `pod` 访问80端口.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
    name: shoppingcart-netpolicy
spec:
    podSelector:
        matchLabels:
            app: shopping-cart
        ingress:
        - from:
            - namespaceSelector:
                matchLabels:
                    tenant: manning
            ports:
            - port: 80
```

![](assert/Pasted%20image%2020220809151256.png)

