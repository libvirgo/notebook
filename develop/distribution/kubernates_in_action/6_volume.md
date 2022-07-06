# 介绍卷

卷被绑定到 `pod` 的生命周期中, 只有在 `pod` 存在时才会存在, 可以通过挂载卷的方式让不同的容器访问相同的文件, 即使在 `pod` 和卷消失之后, 卷的文件也可能保持原样, 并可以挂载到新的卷中.


![](assert/Pasted%20image%2020220705172157.png)

## 可用的卷类型

* `emptyDir` :: 用于存储临时数据的简单空目录.
* `hostPath` :: 用于将目录从工作节点都文件系统挂载到 `pod`
* `gitRepo` :: 通过检出 `git` 仓库的内容来初始化的卷
* `nfs` :: 挂载到 `pod` 中的 `NFS` 共享卷
* `gcdPersistentDisk`, `awsElasticBlockStore`, `azureDisk` :: 用于挂载云服务商提供的特定存储类型
* `cinder`, `cephfs`, `iscsi`, `flocker`, `glusterfs`, `quobyte`, `rbd`, `flexVolume`, `vsphere-Volume`, `photonPersistentDisk`, `scaleIO` :: 用于挂载其它类型的网络存储
* `configMap`, `secret`, `downwardAPI` :: 用于将 `kubernetes` 部分资源和集群信息公开给 `pod` 的特殊类型的卷
* `persistentVolumeClaim` :: 使用预置或动态配置的持久存储类型.

# 通过卷共享

## emptyDir

```yaml
kind: Pod
metadata:
	name: fortune
spec:
	containers:
	- image: luksa/fortune
       name: html-generator
       volumeMounts:
	       - name: html
	          mountPath: /var/htdocs
	- image: nginx:alpine
	   name: web-server
	   volumeMounts:
		   - name: html
		      mountPath: /usr/share/nginx/html # 将上面相同的卷挂载在容器的 /usr/share/nginx/html 目录下
		      readOnly: true
	   ports:
	   - containerPort: 80
	      protocol: TCP
	volumes:
	- name: html
	   emptyDir: {}
```

`emptyDir` 默认使用承载 `pod` 的工作节点的实际磁盘上创建的, 但我们可以通知 `Kubernetes` 在内存而不是磁盘上创建.

```yaml
volumes:
  - name: html
     emptyDir:
       medium: Memory
```

其它类型的卷都是在它的基础上构建的, 在创建空目录后, 它们会用数据填充它.

## gitRepo

`gitRepo` 卷基本上也是一个 `emptyDir`, 但是它通过克隆 `git` 仓库并在 `pod` 启动时(但在创建容器之前)检出特定版本来填充数据.

![](assert/Pasted%20image%2020220705173843.png)

> 它并不能和对应的 `repo` 保持同步, 只有在删除新建的时候会包含最新的提交

```yaml
volumes:
	- name: html
	   gitRepo:
		   repository: https://github.com/example/example.git
		   revision: master
		   directory: . # 克隆到卷的根目录
```

通常这种卷应该使用 `sidecar` 容器, 可以在 `docker hub` 上寻找 `git sync` 镜像来作为 `pod` 的 `sidecar` 容器, 而不是将同步逻辑放到主容器中.

### 访问工作节点文件系统上的文件

## hostPath

`hostPath` 指向节点文件系统上的特定文件或目录, 在同一个节点上运行并使用相同路径 `hostPath` 卷的 `pod` 可以看到相同的文件.

![](assert/Pasted%20image%2020220705180048.png)

`hostPath` 是持久性存储, 即使 `pod` 删除, `hostPath` 卷的内容也不会被删除.

如果考虑使用 `hostPath` 卷作为存储数据库数据的目录, 需要重新考虑. 因为卷的内容存储在特定节点的文件系统中, 所以当数据库 `pod` 被重新安排在另一个节点时, 会找不到数据. 在常规 `pod` 使用 `hostPath` 卷不是一个好主意, 这会使 `pod` 对预定规划的节点敏感.

> 仅当需要在节点上读取或写入系统文件的时候使用 `hostPath`, 不要用它们来持久化跨 `pod` 的数据.

# 使用持久化存储

## `GCE` 持久磁盘

## `AWS` 弹性存储卷

## NFS

```yaml
volumes:
- name: mongodb-data
   nfs:
	   server: 10.1.2.105
	   path: /Users/test/.local/nfs/db/mongodb
```

# 从底层存储技术解耦 `pod`

到目前为止, 探索过的所有持久卷类型都要求 `pod` 的开发人员了解集群中可用的真实网络存储的基础架构. 例如, 要创建支持 `NFS` 协议的卷, 开发人员必须知道 `NFS` 节点所在的实际服务器. 这违背了 `kubernetes` 的基本理念, 这个理念旨在向应用程序及其开发人员隐藏真实的基础设施, 使它们不必担心基础设施的具体状态, 并使应用程序可在大量云服务商和数据企业之间进行功能迁移.

理想的情况下, 在 `kubernetes` 部署应用程序的开发人员不需要知道底层使用的是哪种存储技术, 同理他们也不需要了解应该使用哪些类型的物理服务器来运行 `pod`.

当开发人员需要一定数量的持久化存储来进行应用时, 可以向 `kubernetes` 请求, 就像在创建 `pod` 时可以请求 `cpu`, 内存和其它资源一样. 系统管理员可以对集群进行配置让其可以为应用程序提供所需的服务.

## 持久卷和持久卷声明

为了在集群中使应用正常请求存储资源, 同时避免处理基础设施细节, 引入了这两个新资源.

研发人员无须向他们的 `pod` 中添加特定技术的卷, 而是由集群管理员设置底层存储, 然后通过 `kubernetes API` 创建持久卷并注册. 在创建持久卷时, 管理员可以指定大小和支持的访问模式.

用户需要持久化存储时, 他们首先创建持久卷声明(`PersistentVolumeClaim PVC`)清单, 指定所需要的最低容量要求和访问模式, 然后提交给 `API` 服务器, `kubernetes`将找到可匹配的持久卷并将其绑定到持久卷声明.

持久卷声明可以当做 `pod` 中的一个卷来使用, 其它用户不能使用相同的持久卷, 除非释放掉.

![](assert/Pasted%20image%2020220705183445.png)
