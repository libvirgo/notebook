# 复制有状态 `pod`

如果 `pod` 模板描述了一个关联到特定持久卷声明的数据卷, 那么 `RS` 的所有副本都将共享这个持久卷声明, 也就是绑定到同一个声明的持久卷.

![](assert/Pasted%20image%2020220711185218.png)

不能对每个副本都指定独立的持久卷声明. 所以也不能通过 `RS` 来运行一个每个实例都需要独立存储的分布式数据存储服务.

尽管可以通过创建多个 `RS` 每个副本数设为1来做到 `pod` 和 `RS` 的一一对应, 并有专属的持久卷声明, 但是显得比较笨重, 且难以伸缩.

## 每个 `pod` 都提供稳定的标识

当一个 `RS` 中的 `pod` 被替换时, 新的 `pod` 拥有全新的主机名 `ip`, 在一些应用中, 当启动的实例拥有完全新的网络标识, 但还使用旧实例的数据时, 很可能引起问题.

一个比较取巧的做法是通过 `Service` 来提供稳定的网络地址. 类似与前面的为每个实例创建一个 `RS`, 然而这种做法并不完美, 每个单独的 `pod` 没法知道它对应的 `Service`(所以也无法知道对应的稳定`ip`), 所以他们不能再别的 `pod` 里通过 服务 `ip` 自行注册.

![](assert/Pasted%20image%2020220711190303.png)

# 了解 `StatefulSet`

我们倾向于把无状态应用看作牛, 不需要对单独的实例有太多关心, 挂掉以后非常方便替换掉不健康的实例.

但是把有状态应用看做一个宠物, 若一只宠物撕掉, 需要找到一只行为举止与之完全一致的宠物. 对应用来说, 意味着新的实例需要拥有跟旧的实例完全一致的状态和标识.

`RS` 和 `RC` 管理的 `pod` 副本比较像牛, 它们都是无状态的, 任何时候都可以被一个全新的 `pod` 替换.

## 提供稳定的网络标识

![](assert/Pasted%20image%2020220712162923.png)

`StatefulSet` 创建的每个 `pod` 都有一个从零开始的顺序索引, 这个会体现在 `pod` 的名称和主机名上, 这样有规则的 `pod` 名称更加方便管理. 这样也方便通过主机名来定位具体的有状态 `pod`.

基于如上原因, 一个 `StatefulSet` 通常要求创建一个用来记录每个 `pod` 网络标记的 `headlessService`, 通过这个 `Service`, 每个 `pod` 将拥有独立的 `DNS` 记录, 这样集群里可以通过主机名方便地找到它. 比如可以使用 `a-0.foo.default.svc.cluster.local` 来访问, 也可以通过 `DNS` 服务, 查找域名 `foo.default.svc.cluster.local` 对应的所有 `SRV` 记录, 获取一个 `StatefulSet` 中所有 `pod` 的名称.

`StatefulSet` 会保证一直有一个健康的 `pod` 实例, 这些实例会拥有完全一致的名称和主机名.

### 扩缩容

扩缩容的 `pod` 主机名在 `StatefulSet` 上是可以预期的, 会按照索引值顺序增加或减少, 并且缩容任何时候只会操作一个 `pod` 实例, 并且 `StatefulSet` 在有不健康实例的时候是不允许做缩容操作的.

## 为每个实例提供稳定的专属存储

一个 `StatefulSet` 可以拥有一个或多个卷声明模版, 扩容 `StatefulSet` 增加一个副本数会创建多个 `API` 对象, 对缩容来说只会删除一个 `pod` 并且留下之前创建的声明.

因为缩容会保留持久卷声明, 所以在随后的扩容操作中新的 `pod` 实例会使用绑定在持久卷上的相同声明和其上的数据. 当因为误操作而缩容后可以再做一次扩容来弥补过失, 新的 `pod` 实例会运行到与之前完全一致的状态.

![](assert/Pasted%20image%2020220712164910.png)

# 使用 `StatefulSet`

* 存储数据文件的持久卷
* 必须的一个控制 `Service`
* `StatefulSet`

我们使用 `golang` 写了一个如下的程序:

