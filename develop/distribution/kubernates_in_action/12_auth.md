```toc
```

# `API` 服务器的安全防护

`API` 服务器可以配置一到多个认证的插件. `API` 服务器接收到的请求会经过一个认证插件的列表, 列表中的每个插件都可以检查这个请求和尝试确定谁在发送这个请求. 列表中的第一个插件可以提取请求中的客户端用户名, 用户`ID` 和组信息, 并返回给 `API` 服务器. `API` 服务器会停止调用剩余的认证插件并继续进入授权阶段.

启动 `API` 服务器时, 通过命令行选项可以开启认证插件.

## 用户和组

认证插件会返回已经认证过用户的用户名和组. `kubernetes` 不会在任何地方存储这些信息, 这些信息被用来验证用户是否被授权执行某个操作.

### 了解用户

`kubernetes` 区分了两种连接到 `API` 服务器的客户端.

* 真实的人
* `pod`

用户应该被管理在外部系统中, 但是 `pod` 使用一种成为 `service accounts` 的机制.

### 了解组

正常用户和 `ServiceAccount` 都可以属于一个或多个组. 有插件返回的组仅仅是表示组名称的字符串, 系统内置的组会有一些特殊的含义.

* `system:unauthenticated` :: 所有认证插件都不会认证客户端身份的请求.
* `system:authenticated` :: 自动分配给一个成功通过认证的用户.
* `system:serviceaccounts` :: 所有在系统中的 `ServiceAccount`.
* `system:serviceaccounts:<namespace>` :: 所有在特定命名空间中的 `ServiceAccount`.

## ServiceAccount

已经了解过 `pod` 是怎么通过发送 `/var/run/secrets/kubernetes.io/serviceaccount/token` 文件中的内容来进行身份认证的, 这个文件通过加密挂载进每个容器的文件系统中.

每个`pod` 都与一个 `ServiceAccount` 相关联, 它代表了运行在 `pod` 中应用程序的身份证明. `token` 文件持有 `ServiceAccount` 的认证 `token`. 应用程序使用这个 `token` 连接 `API` 服务器时, 身份认证插件会对 `ServiceAccount` 进行身份认证, 并将 `ServiceAccount` 的用户名传回 `API` 服务器内部. 用户名的格式类似 `system:serviceaccount:<namespace>:<service account name>`.

`ServiceAccount` 只不过是一种运行在 `pod` 中的应用程序和 `API` 服务器身份认证的一种方式.

### 了解 `ServiceAccount` 资源

`ServiceAccount` 就像 `pod`, `secret`, `configMap` 等一样, 它们作用在单独的命名空间, 为每个命名空间自动创建一个默认的 `ServiceAccount`(`pod` 会一直使用).

每个 `pod` 智能与同一个命名空间的一个 `SA` 相关联, 但是多个 `pod` 可以使用同一个 `SA`.

![](assert/Pasted%20image%2020220803173226.png)

### 创建 `SA`

为了集群的安全性, 不需要读取任何集群元数据的 `pod` 运行在一个账户下, 检索的放在只读账户, 修改的也在另一个账户下运行.

```bash
kubectl create serviceaccount foo
```

![](assert/Pasted%20image%2020220803174649.png)

在第七章中, 我们将 `secrets` 挂载到 `pod` 中, 但是我们可以通过对 `SA` 进行配置, 让 `pod` 只允许挂载 `SA` 中列出的可挂载密钥. 为了开启这个功能, `SA` 需要包含 `kubernetes.io/enforce-mountable-secrets="true"` 注解.

如果 `SA` 被加上这个注解, 任何使用这个 `SA` 的 `pod` 只能挂载可挂载密钥, 不能使用其它的密钥.

`SA` 也可以包含镜像拉取密钥的 `list`, 不过这与可挂载密钥不同, 镜像拉取密钥不是确定一个 `pod` 可以使用哪些镜像拉取密钥的, 而是添加到 `SA` 中的镜像拉取密钥会自动添加到所有使用这个 `SA` 的 `pod` 中. 使得不必对每个 `pod` 都单独进行镜像拉取密钥的添加操作.

### 分配 `SA` 给 `pod`

> `pod` 的 `SA` 必须在创建的时候进行设置, 后续不能被修改

```yaml
spec:
    serviceAccountName: xxx
    containers:
```

# 通过基于角色的权限控制加强集群安全

> 除了基于角色的 `RBAC`, 也有基于访问控制的 `ABAC`, `WebHook` 等, 不过 `RBAC` 是标准的.

![](assert/Pasted%20image%2020220803180524.png)
`RBAC` 这样的授权插件运行在 `API` 服务器中会决定一个客户端是否允许在请求的资源上执行请求的动词.

除了可以对全部资源类型应用安全权限, 还可以用于特定的资源实例, 也可以应用于非资源的 `URL` 路径, 因为并不是 `API` 服务器对外暴露的每个路径都映射到一个资源.

顾名思义, `RBAC` 授权插件将用户角色作为决定用户能否执行操作的关键因素. 主体和一个或多个角色相关联, 每个角色被允许在特定的资源上执行特定的动词.

如果一个用户有多个角色, 他们可以做任何他们的角色允许他们做的事情.

通过 `RBAC` 插件管理授权是简单的, 这一切都是通过创建四种 `RBAC` 特定的 `kubernetes` 资源来完成的.

## 介绍 `RBAC` 资源

* `Role` 和 `ClusterRole` 角色, 指定了在资源上可以执行哪些动词.
* `RoleBinding` 和 `ClusterRoleBinding`, 它们将上述角色绑定到特定的用户, 组或 `SA` 上.

角色定义了可以做什么操作, 而绑定定义了谁可以做这些操作.

