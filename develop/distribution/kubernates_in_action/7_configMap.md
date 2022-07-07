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

