SSH_DIRECTORY="$HOME/.ssh"
SSH_APPLICATION_DIRECTORY="$SSH_DIRECTORY/applications"



function parameters__process {
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
					>&2 printf '%b\n' "${FUNCNAME[0]}: Required parameters not provided"
					return 1
				fi

				break
				;;
		esac

		shift
	done


	if [ "$( type -t "$case_function" )" != "function" ]; then
		>&2 printf '%b\n' "${FUNCNAME[0]}: Parameter \"--case-function\" must be a function name"
		return 1;
	fi


	local stop_processing=

	while [ "$1" ]; do
		local arg="$1"
		local arg_full="$arg"
		local arg_value=""

		if [ ! "$stop_processing" ] && [[ "$arg" =~ ^"-" ]]; then
			if [ "$arg" = "--" ]; then
				stop_processing=true
				shift
				continue
			fi

			if [[ "$arg" =~ [^"-"] ]]; then
				arg="$( printf '%s' "$arg" | sed 's/^-*//' )"

				if [[ "$arg" =~ "=" ]]; then
					local arg_value_array=( ${arg/"="/" "} )

					arg="${arg_value_array[0]}"
					arg_value="${arg_value_array[1]}"
				else
					if [[ ! " ${options_no_value[@]} " =~ " $arg " ]]; then
						if [ "$2" ] && [[ ! "$2" =~ ^"-" ]]; then
							arg_value="$2"
							shift
						fi
					fi
				fi
			fi
		fi

		"$case_function"

		shift
	done
}



function url__get_domain_name {
	local url="$1"

	local grep_command="grep -oP"

	local domain_regex="^(.*:\/\/)?(.*@)?\K[^:/]*"
	local domain_name_regex="\K[^.@]*(?=\.[^.]*$)"

	local domain="$( echo "$url" | $grep_command "$domain_regex" )"
	local domain_name="$( echo "$domain" | $grep_command "$domain_name_regex" )"

	echo "$domain_name"
}

function url__is_ssh {
	if [[ "$1" =~ ^"git@"|("git"|"ssh")"://" ]]; then
		return 0
	fi

	return 1
}




function git__export_ssh_command {
	if [ "$1" ]; then
		export GIT_SSH_COMMAND="$1"
	else
		unset GIT_SSH_COMMAND
	fi
}

function git__clone {
	local args=( "$@" )

	local git_ssh_command=""
	local git_ssh_command_old="$GIT_SSH_COMMAND"


	local repo_url=""

	for arg in "${args[@]}"; do
		if url__is_ssh "$arg"; then
			repo_url="$arg"
		fi
	done

	if [ ! "$repo_url" ]; then
		git clone "$@"

		return $?
	fi


	local application="$( url__get_domain_name "$repo_url" )"
	local application_ssh_directory="$SSH_APPLICATION_DIRECTORY/$application"


	local ssh_keys=()

	if [ -d "$SSH_DIRECTORY" ]; then
		for ssh_key_path in "$SSH_DIRECTORY/"*; do
			if [ -f "$ssh_key_path" ]; then
				local ssh_key_path_basename="$( basename "$ssh_key_path" )"

				if [[ "$ssh_key_path_basename" =~ ^"id" ]] && [[ ! "$ssh_key_path_basename" =~ ".pub"$ ]]; then
					ssh_keys+=( "$ssh_key_path" )
				fi
			fi
		done
	fi

	if [ -d "$application_ssh_directory" ]; then
		for application_ssh_key_path in "$application_ssh_directory/"*; do
			if [ -f "$application_ssh_key_path" ] && [[ ! "$application_ssh_key_path" =~ ".pub"$ ]]; then
				ssh_keys+=( "$application_ssh_key_path" )
			fi
		done
	fi


	for ssh_key in "${ssh_keys[@]}"; do
		export GIT_SSH_COMMAND="ssh -i \"$ssh_key\""

		git ls-remote "$repo_url" >/dev/null 2>&1

		if [ $? -eq 0 ]; then
			git_ssh_command="$GIT_SSH_COMMAND"

			break
		else
			git__export_ssh_command "$git_ssh_command_old"
		fi
	done


	local clone_output=""
	local clone_return_value=""
	local repo_dir=""

	clone_output="$( git clone --progress "$@" 2>&1 )"
	clone_return_value=$?

	if [ "$git_ssh_command" ] && [ "$clone_return_value" -eq 0 ]; then
		local cloning_into_output="$( printf '%b' "$clone_output" | head -1 )"

		if [[ "$cloning_into_output" =~ ^"Cloning into" ]]; then
			repo_dir="$( printf '%s' "$cloning_into_output" | grep -oP "'.*?'" )"
			repo_dir="${repo_dir%\'}"
			repo_dir="${repo_dir#\'}"
			repo_dir+="/.git"

			git --git-dir="$repo_dir" config core.sshCommand "$git_ssh_command"
		fi
	fi

	printf '%b\n' "$clone_output"


	git__export_ssh_command "$git_ssh_command_old"


	return "$clone_return_value"
}




function ssh__generate_key {
	local application=""
	local type="ed25519"
	local type_arg="t"
	local user=""

	local ssh_keygen_args=()


	function ssh__generate_key__case_function {
		case "$arg" in
			"application")
				application="$arg_value"
				;;
			"$type_arg")
				type="$arg_value"
				;;
			"user")
				user="$arg_value"
				;;
			*)
				ssh_keygen_args+=( "$arg_full" "$arg_value" )
				;;
		esac
	}

	parameters__process \
		--case-function="ssh__generate_key__case_function" \
		"$@"


	ssh_keygen_args+=( "-$type_arg" "$type" )


	local output_path=""

	if [ "$application" ]; then
		output_path="$SSH_APPLICATION_DIRECTORY/$application"
	else
		output_path="$SSH_DIRECTORY"
	fi

	mkdir --parents "$output_path"

	local access_check_dir="$output_path"

	while [ "$access_check_dir" != "$( dirname "$SSH_DIRECTORY" )" ]; do
		chmod 700 "$access_check_dir"

		access_check_dir="$( dirname "$access_check_dir" )"
	done

	output_path+="/${user:-"id"}--$type.pem"


	printf '%b\n\n' "Creating $type key: \"$output_path\""

	ssh-keygen \
		-C "$application-$user--$( hostname )" \
		-f "$output_path" \
		-t "$type"
}



alias c="clear"
alias e="exit"
alias sb="source $HOME/.bashrc"

alias dcs="./*/manage.py collectstatic --no-input"
alias drs="./*/manage.py runserver 0.0.0.0:8000"

alias ga="git add"
alias gc="git commit"
alias gcl="git__clone"
alias gco="git checkout"
alias gp="git push"
alias gpl="git pull"
alias gs="git status"

alias sshg="ssh__generate_key"
