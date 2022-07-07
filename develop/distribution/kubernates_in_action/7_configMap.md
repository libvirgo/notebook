```toc
```

# 配置应用程序

以下方法均可被用作配置应用程序:

* 向容器传递命令行参数
* 为每个容器设置自定义环境变量
* 通过特殊类型的卷将配置文件挂载到容器中

# 向容器传递命令行参数

了解 `ENTRYPOINT` 和 `CMD`

* `ENTRYPOINT` 定义容器启动时被调用的可执行程序
* `CMD` 指定传递给 `ENTRYPOINT` 的参数

尽管可以直接使用 `CMD` 指令指定镜像运行时想要执行的命令, 正确的做法依旧是借助 `ENTRYPOINT` 指令, 仅仅用 `CMD` 指定所需的默认参数, 这样镜像可以直接运行无须任何参数, 或者自己添加参数覆盖 `CMD` 指定的默认参数值.

```bash
docker run <image>
docker run <image> <arguments>
```

## `shell` 形式和 `exec` 形式

* `shell` ::  `ENTRYPOINT node app.js`
* `exec` :: `ENTRYPOINT ["node", "app.js"]`

使用 `shell` 形式容器中的主进程是 `shell` 进程而不是举例中的 `node` 进程, 使用 `exec` 形式则不会有多余的 `shell` 进程.

## 在 `kubernetes` 中覆盖命令和参数

```yaml
kind: Pod
spec:
    containers:
    - image: <image>
        command: ["/bin/command"]
        args: ["arg1", "arg2", "arg3"]
```

绝大多数下只需要自定义参数, 命令一般很少被覆盖, 除非针对一些未定义的通用镜像.

> `command` 和 `args` 字段在 `pod` 创建后无法被修改

也可以使用如下方法

```yaml
args:
- foo
- bar
- "15" # 字符串无须用引号, 数值需要
```

# 环境变量

```yaml
apiVersion: v1  
kind: Pod  
spec:  
  containers:  
    - name: luksa/fortune:env  
      env:  
        - name: INTERVAL  
          value: "30"  
...
```

引用环境变量

```yaml
env:  
  - name: INTERVAL  
    value: "30"  
  - name: SECOND  
    value: "$(INTERVAL)s"
```

## 硬编码的不足

硬编码意味着需要有效区分生产与开发过程中的 `pod` 定义. 为了能在多个环境下复用 `pod` 的定义, 需要将配置从 `pod` 定义描述中解耦出来. 可以通过一种叫做 `ConfigMap` 的资源对象来完成解耦. 用 `valueFrom` 字段替代 `value` 字段使 `ConfigMap` 成为环境变量值的来源.

# ConfigMap

不管应用是如何使用 `ConfigMap` 的, 将配置存放在独立的资源对象有助于在不同环境下拥有多份同名配置清单, `pod` 是通过名称引用 `ConfigMap` 的, 因此可以在多环境下使用相同的 `pod` 定义描述, 同时保持不同的配置值以适应不同环境.

![](assert/Pasted%20image%2020220707170459.png)

# 创建 `ConfigMap`

## 使用 `kubectl`

```bash
kubectl create configmap fortune-config --from-literal=sleep-interval=25 --from-literal=foor=bar
# 也可以直接将文件内容存储为条目
kubectl create cm my-config --from-file=config-file.conf
# 或者一个目录, 仅限于文件名可以作为合法ConfigMap键名的
kubectl create cm my-config --from-file=/path/to/dir
# 多种选项混合
kubectl create configmap my-config --from-file=foo.json --from-file=bar=boobar.conf --from-file=config-opts/ --from-literal=some=thing
```

![](assert/Pasted%20image%2020220707172712.png)

# 给容器传递条目作为环境变量

```yaml
env:  
  - name: INTERVAL  
    valueFrom:  
      configMapKeyRef:  
        key: sleep-interval  
        name: fortune-config
        optional: false
```

引用不存在的 `ConfigMap` 的容器会启动失败, 当创建了这个缺失的 `ConfigMap` 后会自动启动.

> 可以标记某个配置是可选的

