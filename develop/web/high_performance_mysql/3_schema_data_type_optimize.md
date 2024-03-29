# 选择优化的数据类型

* 更小的通常更好
* 简单就好 :: 例如整型比字符操作代价更低, 还有一个是应该使用 `MySQL` 内建的类型而不是字符串来存储日期和时间.
* 尽量避免 `NULL` :: 尤其是考虑该列作为索引的情况下

`datetime` 和 `timestamp` 都可以存储相同类型的数据: 时间和日期精确到秒, 然而 `timestamp` 只使用 `datetime` 一半的存储空间, 并且会根据时区变化, 具有特殊的自动更新能力. 另一方面, `timestamp` 允许的时间范围要小得多.

## 字符串

下面这些情况下使用 `Varchar` 更合适:

* 字符串列的最大长度比平均长度大很多
* 列的更新很少, 碎片不是问题
* 使用了像 `UTF-8` 这样复杂的字符集, 每个字符都是用不同的字节数存储.

`InnoDB` 可以把过长的 `Varchar` 存储为 `blog`

### BLOB&TEXT

`BLOB` 和 `TEXT` 之间仅有的不同是 `BLOB` 存储二进制数据, 没有排序规则或字符集. 而 `TEXT` 有字符集和排序规则.

这两个的排序与其它类型是不同的, 只对每个列的最前 `max_sort_length` 字节而不是整个字符串做排序. 如果只需要一小部分字符可以减少 `max_sort_length` 或者使用 `order by substring(column, length)`.

如果查询使用了 `Blob` 或者 `text` 并且使用了隐式临时表, 将不得不使用磁盘临时表, 即使只有少数几行. 这会导致严重的性能开销, 即使配置 `MySQL` 将临时表存储在内存块设备商, 依然需要许多昂贵的系统调用. 最好的解决方案是尽量避免使用这两个类型. 如果实在无法避免, 可以在所有用到 `blob` 字段的地方都是用 `substring` 将列值转换为字符串, 这样就可以使用内存临时表了. 确保临时表的大小小于 `max_heap_table_size` 或 `tmp_table_size`.

如果 `explain` 执行计划的 `extra` 列包含了 `using temporary`, 则说明这个查询使用了隐式临时表.

### 使用枚举代替字符串类型

`MySQL` 在内部会将每个值在列表中的位置保存为整数, 并且在表的 `.frm` 文件中保存 `数字-字符串` 映射关系的查找表.

如果使用数字作为 `enum` 枚举常量, 这种双重性很容易导致混乱, 尽量避免这么做.

另一个需要注意的是, 枚举字段是按照内部存储的整数而不是定义的字符串进行排序的.

枚举最不好的地方是, 字符串列表是固定的, 添加或删除字符串必须使用 `alter table`, 因此对于一系列未来可能会改变的字符串, 使用枚举不是一个好主意, 如果能接受只在列表末尾添加元素, 这样在后续就可以不用重建整个表来完成修改.

由于 `MySQL` 把枚举保存为整数并且需要通过查找来获得字符串, 所以有一些开销. 在特定情况下, 把 `char/varchar` 列与枚举列进行关联可能会比直接关联 `char/varchar` 列更慢.

## 日期和时间类型

* `datetime` 能保存大范围的值, 从 `1001-9999` 精确到秒, 他把日期和时间封装到格式为 `YYYYMMDDHHMMSS` 的整数中, 与时区无关, 使用8个字节的存储空间, 默认情况下使用 `ANSI` 标准定义的日期和时间表示方法 `YYYY-MM-DD HH-MM-SS`.
* `timestamp` 保存了从 `1980-2038` 年, 只使用了4个字节的存储空间, 因此它的范围比 `datetime` 小得多.

## 位数据类型

有少数几种存储类型使用紧凑的位存储数据. 所有这些位类型, 不管底层存储格式和处理方式如何, 从技术上来说都是字符串类型.

**bit**

`bit` :: `MySQL` 把 `bit` 当做字符串类型, 而不是数字类型. 当检索 `bit(1)` 的值结果会是一个包含二进制 `0/1` 的字符串, 而不是 `ASCII` 的0或者1.

例如存储一个 `b'00111001'` 到 `bit(8)` 的列并检索, 得到的内容为 `57` 的字符串, 实际得到的位ASCII位57的字符"9", 但是在数字场景下是57. 这是令人费解的, 所以认为应该严谨使用 `bit` 类型. 对于大部分应用, 最好避免使用这种类型.

如果想在一个 `bit` 的存储空间中存储一个 `true/false` 的值, 另一个方法是创建一个可以为空的 `char(0)` 列, 该列可以保存空值或者长度为0的字符串.

**set**

如果需要保存很多 `true/false`, 它在 `MySQL` 内部是以一系列打包的位的集合来表示的, 这样就有效的利用了存储空间. 也有 `find_in_set()/field()` 这样的函数方便查找, 缺点是改变列的定义代价较高, 需要 `alter table`. 一般来说, 也无法在 `set` 列上通过索引查找.

# `schema` 设计中的陷阱

