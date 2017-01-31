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

parse_and_validate_parameters()
{
	# Parse script parameters
	while getopts :h:k:a:s optname; do

		# Log input parameters to facilitate troubleshooting
		log "Option $optname set with value ${OPTARG}"

		case $optname in
		h) # backend hostname
			BACKEND_HOSTNAME=${OPTARG}
			;;
		a) # azure files account name
			AZUREFILES_ACCOUNTNAME=${OPTARG}		
			;;
		k) # azure files account key
			AZUREFILES_ACCOUNTKEY=${OPTARG}
			;;
		s) # azure files share name
			AZUREFILES_SHARENAME=${OPTARG}
			;;
		m) # local mount directory name
			AZUREFILES_MOUNTPOINT=${OPTARG}
			;;			
		v) # vcl file url
			VCL_URL=${OPTARG}
			;;
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
}

install_required_packages()
{
	log "installing required packages"
	until apt-get -y update && apt-get -y install varnish cifs-utils do
		echo "installing required packages....."
		sleep 2
	 done
}

configure_prerequisites()
{
	log "mounting Azure Files share"
	mkdir ${AZUREFILES_MOUNTPOINT}
	mount -t cifs ${AZUREFILES_NFSTEMPLATE} ${AZUREFILES_MOUNTPOINT} -o vers=3.0,username=${AZUREFILES_ACCOUNTNAME},password=${AZUREFILES_ACCOUNTKEY},dir_mode=0777,file_mode=0777

	log "adding Azure Files mounting to /etc/fstab"
	echo "${AZUREFILES_NFSTEMPLATE} ${AZUREFILES_MOUNTPOINT} cifs vers=3.0,username=${AZUREFILES_ACCOUNTNAME},password=${AZUREFILES_ACCOUNTKEY},dir_mode=0777,file_mode=0777" >> /etc/fstab
	mount -a

	log "downloading vcl template from ${VCL_URL} to ${AZUREFILES_MOUNTPOINT}/default.vcl"
	curl -o ${AZUREFILES_MOUNTPOINT}/default.vcl ${VCL_URL}

	log "configuring vcl template with backend ${BACKEND_HOSTNAME}"
	sed -i "s/BACKENDHOSTNAME/${BACKEND_HOSTNAME}" ${AZUREFILES_MOUNTPOINT}/default.vcl

	log "creating varnish.service file in /etc/systemd/system/varnish.service"
	echo "[Service]
ExecStart=/usr/sbin/varnishd -j unix,user=vcache -F -a :80 -T localhost:6082 -f ${AZUREFILES_MOUNTPOINT}/default.vcl -S /etc/varnish/secret -s malloc,256m" >> /etc/systemd/system/varnish.service
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
parse_and_validate_parameters

# Step 2, install required packages
install_required_packages

# Step 3, configure prerequisites
configure_prerequisites

# Step 4, start Varnish
start_varnish