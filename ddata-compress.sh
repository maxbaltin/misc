#!/bin/bash
############
# This script cloning directory tree from SOURCE to TARGET, then archive every file from source individually    
# 	so that those could be read like regular files by utils like [b,x]zcat or by pandas read_sql
# Limitations: only local paths currrntly supported, despite rsync used to copy the tree. 
# Variables: SOURCE, TARGET, archiver of choose (both CMD and EXT should be set), 
#	     OVERWRITE existing archives: check (using md5sum), skip, or overwrite (if not set at all) 
# Prereqs: sudo apt install rsync tree gzip bzip2 pbzip2 xz-utils pxz 
###########
[[ -r ~/.zshrc ]] && source ~/.zshrc || source ~/.bashrc

SCRIPTPATH=$(cd $(dirname $( [[ -L $0 ]] && readlink -n $0 || echo "$0" )); pwd -P)

TIME=$(date +%Y%m%d_%H%M%S)
HOST=$(hostname)

##  some colors
BLACK=$(tput setaf 0); RED=$(tput setaf 1); GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3); LIME_YELLOW=$(tput setaf 190);
POWDER_BLUE=$(tput setaf 153); BLUE=$(tput setaf 4); MAGENTA=$(tput setaf 5); CYAN=$(tput setaf 6); WHITE=$(tput setaf 7);
BRIGHT=$(tput bold); NORMAL=$(tput sgr0); BLINK=$(tput blink); REVERSE=$(tput smso); UNDERLINE=$(tput smul)

####### SET ENVs here

SOURCE=${SOURCE:-/var/data/in}
TARGET=${TARGET:-/var/data/shared/ddata-export-bz2}

OVERWRITE="${OVERWRITE:-check}" #check, skip, default: overwrite

# Set correct pair of cmd+file ext for archiver choosen:
# gzip:
#CMD="${CMD:-gzip -9 -v -l}"
#EXT="${EXT:-gz}"

# parallel xz (replace with xz -v -9 for regular one) 
#CMD="${CMD:-pxz -v -9 -D1}"
#EXT="${EXT:-xz}"

# parallel bzip2 (replace pbzip2 to bzip2 for regular one)
CMD="${CMD:-pbzip2 -v}"
EXT="${EXT:-bz2}"

####################################################

echo "Copy ${SOURCE} tree underneath ${TARGET}"
[[ -d "${TARGET}" ]] || mkdir -p -- ${TARGET}
# using rsync here to avoid known issues with dir names (spaces etc), simplify paths management
# penalty is performance
rsync -a -f"+ */" -f"- *" ${SOURCE}/ ${TARGET}/

echo "Saving source tree as ${SCRIPTPATH}/${TIME}_source_tree.txt"
tree -df ${SOURCE} >${SCRIPTPATH}/${TIME}_source_tree.txt
tree -afQN ${SOURCE} >${SCRIPTPATH}/${TIME}_source_full_tree.txt
tail -n1 ${SCRIPTPATH}/${TIME}_source_tree.txt

echo "Saving target tree as ${SCRIPTPATH}/${TIME}_target_tree.txt"
tree -df ${TARGET} >${SCRIPTPATH}/${TIME}_target_tree.txt
tail -n1 ${SCRIPTPATH}/${TIME}_target_tree.txt

echo "***"
echo "Saving list of files from ${SOURCE}"
find ${SOURCE}/ -type f >${SCRIPTPATH}/${TIME}_source_files.txt

echo "Starting the process line by line from ${SCRIPTPATH}/${TIME}_source_files.txt"

