`Raft` 将一致性分解为多个子问题: `Leader election`, `Log replication`, `Safety`, `Membership change`. 同时, `Raft` 算法使用了更强的假设来减少需要考虑的状态.

* Leader: 接受客户端请求, 并向 `Follower` 同步请求日志, 当日志同步到大多数节点上后统治跟随者提交日志.
* Follower: 接受并持久化领导者同步的日志, 在被告知提交后提交日志.
* Candidate: 选举过程中的临时角色.

# Leader election

![[assert/Pasted image 20220623143345.png]]

选举有两个超时时间: 选举超时和心跳超时.
如果 `Follower` 在选举超时时间内没有收到 `Leader` 的心跳, 就会等待一次随机时间后发起一次选举.

`Follower` 将其当前 `term` 加一然后转换为候选者, 先给自己投票并且给集群中的其他服务器发送 `RequestVote RPC`, 可能会出现如下三种情况:

* 赢得多数选票, 选举成功.
* 收到了 `Leader` 的消息, 表示有其他的服务器已经当了 `Leader`.
* 没有服务器赢得多数的选票, 选举失败, 等待选举时间超时后发起下一次选举(选举时间时随机的).

`Leader` 通过定期向所有 `Followers` 发送心跳来维持统治, 如果没有心跳则再次发起选举.

`Raft` 保证选举出的 `Leader` 上一定有最新的已提交的日志, 这点在安全性中.

# Log replication

![[assert/Pasted image 20220623145620.png]]

某些 `Followers` 可能没有成功的复制日志, `Leader` 会无限的重试直到所有的 `Followers` 最终存储了所有的日志条目.

日志由有序编号的日志条目组成, 每个日志条目包含它被创建时的任期号和用于状态机执行的命令, 如果一个日志条目被复制到大多数的服务器上, 就被认为可以被提交了.

![[assert/Pasted image 20220623150448.png]]

日志同步保证如下两点:

* 如果不同日志中的两个条目有着相同的索引和任期号, 则它们所存储的命令是相同的.
* 如果不同日志中的两个条目有着相同的索引和任期号, 则它们之前的所有条目都是完全一样的.

第一条特性来源于 `Leader` 在一个 `term` 内在给定的一个 `log index` 最多创建一条日志条目, 同时该条目在日志中的位置也从不改变.

第二条特性来源于 `AppendEntries` 的一个简单的一致性检查, 当发送一个 `AppendEntries RPC` 时, `Leader` 会把新日志条目紧接着之前的条目的 `log index` 和 `term` 都包含在里面, 如果 `Follower` 没有在它的日志中找到 `log index` 和 `term` 都相同的日志, 它就会拒绝新的日志条目.

一般情况下, `Leader` 和 `Followers` 的日志保持一致, 因此 `AppendEntries` 一致性检查通常不会失败. 然而 `Leader` 崩溃可能会导致日志不一致: 旧的 `Leader` 可能没有完全复制日志中的所有条目.

![[assert/Pasted image 20220623151149.png]]

`Followers` 可能有新 `Leader` 没有的条目, 也有可能丢掉新 `Leader` 的一些条目. 丢失的或者多出来的会持续多个任期.

`Leader` 通过强制 `Followers` 复制它的日志来处理日志的不一致, 不一致的日志会被 `Leader` 的日志覆盖.

`Leader` 会从后往前试, 每次 `AppendEntries` 失败后尝试前一个日志条目, 直到找到每个 `Follower` 的日志一致位点, 然后向后逐条覆盖 `Followers` 在该位置之后的条目.
