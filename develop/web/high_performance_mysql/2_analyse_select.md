# 剖析 `MySQL` 查询

## 剖析服务器负载

在 `MySQL` 的当前版本中, 慢查询日志是开销最低, 精度最高的测量查询时间的工具. 慢查询日志带来的开销可以忽略不计, 更需要担心的是日志可能消耗大量的磁盘空间, 如果长期开启慢查询日志, 注意要部署日志轮转工具, 或者只在需要收集负载样本的期间开启即可.

`MySQL` 还有另外一种查询日志, 被称之为通用日志, 但很少用于分析和剖析服务器性能. 通用日志在查询请求到服务器时进行记录, 所以不包含响应时间和执行计划等重要信息, `MySQL` 支持将日志记录到数据库的表中, 但大多数情况下没有什么必要, 不但对性能有较大影响, 而且慢查询日志已经支持微秒级别的信息, 将慢查询日志记录到表中会导致时间粒度退化为只能到秒级.

我们也可以通过抓取 `TCP` 网络包, 然后根据客户端服务端通信协议进行解析, 通过慢查询工具 `pt-query-digest` 来分析, 报告中的 `V/M` 列提供了方差均值比, 也就是常说的离差指数, 离差指数高的查询对应的执行时间的变化较大, 而这类查询通常都值得去优化, 如果 `pt-query-digest` 指定了 `--explain` 选项, 输出结果中会增加一列简要描述查询的执行计划. 通过联合观察执行计划列和 `V/M` 列可以更容易识别出性能低下需要优化的查询.

通过慢查询日志记录查询或者使用 `pt-query-digest` 分析 `tcpdump` 的结果, 是可以找到的几种较好的分析方式.

## 剖析单条查询

### 使用 `show profile`

通过 `show profile` 命令剖析. 默认情况下是禁用的, 需要通过 `set profiling = 1` 来开启, 后续就可以通过 `show profiles` 以及 `show profile for query x` 来查看一条语句执行的每个步骤以及其花费的时间. 

![](assert/Pasted%20image%2020220917173009.png)
我们也可以使用如下 `sql` 语句来从 `information_schema.profiling` 表中自己格式化输出(直接使用 `show profile for query 1;` 无法进行排序).

```sql
select state, sum(duration) as total_r, count(*) as calls from information_schema.profiling where query_id = 1 group by state order by total_r desc;

select state, sum(duration) as total_r, round(
100 * sum(duration) / 
(select sum(duration) from information_schema.profiling where query_id = 1), 2
) as pct_r,
count(*) as calls,
sum(duration)/count(*) as "r/call"
from information_schema.profiling where query_id = 1
group by state
order by total_r desc;
```

![](assert/Pasted%20image%2020220917173036.png)

### 使用 `show status`

 `show status` 返回了一些计数器, 既有服务器级别的也有会话级别的, 如果执行 `show global status` 则可以查看服务器级别的从服务器启动时开始计算的查询次数统计. 不同计数器的可见范围不一样, 不过全局的计数器也会出现在  `show status` 的结果中.
