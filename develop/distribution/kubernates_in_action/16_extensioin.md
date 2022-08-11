# CRD

```yaml
apiVersion: apiextensions.k8s.io/v1beta1
kind: CustomResourceDefinition
metadata:
    name: websites.extensions.example.com
spec:
    scope: Namespaced # 属于命名空间资源
group: extensions.example.com
version: v1
names:
    kind: Website
    singular: website
    plural: websites
```

```bash
kubectl create -f website-crd-definition.yaml
```

```yaml
apiVersion: extensions.example.com/v1
kind: Website
metadata:
    name: kubia
spec:
    gitRepo: https://xxx/xxx.git
```

**编写控制器**

[k8s-website-controller](https://github.com/luksa/k8s-website-controller)

当编写好控制器后, 可以使用 `kubectl proxy` 将控制器作为 `API` 服务器的 `ambassador` 运行, 在完成后在生产环境使用时的后, 可以通过 `pod` 的方式运行.

![](assert/Pasted%20image%2020220811171900.png)

我们需要在部署之前创建服务账户和集群角色:

```bash
kubectl create serviceaccount website-controller
kubectl create clusterrolebinding website-controller --clusterrole=cluster-admin --serviceaccount=default:ewbsite-controller
```