function compress-to-stdout(){
# function archives a file ($sfile, $1) using stdout redirection (gzip|xz|bzip2 -c ),
#	so it ALWAYS overwrite target file without a warning
# $1: source file path; default if no $1: $sfile
# $2: target file path; default if no $2: $tfile
# WARN: this won't work correctly for filenames with spaces, hence this is currently just stub, 
# 	don't use with args $1, $2 if such filenames expected, 
#	this should be reworked to call with array like 
#	args=("$path1" "path2"); func "${args[@])"
#	coupled with string to array parser in the function
#
	local s=${1:-${sfile}}
	local t=${2:-${tfile}}

	$CMD -c "${s}" >"${t}"
        
	#echo "Resulting file:"
        #ls -lah "${t}"

	#Checking resulted file:
        chksum-compare
        if [[ $? -eq 0 ]]; then
		echo "${BRIGHT}${GREEN} MD5 matches, keeping resulted:"
                ls -lah "${t}"
                echo "${NORMAL}"
        else
                echo "${BRIGHT}${RED} MD5 failed, removing bad file and starting over:"
                ls -lah "${t}"
                echo "${NORMAL}"

                compress-to-stdout
		# of course, this potentially creates an loop cycle easy to avoid with some like:
	        #	(( c++ )) && (( c >= 5 )) && exit 1
		# but we want to be quite sure every checksum is correct, so keeping it in danger for now
        fi
}

function chksum-compare(){
# function to verify md5 of archived file ($tfile, $2) against original file ($sfile, $2)
# returns exit code ($?) of md5sum command, which also prints some output
# $1: source file path; default if no $1: $sfile
# $2: target file path; default if no $2: $tfile
# WARN: this won't work correctly for filenames with spaces, hence this is currently just stub, 
#       don't use with args $1, $2 if such filenames expected, 
#       this should be reworked to call with array like 
#       args=("$path1" "path2"); func "${args[@])"
#       coupled with string to array parser in the function
#
	local s=${1:-${sfile}}
	local t=${2:-${tfile}}
	
	local zip="$t"
	local txt="$s"
	local bin="cat"
	local cksum=""

	#select cat binary
	case "${zip##*.}" in
		bz2) bin="bzcat" ;;
		xz)  bin="xzcat" ;;
		gz)  bin="zcat"  ;;
		*)   bin="cat"   ;;
	esac

	cksum="$(${bin} "${zip}" | md5sum | awk '{print $1}')"
	echo "${zip} md5: ${cksum}"

	echo "${cksum} ${txt}" | md5sum -c -
	# don't add more commands here: 
	# main code using exit code of the latest md5sum command 
	# as an overall function result
}


while IFS= read file; do 
	echo "************"
	echo "Source file:"
	ls -lah "${file}"
	
	sfile="$file"
	tfile="${TARGET}${file#${SOURCE}}${EXT:+.${EXT}}"
	
	if [[ -e "${tfile}" ]]; then 
		echo "Target file ${tfile} exists, ${OVERWRITE}ing"
		case "${OVERWRITE}" in
			check|test) 
				#$CMD --test "${tfile}" || compress-to-stdout
				chksum-compare
				if [[ $? -eq 0 ]]; then
					echo "${BRIGHT}${GREEN} MD5 matches, skipping ${sfile}. Leaving existing:"
					ls -lah "${tfile}"
					echo "${NORMAL}"
					
					continue
				else
					echo "${BRIGHT}${RED} MD5 failed, overwriting ${tfile}:"
					ls -lah "${tfile}"
					echo "${NORMAL}"
					
					compress-to-stdout
				fi	
				;;
			skip|no|false)
				continue
				;;
			*) 	compress-to-stdout
				;;
		esac
	else
	       compress-to-stdout
	fi
	
done <${SCRIPTPATH}/${TIME}_source_files.txt 


echo "Saving list of files from ${TARGET}"
find ${TARGET}/ -type f >${SCRIPTPATH}/${TIME}_target_files.txt
tree -afQN ${TARGET} >${SCRIPTPATH}/${TIME}_target_full_tree.txt

echo "Simple resulting compare of full_trees"
echo "Source:"
tail -n1 ${SCRIPTPATH}/${TIME}_source_full_tree.txt
echo "Target:"
tail -n1 ${SCRIPTPATH}/${TIME}_target_full_tree.txt


