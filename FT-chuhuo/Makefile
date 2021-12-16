all:
	systemctl  restart   tftpd-hpa
	systemctl restart nfs-kernel-server
	systemctl restart isc-dhcp-server
1:
	systemctl status isc-dhcp-server
2:
	systemctl status nfs-kernel-server
3:
	systemctl status tftpd-hpa
4:
	cat /etc/dhcp/dhcpd.conf
	echo "\n"
	cat /etc/default/tftpd-hpa
	echo "\n"
	cat /etc/exports
	echo "\n"
	cat /etc/default/isc-dhcp-server
	echo "\n"
	cat /opt/nfs/arm64/pxeinfo.sh
	echo "\n"
	cat /opt/nfs/arm64/post_custom.sh
