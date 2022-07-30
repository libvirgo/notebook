# 扩容

`ext4-combined-efi` 固件扩容

简单的创建两个分区用来挂载然后把旧分区的文件备份然后解压到新分区即可.

参考 [storage](https://doc.embedfire.com/openwrt/user_manal/zh/latest/User_Manual/openwrt/storage.html)

```bash
mkdir -p /tmp/introot
mkdir -p /tmp/extroot
mount --bind / /tmp/introot
mount /dev/sda1 /tmp/extroot
tar -C /tmp/introot -cvf - . | tar -C /tmp/extroot -xf -
umount /tmp/introot
umount /tmp/extroot
```