```go
package main  
  
import (  
    "bufio"
    "bytes"    
    "log"   
    "net"   
    "net/http"   
    "os")  
  
func main() {  
   http.HandleFunc("/store", func(writer http.ResponseWriter, request *http.Request) {  
      name, _ := os.Hostname()  
      buf := bufio.NewReader(request.Body)  
      file, err := os.OpenFile("/etc/stateful/hello", os.O_CREATE|os.O_APPEND|os.O_RDWR, 0644)  
      defer file.Close()  
      if err != nil {  
         log.Println("open file error:", err)  
         return  
      }  
      n, err := buf.WriteTo(file)  
      if err != nil {  
         log.Println("write to file error:", err)  
         return  
      }  
      if n == 0 {  
         _, err := file.WriteString("hello from v2:" + name)  
         if err != nil {  
            log.Println("write hello error:", err)  
            return  
         }  
      }  
      _, _ = writer.Write([]byte("hello from v2:" + name))  
   })  
   http.HandleFunc("/get", func(writer http.ResponseWriter, request *http.Request) {  
      cname, srv, err := net.LookupSRV("", "", "hello-stateful-service")  
      if err != nil {  
         log.Println("lookup ip failed:", err)  
      }  
      var buf bytes.Buffer  
      buf.WriteString(cname + "\n")  
      for _, s := range srv {  
         buf.WriteString(fmt.Sprintf("%s:%d\n", s.Target, s.Port))  
      }  
      _, err = writer.Write(buf.Bytes())  
      if err != nil {  
         log.Println("write buf err:", err)  
      }  
   })  
   err := http.ListenAndServe(":8000", nil)  
   if err != nil {  
      log.Fatalln(err)  
   }  
}
```

`StatefulSet` 完整模板:

```yaml
kind: List  
apiVersion: v1  
items:  
  - kind: Service  
    apiVersion: v1  
    metadata:  
      name: hello-stateful-service  
    spec:  
      clusterIP: None  
      selector:  
        app: hello-stateful  
      ports:  
        - name: http  
          port: 8000  
  - kind: StatefulSet  
    apiVersion: apps/v1  
    metadata:  
      name: hello-stateful  
    spec:  
      replicas: 3  
      selector:  
        matchLabels:  
          app: hello-stateful  
      serviceName: hello-stateful-service  
      template:  
        metadata:  
          labels:  
            app: hello-stateful  
        spec:  
          containers:  
            - name: hello-stateful  
              image: hello-stateful:v3  
              ports:  
                - name: http  
                  containerPort: 8000  
              volumeMounts:  
                - mountPath: /etc/stateful  
                  name: data  
      volumeClaimTemplates:  
        - metadata:  
            name: data  
          spec:  
            resources:  
              requests:  
                storage: 1Mi  
            accessModes:  
              - ReadWriteOnce  
            storageClassName: nfs-client  
  - kind: Ingress  
    apiVersion: networking.k8s.io/v1  
    metadata:  
      name: hello-ingress  
      annotations:  
        nginx.ingress.kubernetes.io/rewrite-target: /$2  # 将$2替换成(.*), 用于重写前缀
    spec:  
      rules:  
        - http:  
            paths:  
              - pathType: Prefix  
                path: "/hello(/|$)(.*)"
                backend:  
                  service:  
                    name: hello-service  
                    port:  
                      number: 8000  
              - pathType: Prefix  
                path: "/stateful(/|$)(.*)"  
                backend:  
                  service:  
                    name: hello-stateful-service  
                    port:  
                      number: 8000
```

也可以不创建 `ingress`, 通过代理的方式请求 `pod`:

```bash
kubectl proxy
curl localhost:8001/api/v1/namespaces/default/pods/hello-stateful-0/proxy/ -d "xxx"
```

当一个 `pod` 要获取一个 `StatefulSet` 里的 `pod` 列表的时候, 需要做的就是触发一次 `SRV DNS` 查询. 如果是上面的应用程序, 可以使用如下 `curl` 触发查询:

```bash
curl localhost/stateful/get
hello-stateful-service.default.svc.cluster.local.
hello-stateful-2.hello-stateful-service.default.svc.cluster.local.:8000
hello-stateful-1.hello-stateful-service.default.svc.cluster.local.:8000
hello-stateful-0.hello-stateful-service.default.svc.cluster.local.:8000
```

也可以通过获取到的 `target` 来解析到它的 `ip` 或者直接使用所需要的去访问即可.

