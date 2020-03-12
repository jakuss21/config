SSH_DIRECTORY="$HOME/.ssh"



function parameters_process {
	local case_function=""
	local options_no_value=()

	while [ "$1" ]; do
		case "$1" in
			"--case-function"*)
				case_function="${1/"--case-function="/""}"
				;;
			"--options-no-value"*)
				options_no_value=( ${1/"--options-no-value="/""} )
				;;
			*)
				if [ ! "$case_function" ]; then
					echo >&2 "${FUNCNAME[0]}: Required parameters not provided"
					return 1
				fi

				break
				;;
		esac

		shift
	done


	if [ "$( type -t "$case_function" )" != "function" ]; then
		echo >&2 "${FUNCNAME[0]}: First parameter must be case function name"
		return 1;
	fi


	local stop_processing=

	while [ "$1" ]; do
		local arg="$1"
		local value=""

		if [ ! "$stop_processing" ] && [[ "$arg" =~ ^"-" ]]; then
			if [ "$arg" = "--" ]; then
				stop_processing=true
				shift
				continue
			fi

			if [ "$arg" != "-" ]; then
				arg="$( echo "$arg" | sed 's/^-*//' )"

				if [[ "$arg" =~ "=" ]]; then
					local arg_value_array=( ${arg/"="/" "} )

					arg="${arg_value_array[0]}"
					value="${arg_value_array[1]}"
				else
					if [[ ! " ${options_no_value[@]} " =~ " $arg " ]]; then
						if [ "$2" ] && [[ ! "$2" =~ ^"-" ]]; then
							value="$2"
							shift
						fi
					fi
				fi
			fi
		fi

		"$case_function" "$arg" "$value"

		shift
	done
}



function get_url_domain_name {
	local url="$1"

	local grep_command="grep -oP"

	local domain_regex="^(.*:\/\/)?(.*@)?\K[^:/]*"
	local domain_name_regex="\K[^.@]*(?=\.[^.]*$)"

	local domain="$( echo "$url" | $grep_command "$domain_regex" )"
	local domain_name="$( echo "$domain" | $grep_command "$domain_name_regex" )"

	echo "$domain_name"
}




function git__in_directory {
	git rev-parse --absolute-git-dir >/dev/null 2>&1

	return $?
}

function git__clone {
	local args=( "$@" )

	local default_ssh_key="$SSH_DIRECTORY/id_rsa"

	local ssh_url=""
	local ssh_keys=()

	for arg in "${args[@]}"; do
		if [[ "$arg" =~ "@" ]]; then
			ssh_url="$arg"
			break
		fi
	done

	if [ -d "$SSH_DIRECTORY" ]; then
		if [ "$ssh_url" ]; then
			local ssh_domain_name="$( get_url_domain_name "$ssh_url" )"

			local ssh_key_domain_directory="$SSH_DIRECTORY/$ssh_domain_name"

			if [ -d "$ssh_key_domain_directory" ]; then
				for domain_ssh_key in "$ssh_key_domain_directory/"*; do
					if [[ ! "$domain_ssh_key" =~ ".pub"$ ]]; then
						ssh_keys+=("$domain_ssh_key")
					fi
				done
			fi
		fi
	fi

	if [ -f "$default_ssh_key" ]; then
		ssh_keys+=("$default_ssh_key")
	fi

	for ssh_key in "${ssh_keys[@]}"; do
		export GIT_SSH_COMMAND="ssh -i \"$ssh_key\""

		git ls-remote "$ssh_url" > /dev/null 2>&1

		if [ $? -eq 0 ]; then
			break
		else
			unset GIT_SSH_COMMAND
		fi
	done

	git clone "$@"

	unset GIT_SSH_COMMAND
}



alias c="clear"
alias e="exit"
alias sb="source $HOME/.bashrc"

alias dcs="./*/manage.py collectstatic --no-input"
alias drs="./*/manage.py runserver 0.0.0.0:8000"

alias gc="git__clone"
alias gs="git status"