* 太多的列
* 太多的关联 :: 如果希望查询执行的快且并发性好, 单个查询最好在12个表以内做关联.
* 全能的枚举 :: 避免过度使用枚举
* 变相的枚举 :: 比如集合允许在列中存储一组定义值中的一个或多个值, 有时候这可能容易导致混乱, 比如 `create table (is_default set('y', 'n') not null default 'n')`, 如果这里真假不会同时出现, 那么毫无疑问应该使用枚举列来代替集合列.
* 非此发明的NULL :: 之前写了避免使用NULL, 并且建议尽可能地考虑替代方案. 即使需要存储一个事实上的空值到表中时, 也不一定非得使用NULL. 也许可以使用0, 某个特殊值, 或者空字符串作为代替. 不过也不要走极端, 处理NULL确实不容易, 但有时候会比替代方案更好, 比如 `create table (dt datetime not null default '0000-00-00 00:00:00'`. 伪造的全0值可能会导致很多问题(可以配置 `MySQL` 的 `SQL_MODE` 来禁止不可能的日期, 它不会让创建的数据库里充满不可能的值).

# 范式和反范式

在范式化的数据库中, 每个事实数据会出现且只出现一次. 相反, 在反范式化的数据库中, 信息是冗余的, 可能会存储在多个地方.

冗余的比如如下:

| employee | department | head |
| --- | --- | --- |
| jones | accounting | jones |
| smith | engineering | smith |
| brown | accounting | jones |
| green | engineering | smith |
假如 `brown` 要接任 `accounting` 的领导, 那么就需要修改多行数据来反应这个变化, 这很容易引入错误. 如果 `jones` 这行的领导跟 `brown` 这行的不一样, 就没有办法知道哪个是对的. 就像是一句老话: "一个人有两块手表就永远不知道时间". 此外, 这个设计在没有雇员信息的情况下就无法表示一个部门. 要避免这些问题, 我们就需要对这个表进行范式化, 方式是拆分雇员和部门项.

## 范式的优点和缺点

* 范式化的更新操作通常比反范式化要快
* 当数据较好的范式化时, 就只有很少或者没有重复数据, 所以只需要修改更少的数据.
* 范式化的表通常更小, 可以更好地放在内存里, 所以执行操作会更快.
* 很少有多余的数据意味着检索列表数据时更少需要 `distinct` 或者 `group by` 语句. 比如前面的需要用 `distinct/group by` 才能获得一份唯一的部门列表.

然而范式化设计的 `schema` 的缺点是通常需要关联, 复杂的查询语句可能代价昂贵, 甚至可能使一些索引策略无效.

## 反范式的优点和缺点

因为所有数据都在一张表中, 可以很好地避免关联.

如果不需要关联表, 则对大部分查询最差的情况(没有索引全表扫描), 也要比关联要快得多, 因为避免了随机 `I/O`. 单独的表也能使用更有效的索引策略.

范式化的主要问题是关联, 使得需要在一个索引中又排序又过滤, 如果采用反范式化组织数据, 将几张表中需要的字段合并一下并且增加一个索引, 就可以不通过关联写出查询, 将非常高效.

## 混用范式化和反范式化

范式化和反范式化的 `schema` 各有优劣. 完全的范式化和反范式化都是实验室里才有的东西. 在实际应用中经常需要混用.

最常见的反范式化数据的方法是复制或者缓存. 在不同的表中存储相同的特定列, 可以通过触发器更新缓存值, 这使得实现这样的方案变得更简单.

## 缓存表和汇总表

有时提升性能最好的方法是在同一张表中保存衍生的冗余数据. 然而有时也需要创建一张完全独立的汇总表或缓存表(特别是为满足检索的需求时). 如果能容许少量的脏数据 , 这是非常好的方法. 不过需要避免昂贵复杂的实时更新操作.

## 物化视图

物化视图是实际上预先计算并且存储在磁盘上的表, 而视图会被转化成普通的`SQL`查询语句, 是不存数据的虚拟表.

`MySQL` 不支持原生的物化视图, 需要使用 `flexviews` 来实现.

## 加快 `alter table` 操作的速度

`MySQL` 执行大部分修改表结构操作的方法是用新的结构创建一个空表, 从旧表中查出所有数据插入新表, 然后删除旧表. 这样操作可能需要话费很长时间, 如果内存不足且表很大, 而且有很多索引的情况下更是如此.

一般而言, 大部分 `alter table` 操作将导致 `MySQL` 服务中断. 对常见的场景, 能使用的技巧只有两种: 一种是先在一台不提供服务的机器上执行 `alter table` 操作, 然后和提供服务的主库进行切换, 另外一种是影子拷贝, 用要求的表结构创建一张和源表无关的新表, 然后通过重命名和删表操作交换两张表. 有一些工具可以帮助完成影子拷贝工作.

不是所有的 `alter table` 操作都会引起表重建. 加入要修改一个列的默认值:

```sql
alter table sakila.file 
modify column rental_duration tinyint(3) not null default 5;
```

```sql
alter table sakila.file
alter column rental_duration set defaul 5;
```

第一种会重建新表, 而第二种只会修改 `.frm` 文件而不涉及表数据.

但 `MySQL` 有时候会在没有必要的时候也重建表. 如果愿意冒一些风险, 可以让 `MySQL` 做一些其他类型的修改而不用重建表.

下面这些操作是有可能不需要重建表的:

* 移除一个列的 `auto_increment` 属性
* 增加, 移除, 或更改枚举和set常量.

基本的技术是为想要的表结构创建一个新的 `.frm` 文件, 然后用它替换掉已经存在的那张表的 `.frm` 文件:

1. 创建一张有相同结构的空表, 并进行所需要的修改.
2. 执行 `flush table with read lock`, 这会关闭所有正在使用的表, 并且禁止任何表被打开.
3. 交换 `.frm` 文件
4. 执行 `unlock tables` 来释放锁.
