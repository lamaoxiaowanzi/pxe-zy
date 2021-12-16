#!/bin/bash

# general config
CLIENT_ARCH=arm64		# arm64 or x86 mips64
NETWORK_INTERFACE=enp1s0f0	# pxe client network interface
PXE_FILE=arm64-efi/netbootaa64.efi

SERVER_IP=192.168.1.1	# pxe server ip
path=$1
ISO=$path
BIOS=$2
BOOT_MODE=uefi		# uefi or legacy
TAR_FILE=arm64-efi.tar.gz
EFI=arm64-efi


# dhcp config
SUBNET=192.168.1.0
NETMASK=255.255.255.0
ROUTER=192.168.1.1
DHCP_RANGE_LOW=192.168.1.10
DHCP_RANGE_HIGH=192.168.1.100

shutdown_firewall() {
	iptables -F || echo "iptables delete all rules failed!"

	systemctl stop firewalld || echo "Stop firewalld failed!"
	systemctl disable firewalld || echo "Disable firewalld failed!"
	systemctl status firewalld | grep -q running && echo "firewalld is still running!"

	sed -i 's/RefuseManualStop=yes/#RefuseManualStop=yes/' /usr/lib/systemd/system/auditd.service
	systemctl daemon-reload
	systemctl stop auditd || echo "Stop auditd failed"
	systemctl disable auditd || echo "Disable auditd failed!"
	sed -i 's/#RefuseManualStop=yes/RefuseManualStop=yes/' /usr/lib/systemd/system/auditd.service
	systemctl daemon-reload
	systemctl status auditd | grep -q running && echo "auditd is still running"

	case "`getenforce`" in
	"Enforcing")
		sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
		echo "Changing selinux from enforcing to disabled. Need reboot to take effect."
		echo -e "\033[31;1m[WARNING]: SYSTEM WILL REBOOT IN 60 SECONDS! \033[0m"
		sleep 60 && reboot
		;;
	"Permissive")
		sed -i 's/SELINUX=permissive/SELINUX=disabled/' /etc/selinux/config
		echo "Changing selinux from permissive to disabled. Need reboot to take effect."
		echo -e "\033[31;1m[WARNING]: SYSTEM WILL REBOOT IN 60 SECONDS! \033[0m"
		sleep 60 && reboot
		;;
	"Disabled")
		# do nothing
		;;
	esac

	echo -e "Shut down firewall:\t[\033[32;1m OK \033[0m]"
}

config_dhcp() {
	dpkg -l | grep -q isc-dhcp-server || apt-get install isc-dhcp-server -y > /dev/null
	dpkg -l | grep -q isc-dhcp-client || apt-get install isc-dhcp-client -y > /dev/null

	cat > /etc/dhcp/dhcpd.conf <<-EOF
ddns-update-style none;
default-lease-time 600;
max-lease-time 7200;
log-facility local7;
option space PXE;
option client-system-arch code 93 = unsigned integer 16;
allow booting;
allow bootp;
subnet 192.168.1.0 netmask 255.255.255.0 {
	range 192.168.1.10 192.168.1.100;
	option broadcast-address 192.168.1.255;
	option routers 192.168.1.1;
	default-lease-time 600;
	max-lease-time 7200;
	next-server 192.168.1.1;
	filename "$PXE_FILE";
}
	EOF

	cat > /etc/default/isc-dhcp-server <<-EOF
INTERFACES="$NETWORK_INTERFACE"
	EOF
}

