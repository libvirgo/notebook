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

`show status` 是一个有用的工具, 但并不是一款剖析工具, `show status` 大部分结果都只是一个计数器, 可以显示某些活动如读索引的频繁程度, 但是无法给出消耗了多少时间.

尽管 `show status` 无法提供基于时间的统计, 但对于在执行完查询后观察某些计数器的值还是有帮助的. 有时候可以猜测那些操作代价较高或者消耗的时间较多. 最有用的计数器包括句柄计数器, 临时文件和表计数器等.

可以用 `flush status` 刷新.

# 间歇性问题

* 应用通过 `curl` 从一个运行得很慢的外部服务来获取汇率报价的数据.
* `memcached` 缓存中的一些重要条目过期, 导致大量请求落得 `MySQL` 以重新生成缓存条目.
* `DNS` 查询偶尔会有超时现象.
* 可能是由于互斥锁争用, 或者内部删除查询缓存的算法效率太低的缘故, `MySQL` 查询缓存有时候会导致服务有短暂的停顿.
* 当并发度超过某个阈值时, `InnoDB` 的拓展性限制导致查询计划的优化需要很长时间.

## 查询问题还是服务器问题

### 通过 `show global status`

以较高频率比如一秒执行一次 `show global status` 命令捕获数据, 问题出现时, 则可以通过某些计数器(threads_running, threads_connected, questions, queries) 的尖刺或者凹陷来发现.

```bash
mysqladmin ext -i1 -p | awk '/Queries/{q=$4-qp;qp=$4}
/Threads_connected/{tc=$4}
/Threads_running/{printf "%5d %5d %5d\n", q, tc, $4}'
```

### 通过 `show processlist`

```bash
mysql -p -e 'show processlist\G' | grep State: | sort | uniq -c | sort -rn
```

我们可以通过编写脚本或使用 `pt-stalk` 等工具来作为触发器, 当数据达到某个程度的时候触发数据收集等.

# 案例

以下是可能的收集样本数据:

* 查询活动从1000-10000的`QPS`, 其中有很多垃圾命令, 比如`ping`. 大部分都是`select`, 大约300~2000/s, 5/s的`update`
* 在 `show processlist` 中收集到的线程状态.
* 大部分查询都是索引扫描/范围扫描, 很少有全表或者表关联的情况.
* 每秒大约有20~100次排序, 需要排序的行大约有1000~12000行.
* 每秒大约创建12~90个临时表, 其中3~5个磁盘临时表.
* 没有表锁或者查询缓存的问题.
* 在 `show innodb status` 观察到主要的线程状态是 `flushing buffer pool pages`, 但只有少量的脏页需要刷新(innodb_buffer_pool_pages_dirty), `log sequence number` 和 `last checkpoint` 之间的差距也较少. `innodb` 缓存池也没有用满, 比数据集还要大很多.
* 每秒捕获一次 `iostat` 输出, 可以发现没有磁盘读, 而写操作则接近天花板, 所以I/O平均等待时间和队列长度都非常高.
* `vmstat` 显示`CPU`大部分时间是空闲的, 只是偶尔在写尖峰的时候有一些I/O等待时间.

以上是一些可能能用来排查问题的数据.

* 为什么不一开始就优化慢查询 :: 可能问题出在缓存失效导致的查询风暴上, 连接太多导致, 或者其他问题. 应该先排查找到问题点.
* 查询由于糟糕的执行计划而执行缓慢 :: 我们得确定慢查询时原因还是结果, 可能是缓存失效导致的查询风暴积累问题而导致的慢查询, 尽管可能消除临时表或者排序可能是最佳实践, 但有可能这不是问题导致的根本原因.
* 如果缓存项被重新生成很多次, 是不是会导致产生很多同样的查询? :: 如果是多线程重新生成同样的缓存项, 那么确实有可能导致产生很多同样的查询.
* 每秒有几百次select, 但只有五次update, 怎么确定这五次update的压力不会导致问题? :: 某种查询的绝对数量不一定有意义.
* I/O风暴最初的证据看起来不是很充分 :: 有很多种解释可以说明为什么一个小数据库可以产生大量的写入磁盘, 然而可能很难准确测量. 我们以尽量平衡成本和潜在的利益为第一优先级. 越是难以准确测量的时候, 成本/收益比越攀升, 也更愿意接受不确定性.

# 总结

* 定义性能最有效的方法是响应时间
* 如果无法测量就无法有效地优化, 所以性能优化工作需要基于高质量, 全方位以及完整的响应时间测量.
* 测量的最佳开始点事应用程序, 而不是数据库.
* 大多数系统无法完整地测量, 有时候也会有错误的结果. 但也可以想办法饶过一些限制, 并得到好的结果.
* 完整的测量会产生大量需要分析的数据, 所以需要用到剖析器.
* 剖析报告是一种汇总信息, 掩盖和丢弃了太多细节并且不会告诉缺少了什么. 所以不能完全依赖剖析报告.
* 有两种消耗时间的操作: 工作或者等待. 大多数剖析器智能测量因为工作而消耗的时间, 所以等待分析有时候是很有用的补充. 尤其是当CPU利用率很低但工作却一直无法完成的时候.
* 优化和提升是两回事. 当继续提升的成本超过收益的时候, 应当停止优化.
* 注意直觉, 应当只根据直接来指导解决问题的思路, 而不是确定系统的问题. 决策应当尽量基于数据而不是感觉.
