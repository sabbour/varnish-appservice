#!/bin/bash

# sudo chmod +x install_varnish.sh
# sudo install_varnish.sh -h google.com -a varnish123s -k 60ELpYRoGqv3N6LIT4v5cNOgVDVTbrbrOaPPHbhKHn+OP+myFA2nLK1iLkClELmaCDara+FPD+Sh9RLRCJoOmQ== -s varnishshare -m /mnt/azurefiles -v https://raw.githubusercontent.com/sabbour/varnish-appservice/master/varnish-appservice/nested/scripts/default.vcl

# Variables
BACKEND_HOSTNAME=""
AZUREFILES_ACCOUNTNAME=""
AZUREFILES_ACCOUNTKEY=""
AZUREFILES_SHARENAME=""
AZUREFILES_MOUNTPOINT=""
AZUREFILES_NFSTEMPLATE="//accountnameplaceholder.file.core.windows.net/sharenameplaceholder"
VCL_URL=""

help()
{
	echo "This script installs Varnish on the Ubuntu virtual machine image. Configuration is hosted on an Azure Files share."
	echo "Options:"
	echo "		-h backend hostname"
	echo "		-a azure files account name"
	echo "		-k azure files account key"
	echo "		-s azure files share"
	echo "		-m mount directory"
	echo "		-v vcl file url"
}

log()
{
	echo "$1"
}

install_required_packages()
{
	log "installing required packages"
	until apt-get -y update && apt-get -y install varnish cifs-utils
	do
		echo "installing required packages....."
		sleep 2
	done
}

configure_prerequisites()
{
	# Creating mount directory if it doesn't exist'
	log "mounting Azure Files share to ${AZUREFILES_MOUNTPOINT}"
	mkdir -p ${AZUREFILES_MOUNTPOINT}
	mount -t cifs ${AZUREFILES_NFSTEMPLATE} ${AZUREFILES_MOUNTPOINT} -o vers=3.0,username=${AZUREFILES_ACCOUNTNAME},password=${AZUREFILES_ACCOUNTKEY},dir_mode=0777,file_mode=0777

	# Adding to /etc/fstab to mount on boot, if it isn't there already'
	log "adding Azure Files mounting to /etc/fstab"
	if grep -q 'azure-files-varnish-mount' /etc/fstab ;
	then
		echo "Entry in fstab exists."
	else
		echo "#azure-files-varnish-mount" >> /etc/fstab
		echo "${AZUREFILES_NFSTEMPLATE} ${AZUREFILES_MOUNTPOINT} cifs vers=3.0,username=${AZUREFILES_ACCOUNTNAME},password=${AZUREFILES_ACCOUNTKEY},dir_mode=0777,file_mode=0777" >> /etc/fstab
	fi

	# Download the vcl template from the repo only if it doesn't exist, so that we don't accidentally override our configuation
	if [ ! -f ${AZUREFILES_MOUNTPOINT}/default.vcl ]; then
		log "downloading vcl template from ${VCL_URL} to ${AZUREFILES_MOUNTPOINT}/default.vcl"
		curl -o ${AZUREFILES_MOUNTPOINT}/default.vcl ${VCL_URL}

		log "configuring vcl template with backend ${BACKEND_HOSTNAME}"
		sed -i "s/BACKENDHOSTNAME/${BACKEND_HOSTNAME}/" ${AZUREFILES_MOUNTPOINT}/default.vcl
	else
		echo "vcl template exists in ${AZUREFILES_MOUNTPOINT}/default.vcl, skipping overwrite"
	fi	

	# Create varnish.service file if it doesn't exist
	if [ !  -f /etc/systemd/system/varnish.service ]; then
		log "creating varnish.service file in /etc/systemd/system/varnish.service"
		echo "[Service]
ExecStart=/usr/sbin/varnishd -j unix,user=vcache -F -a :80 -T localhost:6082 -f ${AZUREFILES_MOUNTPOINT}/default.vcl -S /etc/varnish/secret -s malloc,256m" >> /etc/systemd/system/varnish.service
	else
		echo "service exists in /etc/systemd/system/varnish.service, skipping overwrite"
	fi
}

start_varnish() {
	log "starting varnish.service"
	# Start the newly created varnish.service and make it run at boot
	systemctl start varnish.service
	systemctl enable varnish.service

	# Restart systemd and varnish
	log "restarting systemd and varnish"
	systemctl daemon-reload
	systemctl restart varnish
}

log "Begin execution of Varnish installation script extension on ${HOSTNAME}"

if [ "${UID}" -ne 0 ];
then
    log "Script executed without root permissions"
    echo "You must be root to run this program." >&2
    exit 3
fi

# Step 1, parse parameters and fill the variables
# Parse script parameters
while getopts ":h:k:a:s:m:v:" optname; do
	# Log input parameters to facilitate troubleshooting
	log "Option $optname set with value ${OPTARG}"

	case "${optname}" in
	h) BACKEND_HOSTNAME=${OPTARG};; # backend hostname
	a) AZUREFILES_ACCOUNTNAME=${OPTARG};; # azure files account name
	k) AZUREFILES_ACCOUNTKEY=${OPTARG};; # azure files account key
	s) AZUREFILES_SHARENAME=${OPTARG};; # azure files share name
	m) AZUREFILES_MOUNTPOINT=${OPTARG};; # local mount directory name
	v) VCL_URL=${OPTARG};; # vcl file url
	\?) # Unrecognized option - show help
		echo -e \\n"Option -${BOLD}$OPTARG${NORM} not allowed."
		help
		exit 2
		;;
	esac
done

# Validate parameters
if [ "$BACKEND_HOSTNAME" == "" ] || [ "$AZUREFILES_ACCOUNTNAME" == "" ] || [ "$AZUREFILES_ACCOUNTKEY" == "" ] || [ "$AZUREFILES_SHARENAME" == "" ] || [ "$AZUREFILES_MOUNTPOINT" == "" ] || [ "$VCL_URL" == "" ];
then
	log "Script executed without required parameters"
	echo "You must provide all required parameters." >&2
	exit 3
fi


# Construct the NFS location from the account and share names passed
AZUREFILES_NFSTEMPLATE="${AZUREFILES_NFSTEMPLATE/accountnameplaceholder/$AZUREFILES_ACCOUNTNAME}"
AZUREFILES_NFSTEMPLATE="${AZUREFILES_NFSTEMPLATE/sharenameplaceholder/$AZUREFILES_SHARENAME}"

log "Azure Files location: $AZUREFILES_NFSTEMPLATE"

# Step 2, install required packages
install_required_packages

# Step 3, configure prerequisites
configure_prerequisites

# Step 4, start Varnish
start_varnish