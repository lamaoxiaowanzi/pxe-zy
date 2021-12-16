#!/bin/bash

echo 该脚本仅用于非法重启动作

busybox devmem 0x28180480 8 0x01
echo  pull high ctr0
sleep 2
for((i=0;i<12;i=i+1))
do	
	busybox devmem 0x28180484 8 0x01
	echo  pull high ctr1
	sleep 1	
	busybox devmem 0x28180484 8 0x00
	echo  pull low ctr1
	sleep 1
done

sleep 2
busybox devmem 0x28180480 8 0x00
echo  poweroff
 