**一次性传递所有条目**

```yaml
spec:  
  containers:  
    - name: luksa/fortune:env  
      envFrom:  
        - prefix: CONFIG_  
          configMapRef:  
            name: my-config
```

# 作为命令行参数

```yaml
apiVersion: v1  
kind: Pod  
spec:  
  containers:  
    - name: luksa/fortune:env  
      env:  
        - name: INTERVAL  
          valueFrom:  
            configMapKeyRef:  
              key: sleep-interval  
              name: fortune-config  
              optional: false  
      args:  
        - "$(INTERVAL)"
```

# 使用 `ConfigMap` 卷将条目暴露为文件

例如 `config.toml`

```yaml
kubectl create configmap fortune-config --from-file=config.toml
```

会得到如下数据:

```text
apiVersion: v1
data:
  config.toml: |
    [server_config]
    heartbeat = 10 # 心跳检测间隔时间, 默认10秒一次
    kick_out_times = 6 # 当n次心跳检测失败时将客户端从服务列表中移除, 默认6次失败移除
    broadcast_intervals = 3 # 广播频率, 默认3秒或服务列表发生改动时广播一次

    [server_config.listener]
    ip = "239.0.0.0"
    port = 12345

    [server_config.broadcaster]
    ip = "239.0.0.0"
    port = 54321
kind: ConfigMap
metadata:
  creationTimestamp: "2022-07-07T09:40:36Z"
  name: bonfire-config
  namespace: default
  resourceVersion: "954581"
  uid: de7caafa-6d5f-4943-889e-3f7ab1916780
```

## 在卷内使用 `ConfigMap`

```yaml
apiVersion: v1  
kind: Pod  
spec:  
  containers:  
    - image: nginx:alpine  
      name: web-server  
      volumeMounts:  
        - mountPath: /etc/nginx/conf.d  
          name: config  
          readOnly: true  
  
  volumes:  
    - name: config  
      configMap:  
        name: fortune-config
```

`ConfigMap` 的所有条目会被作为文件置于指定文件夹下.

也可以通过 `items` 暴露指定的条目

```yaml
volumes:  
  - name: config  
    configMap:  
      name: fortune-config  
      items:  
        - key: my-nginx-config.conf  
          path: gzip.conf
```

> 注意, 挂载某一文件夹会隐藏容器该文件夹中原本已存在的文件

## 挂载且不隐藏其它文件

```yaml
volumeMounts:  
  - mountPath: /etc/someconfig.conf  
    name: config  
    readOnly: true  
    subPath: myconfig.conf
```

![](assert/Pasted%20image%2020220707175454.png)

## 修改 `ConfigMap`

```yaml
kubectl edit configmap fortune-config
```

最终挂载的文件也会更新, 这是通过链接符号实现的. 服务器需要自己主动监听或者重启.

> 挂载至已存在文件夹的文件不会被更新, 比如上面的部分挂载? 未验证.

> 解决方法是挂载完整卷到不同的文件夹并创建指向所需文件的符号链接, 可以在容器启动时创建或者原生创建在容器镜像中.

# 使用 `Secret`

结构与 `ConfigMap` 类似, 键值对的映射, 使用方法也与 `ConfigMap` 相同.

`kubernetes` 通过仅仅将 `Secret` 分发到需要访问 `Secret` 的 `pod` 所在的机器节点来保障其安全性. 另外, `Secret` 只会存储在节点的内存中, 永不写入物理存储.

* 采用 `ConfigMap` 存储非敏感的文本配置数据
* 采用 `Secret` 存储天生敏感的数据, 通过键来引用. 如果一个配置文件同时包含敏感数据与非敏感数据, 则该文件应该被存储在 `Secret` 中.

每个 `pod` 会挂载一个 ` /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-tpfng (ro)`

```bash
❯ k exec hello-deployment-78bdcf6fcb-8s87p -- ls /var/run/secrets/kubernetes.io/serviceaccount
ca.crt
namespace
token
```

包含了从 `pod` 内部安全访问 `kubernetes API` 服务器所需的全部信息.