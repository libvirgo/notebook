```toc
```

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

## 创建持久卷

```yaml
apiVersion: v1  
kind: PersistentVolume  
metadata:  
  name: redis-pv  
spec:  
  capacity:  
    storage: 2Gi  
  accessModes:  
    - ReadWriteMany  
  persistentVolumeReclaimPolicy: Retain  
  nfs:  
    path: "${HOME}/.local/nfs" # envsubst < pvc.yml  
    server: "host.docker.internal" 
```

## 创建持久卷声明

```yaml
apiVersion: v1  
kind: PersistentVolumeClaim  
metadata:  
  name: redis-pvc  
spec:  
  accessModes:  
    - ReadWriteMany  
  resources:  
    requests:  
      storage: 1Gi  
  storageClassName: "" # 这里指定空字符串可以确保PVC绑定到预先配置的PV, 而不是动态配置新的PV
```

## 测试持久卷

```yaml
apiVersion: v1  
kind: Pod  
metadata:  
  name: redis-test  
spec:  
  containers:  
    - name: redis-pvc  
      image: busybox:stable  
      command:  
        - "/bin/sh"  
      args:  
        - "-c"  
        - "touch /mnt/Success && exit 0 || exit 1"  
      volumeMounts:  
        - mountPath: "/mnt"  
           name: redis-test  
           subPath: "redis-test" # 可以在多个pod中引用同一个claim并分开它们的数据目录.
  restartPolicy: Never  
  volumes:  
    - name: redis-test  
      persistentVolumeClaim:  
        claimName: redis-pvc
```

使用这种间接方法从基础设施获取存储, 对于应用程序开发人员来说更加简单. 虽然这需要额外的步骤创建持久卷和持久卷声明, 但是研发人员不需要关心底层实际使用的存储技术.

![](assert/Pasted%20image%2020220706164145.png)

持久卷回收策略有如下几种:

* `Retain` :: 在创建持久卷后将其持久化, 让 `kubernetes` 可以在持久卷从持久卷声明中释放后仍然能保留它的卷和数据内容. 这是手动方式, 唯一可以使其恢复可用的方法是删除和重新创建持久卷资源. 可以自己决定如何处理底层存储中的文件, 删除或者闲置, 闲置以便在下一个 `pod` 中复用.
* `Recycle` :: 删除卷的内容并使卷可用于再次声明 :: 已经废弃, 被建议使用 `dynamic provisioning`
* `Delete` :: 删除底层存储

# 动态配置持久卷

## StorageClass

使用持久卷和持久卷声明可以轻松获得持久化存储资源, 但这仍然需要一个集群管理员来支持实际的存储. `kubernetes` 还可以通过动态配置持久卷来自动执行此任务.

与管理员预先提供一组持久卷不同, 它们需要定义一个或多个 `StorageClass`, 并允许系统在每次通过持久卷声明请求时创建一个新的持久卷. 最重要的是, 不可能耗尽持久卷(但是可以用完存储空间)

## 在 `kind` 中使用 `NFS` 作为 `StorageClass`

1. 在 `mac` 上启动 `nfs` 服务器

```text
# /etc/exports
$HOME/.local/share/nfs -alldirs -maproot=501:20 -network=192.168.0.0 -mask=255.255.0.0
$HOME/.local/share/nfs -alldirs -maproot=501:20 localhost

# /etc/nfs.conf
nfs.server.mount.require_resv_port = 0
```

```bash
sudo nfsd restart
sudo nfsd status
showmount -e
```

2. 使用 [nfs-subdir-external-provisioner](https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner) 作为 `provisioner`

	根据文档创建对应的文件

```yaml
# kustomization.yaml
namespace: nfs-provisioner
resources:
  - github.com/kubernetes-sigs/nfs-subdir-external-provisioner//deploy
  - namespace.yaml
patchesStrategicMerge:
  - patch_nfs_details.yaml
# namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: nfs-provisioner
# patch_nfs_detail.tmpl
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: nfs-client-provisioner
  name: nfs-client-provisioner
spec:
  template:
    spec:
      containers:
        - name: nfs-client-provisioner
          env:
            - name: NFS_SERVER
              value: 192.168.0.100
            - name: NFS_PATH
              value: ${HOME}/.local/share/nfs
      volumes:
        - name: nfs-client-root
          nfs:
            server: 192.168.0.100
            path: ${HOME}/.local/share/nfs
```

```bash
# 先根据环境变量使用envsubst生成最终的yaml文件
for f in *.tmpl; do envsubst < $f > "$(basename -s .tmpl $f).yaml"; done
# 使用kustomization来部署provisioner
kubectl apply -k .
# 用于测试
kubectl create -f https://raw.githubusercontent.com/kubernetes-sigs/nfs-subdir-external-provisioner/master/deploy/test-claim.yaml -f https://raw.githubusercontent.com/kubernetes-sigs/nfs-subdir-external-provisioner/master/deploy/test-pod.yaml
```

3. 使用持久卷声明请求特定存储类

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
    name: test-claim
spec:
    storageClassName: nfs-client
    resources:
        requests:
            storage: 100Mi
    accessModes:
        - ReadWriteMany
```

![](assert/Pasted%20image%2020220707010210.png)
