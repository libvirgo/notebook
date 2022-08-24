# Command

```
use crashcourse;

show databases;

show tables;

show status

show create database; show create table;
show grants;

show errors; show warnings;

help show;
```

# SQL

```sql
select * from xxx;
select name, age, sex from xxx limit 5;
```

```sql
select prod_id, prod_price, prod_name from products order by prod_price, prod_name;
select ...... order by desc;
```

```sql
select xxx, xxx from products where prod_price = 2.5;
select prod_id, quantity, item_price, quantity*item_price as expanded_price from orderitems where order_num = 20005;
```

## 支持的算数操作符

* +
* -
* *
* /

## 常用文本处理函数

| func | desc |
| --- | --- |
| Left() | 返回串左边的字符 |
| Length() |  |
| Locate() | 找出串的子串 |
| Lower() |  |
| LTrim() |  |
| Right |  |
| RTrim |  |
| Soundex() | 返回串的soundex值 |
| SubString() |  |
| Upper() |  |
|  |  |

其中 `Soundex` 是一个将任何文本串转换为描述其语音表示的字母数字模式的算法.

```sql
# 可以找出 y lee
select cust_name, cust_contact from customers where soundex(cust_contact) = soundex('y lie')
```

## 日期处理函数

| func | desc |
| --- | --- |
| AddDate() |  |
| AddTime() |  |
| CurDate() |  |
| CurTime() |  |
| Date() |  |
| DateDiff() |  |
| Date_Add() |  |
| Date_Format() |  |
| Day() |  |
| DayOfWeek() | 对于一个日期返回星期 |
| Hour() | 返回一个时间的小时 |
| Minute() |  |
| Month() |  |
| Now() |  |
| Second() |  |
| Time() |  |
| Year() |  |
```sql
select cust_id, order_num from orders where year(order_date) = 2005 and month(order_date) = 9;
select xx from orders where date(order_date) between '2005-09-01' and '2005-09-30';
```

## 聚集函数

| func | desc |
| --- | --- |
| Avg() |  |
| Count() | 某列的行数 |
| Max() | 某列最大值 |
| Min() |  |
| Sum() |  |
|  |  |
```sql
select avg(prod_price) as avg_price from products;
```

## 分组

分组允许把数据分为多个逻辑组, 以便能对每个组进行聚集计算.

```sql
select vend_id, count(*) as num_prods from products group by vend_id;
```

使用 `with rollup` 可以得到每个分组以及每个分组汇总级别的值.

过滤分组

```sql
select cust_id, count(*) as orders from orders group by cust_id having count(*) >= 2;
```

优化:

1. 给 `group by` 后面的字段添加索引可以让字段数值有序而避免排序一遍.
2. `order by null` 取消排序
3. 尽量只是用内存临时表, 如果因为数据放不下导致使用磁盘临时表的话会比较耗时, 因此可以适当调大 `tmp_table_size` 参数以避免磁盘临时表
4. 使用 `SQL_BIG_RESULT` 优化磁盘临时表, 会使用数组代替b+树

## 联结

![](assert/Pasted%20image%2020220825001658.png)