config_tftp() {
	dpkg -l | grep -q tftp-hpa || apt-get install tftp-hpa -y > /dev/null
	dpkg -l | grep -q tftpd-hpa || apt-get install tftpd-hpa -y > /dev/null

	cat > /etc/default/tftpd-hpa <<-EOF
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/var/lib/tftpboot"
TFTP_ADDRESS="0.0.0.0:69"
TFTP_OPTIONS="-l -c -s"
	EOF

	rm -rf /var/lib/tftpboot/*
	[ ! -d /var/lib/tftpboot ] && mkdir /var/lib/tftpboot && chmod 777 /var/lib/tftpboot
	tar -xvf $TAR_FILE -C /var/lib/tftpboot/


	case "$BOOT_MODE" in
	"uefi")
		mkdir /var/lib/tftpboot/${EFI}/casper/

		cp -f /tmpmnt/casper/Image /var/lib/tftpboot/${EFI}/casper/
	       	cp -f /tmpmnt/casper/initrd.img /var/lib/tftpboot/${EFI}/casper/
		;;
	*)
		echo "Invalid boot mode!"
		exit 1
		;;
	esac

	chmod -R 777 /var/lib/tftpboot
}

config_bios() {
	cat > /opt/nfs/${CLIENT_ARCH}/post_custom.sh <<-EOF
#!/bin/bash
cd /cdrom/BIOS_TOOL;./klupdate --image=${BIOS}
cd /cdrom/BIOS_TOOL;bash force-reboot.sh
	EOF
	cp -a BIOS_TOOL /opt/nfs/${CLIENT_ARCH}
	sync
	[ ! -d /opt/nfs/${CLIENT_ARCH}/BIOS_TOOL/BIOS ] && mkdir /opt/nfs/${CLIENT_ARCH}/BIOS_TOOL/BIOS
	cp ${BIOS} /opt/nfs/${CLIENT_ARCH}/BIOS_TOOL/BIOS
	chmod 777 -R /opt/nfs/${CLIENT_ARCH}/BIOS_TOOL
}

config_nfs() {
	dpkg -l | grep -q nfs-kernel-server || apt-get install nfs-kernel-server -y > /dev/null

	cat > /etc/exports <<-EOF
/opt/osupdate *(rw,sync,no_root_squash,no_subtree_check)
/opt/nfs/ *(rw,sync,no_root_squash,no_subtree_check)
	EOF

	[ ! -d /opt/osupdate ] && mkdir /opt/osupdate && chmod 777 /opt/osupdate
	
	[ ! -d /opt/nfs ] && mkdir /opt/nfs && chmod 777 /opt/nfs
	[ -d /opt/nfs/${CLIENT_ARCH} ] && rm -rf /opt/nfs/${CLIENT_ARCH}
	mkdir /opt/nfs/${CLIENT_ARCH}
	chmod 777 /opt/nfs/${CLIENT_ARCH}

	echo -e "rsync data from iso to /opt/nfs/${CLIENT_ARCH}:\c"
	rsync -a /tmpmnt/ /opt/nfs/${CLIENT_ARCH} && echo -e "\t[ \033[32;1mDone\033[0m ]" || echo -e "\t[\033[31;1m Failed \033[0m]"

}

mount_all() {
	mount | grep -q tmpmnt && umount /tmpmnt > /dev/null 2>&1

	[ -d /tmpmnt ] || mkdir /tmpmnt
	mount $ISO /tmpmnt > /dev/null 2>&1 && echo -e "mount $ISO /tmpmnt:\t[ \033[32;1mSuccess\033[0m ]" || echo -e "mount $ISO /tmpmnt:\t[\033[31;1m Failed \033[0m]"

}

umount_all() {
	if umount -A /tmpmnt && rmdir /tmpmnt; then
		echo -e "umount /tmpmnt:\t[\033[32;1m Success \033[0m]"
	else
		echo -e "umount /tmpmnt:\t[\033[31;1m Failed \033[0m]"
	fi
}

main() {
	[ -f "$ISO" ] || { echo "No such iso: $ISO" && exit 1; }
	[ -f "$BIOS" ] || { echo "No such bios file: $BIOS" && exit 1; }
	mount_all
	shutdown_firewall
	config_dhcp
	config_tftp
	config_nfs
	config_bios
	umount_all

	echo -e "\nPXE server configuration:\t[\033[32;1m Complete \033[0m]\n"
}

main
