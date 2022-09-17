# 隔离级别

* READ UNCOMMITTED 脏读
* READ COMMITTED 不可重复读
* REPEATABLE READ 幻读
* SERIALIZABLE 加锁读

`MYSQL` 默认为 `REPEATABLE READ`

# 事务

## 自动提交

可以通过 `autocommit` 变量查看启用禁用自动提交模式, 如果不显式地开始一个事务, 那么每个查询都被当作一个事务执行提交操作.

```bash
show variables like 'autocommit';
```


## 隐式和显式锁定

`InnoDB` 采用的是两阶段锁定协议, 在事务执行过程中, 随时都可以执行锁定, 锁只有在执行`Commit` 或者 `Rollback` 的时候才会释放, 并且所有的锁在同一时刻被释放. 前面描述的锁都是隐式锁定, `InnoDB` 会根据隔离级别在需要的时候自动加锁.

`InnoDB` 也支持显式锁定, 这些语句不属于 `SQL` 规范.

* select ... lock in share mode
* select ... for update

`MySQL` 也支持 `lock tables` 和 `unlock tables`, 这是在服务器层实现的, 和存储引擎无关. 他们有自己的用途, 不能替代事务处理.

# 多版本并发控制(MVVC)

基于提升并发性能的考虑, 行级锁的实现并不简单, 一般都同时实现了多版本并发控制, 可以认为 `MVVC` 是行级锁的一个变种, 但是它在很多情况下避免了加锁操作, 因此开销更低. 数据库实现机制有所不同, 但大都实现了非阻塞的读操作, 写操作也只锁定必要的行.

`MVVC` 的实现, 是通过保存数据在某个时间点的快照来实现的, 也就是说, 不管需要执行多长时间, 各个事务看到的数据都是一致的, 根据事务开始的时间不同, 每个事务对同一张表, 不一样的.

`InnoDB` 的 `MVVC` 是通过在每行记录后面保存两个隐藏的列来实现的. 这两个列, 一个保存了行的创建时间, 一个保存行的过期时间, 当然存储的并不是实际的时间值, 而是系统版本号, 每开始一个新的事务, 系统版本号都会自动递增. 事务开始时刻的系统版本号会作为事务的版本号, 用来和查询到的每行记录的版本号进行比较. 以下是 `REPEATABLE READ` 隔离级别下 `MVVC` 的具体操作.

SELECT :: 
    1. `InnoDB` 只查找版本早于当前事务版本的数据行, 也就是, 行的系统版本号小于等于事务的系统版本号, 这样可以确保事务读取的行要么是在事务开始前已经存在的, 要么是事务自身插入或修改过的.
    2. 行的删除版本要么未定义, 要么大于当前事务版本号. 这可以确保事务读取到的行在事务开始之前未被删除.
INSERT ::
    `InnoDB` 为新插入的每一行保存当前系统版本号作为行版本号.
DELETE ::
    `InnoDB` 为删除的每一行保存当前系统版本号作为行删除标识.
UPDATE ::
    InnoDB 为插入一行新纪录, 保存当前系统版本号作为行版本号, 同时保存当前系统版本号到原来的行作为行删除标识.

保存这两个额外系统版本号, 使大多数操作都可以不用加锁, 这样设计使得读操作简单性能好, 并且也能保证只会读取到符合标准的行. 不足之处是每行记录都需要额外的存储空间, 需要做更多的行检查操作, 以及一些额外的维护操作.

`MVVC` 只在 `REPEATABLE READ` 和 `READ COMMITTED` 两个隔离级别下工作, 其他两个事务隔离级别不兼容.

## 快照读

* `READ COMMITTED` :: 每次 `select` 都生成一个快照读
* `REPEATABLE READ` :: 开启事务后第一个 `select` 语句生成快照读.

### undolog 和 MVVC

![](assert/Pasted%20image%2020220913235603.png)

事务会先使用排他锁锁定该行, 将该行当前的值复制到 `undo log` 中, 然后再真正地修改当前行的值, 最后填写事务的 `DB_TRX_ID`, 使用回滚指针 `DB_ROLL_PT` 指向 `undo log` 中修改前的行 `DB_ROW_ID`.

# InnoDB 存储引擎

`InnoDB` 是 `MySQL` 的默认事务型引擎, 它被设计用来处理大量的短期事务, 短期事务大部分情况是正常提交的, 短期事务大部分情况下是正常提交的, 很少会被回滚. `InnoDB` 的性能自动崩溃恢复特性, 使得它在非事务型存储的需求中也很流行.

## 概览

`InnoDB` 的数据存储在表空间中, 表空间是由 `InnoDB` 管理的一个黑盒子, 由一系列的数据文件组成. 在 `4.1` 版本后, 可以将每个表的数据和索引存放在单独的文件中, 也可以使用裸设备作为表空间的存储介质.

`InnoDB` 采用 `MVVC` 来支持高并发, 并且实现了四个标准的隔离级别, 默认级别是 `REPEATABLE READ` 并且通过间隙锁策略防止幻读的出现. 间隙锁使得 `InnoDB` 不仅锁定查询设计的行, 还会对索引中的间隙进行锁定, 以防止幻影行的插入.

