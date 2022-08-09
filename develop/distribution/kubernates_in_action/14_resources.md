# 申请资源

```yaml
containers:
- image: xxx
    resources:
        requests:
            cpu: 200m # 1/5 core
            memory: 10Mi
```

这表示该 `pod` 所需资源最少200毫核 和 `10Mi` 的内存.

# 限制资源

```yaml
containers:
- image: xxx
    resources:
        limits:
            cpu: 200m # 1/5 core
            memory: 10Mi
```

这会限制 `pod` 使用的最大资源量.

和资源申请不同, 资源限制是可以超量的, 当资源总和超出可分配资源的时候会通过杀掉一些容器释放资源.

需要注意的是, 容器里看到的始终是节点的内存和 `CPU`, 并不是分配给它的可使用资源. 所以不要依赖于这些信息去配置应用程序使用的资源, 而是通过 `Downward API` 将 `CPU`限额传递至容器并使用这个值, 或者通过 `cgroup`系统直接获取配置的 `CPU`限制:

* `/sys/fs/cgroup/cpu/cpu.cfs_quota_us`
* `/sys/fs/cgroup/cpu/cpu.cfs_period_us`

# QoS

`kubernetes` 将 `pod` 划分为3中 `QoS` 等级来决定哪个 `pod` 在资源超量后优先被杀掉.

* BestEffort (优先级最低)
* Burstable
* Guaranteed (优先级最高)

`BestEffort` 优先级会分配给那些没有为容器设置任何 `requests` 和 `limits` 的 `pod`. `Guaranteed` 等级配置的话需要有以下几个条件:

* `CPU` 和内存都要设置 `requests` 和 `limits`
* 每个容器都需要设置资源量
* `requests` 和 `limits` 必须相等

如果 `requests` 没有显式设置, 默认与 `limits` 相等.所有只设置 `limits` 的就可以使 `pod` 的 `QoS` 等级为 `Guaranteed`. 这些 `pod` 的容器可以使用它所申请的等额资源, 但是无法消耗更多的资源.

`Burstable` 介于两者之间, 其它所有的 `pod` 都属于这个等级.

![](assert/Pasted%20image%2020220809153735.png)

## 多容器的等级

![](assert/Pasted%20image%2020220809153809.png)
## 内存不足时那个进程被杀死

`Guaranteed` 只在系统进程需要内存的时候才会被杀掉.

![](assert/Pasted%20image%2020220809154233.png)

每个运行中的进程都有一个称为 `OOM` 分数的值, 系统通过比较所有运行进程中的 `OOM` 分数来选择要杀掉的进程. 分数最高的会在等级相同的情况下优先被杀掉.

`OOM` 分数通过计算得出: 进程已消耗的内存占可用内存的百分比.

# LimitRange

可以通过创建 `LimitRange` 资源来避免必须配置每个容器. 是命名空间级别的资源.

![](assert/Pasted%20image%2020220809154810.png)

# ResourceQuota

`LimitRange` 用于限制命名空间中的所有资源的分配, 而 `ResourceQuota` 可以限制命名空间的总量.

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
    name: cpu-and-mem
spec:
    hard:
        requests.cpu: 400m
        requests.memory: 200Mi
        limits.cpu: 600m
        limits.memory: 500Mi
```

同时该资源也可以限制 `pod` 以及其他资源比如 `configMap` 的个数, `Storage`, 作用域等.

# 监控

可以通过 `heapster` 进行整个集群资源的监控.

[Heapster](https://github.com/kubernetes/heapster) 中获取, 可以搭配 `InfluxDB` 和 `Grafana` 来使用.

