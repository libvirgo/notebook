```toc
```

`pod` 通常需要对来自集群内部的其它 `pod` 以及外部的客户端请求做出响应.

`pod` 需要寻找其它 `pod` 的方法来使用其它 `pod` 提供的服务, 在没有 `kubernetes` 的世界, 系统管理员在用户端配置文件中明确指出服务的精确 `IP`地址或者主机名来配置每个客户端应用, 但是这在 `kubernetes` 中不适用, 原因如下:

* `pod` 是短暂的-它们随时会启动或者关闭.
* `kubernetes` 在 `pod` 启动前会给已经调度到节点上的 `pod` 分配 `ip` 地址, 因此客户端不能提前知道提供服务的 `pod` 的 `ip`.
* 水平伸缩意味着多个 `pod` 可能会提供相同的服务, 每个 `pod` 都有自己的 `ip`.

为了解决上述问题, `kubernetes` 提供了一种资源类型-服务(`service`).

# 介绍服务

![](assert/Pasted%20image%2020220705004108.png)
## 创建服务

```yaml
apiVersion: v1
kind: Service
metadata:
	name: kubia
spec:
	ports:
	- port: 80
	  targetPort: 808
	selector:
		app: kubia
```

也可以通过 `kubectl expose` 创建服务.

```bash
kubectl expose deployment internal-deployment --port=80 --target-port=8008 --name=internal-service
kubectl get svc
```

从内部测试集群服务

* 创建一个 `pod` 记录日志响应.
* 使用 `ssh` 远程登录到一个 `kubernetes` 节点上, 使用 `curl`.
* 通过 `kubectl exec` 在一个已经存在的 `pod` 中执行 `curl` 命令.

```bash
kubectl exec kubia-xkcj -- curl -s http://service_ip:port
```

![](assert/Pasted%20image%2020220705005647.png)

如果希望让客户端产生的所有请求都指向同一个 `pod`, 可以设置服务的 `sessionAffinity` 属性为 `ClientIP`, `None` 是默认值. `kubernetes` 仅支持这两种形式的会话亲和性服务.

同一个服务也是可以暴露多个端口的:

```yaml
spec:
	ports:
	- name: http
	  port: 80
	  targetPort: 8080
	- name: https
	  port: 443
	  targetPort: 8443
	selector:
		app: kubia
```

> 标签选择器应用于整个服务, 不能为每个端口设置不同的 `pod`. 这种情况需要创建多个服务.

## 命名端口

可以为 `pod` 的端口命名

```yaml
spec:
	containers:
		- name: kubia
		  ports:
		  - name: http
		    containerPort: 8080
		  - name: https
		    containerPort: 8443
---
spec:
	ports:
	- name: http
	  port: 80
	  targetPort: http
	- name: https
	  port: 443
	  targetPort: https
	selector:
		app: kubia
```

## 服务发现

### 环境变量

创建服务的时候, 会根据名称进行蛇形转换为环境变量, 比如 `kubia` 服务, 就会在所有 `pod` 提供两个环境变量

```bash
KUBIA_SERVICE_HOST=10.111.248.153
KUBIA_SERVICE_PORT=80
```

然后就可以通过这两条环境变量获得 `IP` 地址和端口信息.

### DNS

通过 `FQDN` 全限定域名来访问. 例如:

```text
backend-database.default.svc.cluster.local
```

`backend-database` 对应服务名称, `default` 对应命名空间, `svc.cluster.local` 是在所有集群本地服务名称中使用的可配置集群域后缀.

> 端口号依然需要, 标准的端口号可以忽略, 其它的需要从环境变量中获取.

# 连接集群外部的服务

## endpoint

服务并不是和 `pod` 直接相连的, `endpoint` 介于两者之间. `endpoint` 就是暴露一个服务的 `ip` 和端口的列表, `endpoint` 资源和其它的资源一样, 可以使用 `kubectl get endpoints` 来获取它的基本信息.

服务的 `endpoint` 与服务解耦后, 就可以分别手动配置和更新它们. 如果创建了不包含 `pod` 选择器的服务,  `kubernetes` 将不会创建 `endpoint` 资源.

要使用手动配置 `endpoint` 的方式创建服务, 需要创建服务和 `endpoint` 资源.

```yaml
# 创建没有选择器的服务
apiVersion: v1
kind: Service
metadata:
	name: external-service
spec:
	ports:
		- port: 80

```

```yaml
# 为没有选择器的服务创建 `endpoint` 资源
apiVersion: v1
kind: Endpoints
metadata:
	# 必须跟服务相同
	name: external-service
subsets:
	- addresses:
		- ip: 11.11.11.11
		- ip: 22.22.22.22
	   ports:
		   - port: 80
```

这意味着服务的 `ip` 可以保持不变, 同时服务的实际实现发生了改变.

而通过 `endpoint` 也可以将 `ip` 指向外部服务或其它集群的 `ip` 端口, 这样集群内部访问外部服务也可以使用 `external-service` 当做 `hostname` 来使用, 类似反向代理.

使用 `Service` 反向代理外部域名:

```yaml
apiVersion: v1
kind: Service
metadata:
	labels:
		app: nginx-externalname
	name: nginx-externalName
spec:
	type: ExternalName
	externalName: www.baidu.com # 指定反代的域名, 可能有跨域问题.
```

# 将服务暴露给外部客户端

* 将服务的类型设置为 `NodePort`, 每个集群节点都会在节点上打开一个端口, 对于 `NodePort` 服务, 每个集群节点在节点本身上打开一个端口, 并将在该端口上接收到的流量重定向到基础服务, 该服务仅在内部集群 `ip` 和端口上才可以访问, 但也可以通过所有节点上的专用端口访问.
* `LoadBalance`, `NodePort` 类型的拓展, 使得服务可以通过一个专用的负载均衡器来访问, 这是由 `kubernetes` 中正在运行的云基础设施提供. 负载均衡器将流量重定向到跨所有节点的节点端口, 客户端通过负载均衡器的 `ip` 连接到服务.
* `Ingress` 资源. 通过一个 `ip` 地址公开多个服务, 运行在 `http` 层, 因此可以提供比工作在第四层的服务更多的功能.

## NodePort

```yaml
spec:
	type: NodePort
	ports:
	- port: 80
	   targetPort: 8080
	   nodePort: 30123
```

![](assert/Pasted%20image%2020220705135742.png)

