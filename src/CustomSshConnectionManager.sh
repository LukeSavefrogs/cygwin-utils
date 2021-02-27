# Automated SSH Login Connection
# 	In caso si utilizzi la stessa password per tutti i server (come non succede ASSOLUTAMENTE MAI nel progetto PICO) 
#		permette di automatizzare e velocizzare notevolmente la procedura di Login semplicemente creando un alias
#		come segue: 
#		
#		alias youraliasname='aliasCalledBy=youraliasname CustomSshConnectionManager utenza password';
#	
#	Per collegarsi in ssh alla macchina desiderata bastera quindi digitare semplicemente: youraliasname nomemacchina
#
#	NOTA: 	
#		La variabile `aliasCalledBy` impostata prima di richiamare la funzione core `CustomSshConnectionManager` serve
#		unicamente per mostrare a video da che alias è stata richiamata. 
#
#	
#	Per definire gli alias (preset) da generare, utilizzare il codice di seguito nel proprio file ~/.bashrc, sostituendo i valori corretti. 
#
#	Esempio:
# 		declare -A SSH_PRESET=(
#			[your_alias_name]='your_username your_password'
#		);
#		eval "$(CustomSshConnectionManager init)";
#
#	Autore:
#		Luca Salvarani - luca.salvarani@ibm.com
#
CustomSshConnectionManager() (
	local -r default='\033[0m';
	local -r red='\033[31m';
	local -r yellow='\033[33m'
	local -r cyan='\033[36m';
	local -r underlined='\033[4m';

	local -r SCRIPT_NAME="${FUNCNAME[0]}";
	local -r SCRIPT_VERSION="2.0.0";
	local -r SCRIPT_URL="";

	main () {
		local action="${1}";

		if [[ "${action,,}" == "init" ]]; then
			__init_aliases_completion;
			
		else
			__connect "$@";
		fi;
	}

	__init_aliases_completion () {
		function _complete_ssh_hosts () {
			COMPREPLY=()
			cur="${COMP_WORDS[COMP_CWORD]}"
			comp_ssh_hosts=$(
				cat ~/.ssh/known_hosts 2>/dev/null | \
					cut -f 1 -d ' ' | \
					sed -e 's/,.*//g' | \
					grep -v '^#' | \
					uniq | \
					grep -v "\[" ;
				cat ~/.ssh/config 2>/dev/null | \
					grep "^Host " | \
					awk '{print $2}'
			);
			COMPREPLY=( $(compgen -W "${comp_ssh_hosts}" -- $cur))
			return 0
		}

		declare -f _complete_ssh_hosts;
		for aliasName in "${!SSH_PRESET[@]}"; do
			command="alias ${aliasName}='aliasCalledBy=${aliasName} CustomSshConnectionManager ${SSH_PRESET[$aliasName]}';";
			echo "$command";

			command="complete -F _complete_ssh_hosts '${aliasName}'";
			echo "$command";
			
			# eval "alias ${aliasName}='aliasCalledBy='${aliasName}' CustomSshConnectionManager ${SSH_PRESET[$aliasName]}';";
			# complete -F _complete_ssh_hosts "${aliasName}";
		done
	};

	__connect () {
		local username="$1";
		local password="$2";
		local macchina="$3";

		local aliasName="${aliasCalledBy:?}";

		if [ -z "$username" ] ||  [ -z "$password" ] ||  [ -z "$macchina" ]; then  
			printf "${red}ERRORE${default} - Sintassi non valida:\n\n"; 
			__usage;	
			return 1; 
		fi;

		shift 3;
		
		# Controllo delle dipendenze
		Packages.checkDependencies "sshpass" || {
			Utils.user_confirmation "Install 'sshpass'?" || {
				printf "${red}[ ERROR ]${default} - Aborted\n\n";
				return 1;
			};
			Packages.install_sshpass || {
				printf "${red}[ ERROR ]${default} - Installation failed\n\n";
				return 1;
			}

			printf "${green}[ SUCCESS ]${default} - Installation completed\n\n";
		}

		# Controlla prima se la macchina passata come parametro non è un IP
		macchina=$(Connectivity.resolvePartialHostname "$macchina");
		if [[ $? -ne 0 ]]; then
			return 1;
		fi;

		# Regola PICO
		[[ "${macchina,,}" =~ (trnx|c2cx) ]] && username="${username^^}";


		printf "${cyan}[ INFO ]${default} - Logging in as %s (%s)\n" "${username}" "${aliasName}" >&2;
		Connectivity.checkHostnameReachable "${macchina}" || {
			printf "${red}[ ERROR ]${default} - Hostname '%s' not reachable\n" "${macchina}";
			return 2;
		};

		if Connectivity.checkAccess "$macchina" "$username" "$password"; then
			sshpass -p "$password" ssh -l "${username}" "${macchina}" "$@";
			return 0;
		else
			printf "${cyan}[ INFO ]${default} - Password script %s non valida. Ripiego sull'ssh normale\n" "$SCRIPT_NAME" >&2;
			ssh -l "${username}" "${macchina}" "${@}";

			return 0;
		fi
	}

	__usage () {
		printf "${yellow}USAGE${default}:\n"
		printf "\t%s ${underlined}USERNAME${default} ${underlined}PASSWORD${default} ${underlined}MACCHINA${default}\n" "$SCRIPT_NAME"; 
		printf "\t%s init\n" "$SCRIPT_NAME"; 
	}

	# __check_updates () {
	# 	local content="";
	# 	if command -v "curl" >/dev/null 2>&1; then
	# 		content=$(timeout 5 curl --silent --show-error --location --ssl-no-revoke "${NEW_BIN_NAME}");

	# 	elif command -v "wget" >/dev/null 2>&1; then
	# 		content=$(timeout 5 wget --quiet "${NEW_BIN_NAME}");

	# 	else
	# 		printf "${red}ERROR${default} - No binary found for download!\n\n";
	# 		printf "Aborted\n";

	# 		return 10;
	# 	fi
	# 	[[ -z "$content" ]] && return 5;

	# 	local remote_version="$(echo "$content" | grep "SCRIPT_VERSION=" | cut -d= -f2 | tr -d ";" | tr -d '"' | tr -d "'")";
	# 	[[ "$remote_version" != "$SCRIPT_VERSION" ]] && {
	# 		printf "${green}SUCCESS${default} - Update completed\n\n";
	# 		echo "$content" > CustomSshConnectionManager.sh;
	# 	}
	# }

	# Check if program is installed
	function Packages.checkDependencies () {
		# Colors
		local red='\033[0;31m';
		local green='\033[0;32m';
		local yellow='\033[0;33m';
		local default='\033[0m';

		# Declare variables
		local progs="$@";
		local not_found_counter=0;
		local total_programs=$(echo "$progs" | wc -w);

		# Check every program
		for p in ${progs}; do
			command -v "$p" >/dev/null 2>&1 || {
				printf "${yellow}WARNING${default} - Program required is not installed: $p\n";
			
				not_found_counter=$(expr $not_found_counter + 1);
			}
		done

		# Print error
		[[ $not_found_counter -ne 0 ]] && {
			printf "\n"
			printf "${red}ERROR${default} - %d of %d programs were missing. Execution aborted\n" "$not_found_counter" "$total_programs";

			return 1;
		}

		return 0;
	}

	# Install SSHPASS
	function Packages.install_sshpass () {
		printf "Download: ";
		downl_result=$(wget -q http://sourceforge.net/projects/sshpass/files/latest/download -O sshpass.tar.gz 2>&1) && printf "\033[0;32mOK\033[0m\n" || {
			printf "\033[0;31mErrore\033[0m\n\n";
			echo "$downl_result";
			exit 1;
		}

		tar -xvf sshpass.tar.gz
		cd sshpass-1.06 || {
			printf "\033[0;31mDirectory non esistente\033[0m. Estrazione file .tar fallita\n\n";

			exit 1;
		}

		printf "Configurazione: "
		confg_result=$(./configure 2>&1) && printf "\033[0;32mOK\033[0m\n" || {
			printf "\033[0;31mErrore\033[0m\n\n";
			echo "$confg_result";

			exit 1;
		}


		printf "Compilazione: ";
		compi_result=$($(which sudo >/dev/null 2>&1 && printf "sudo") make install 2>&1) && printf "\033[0;32mOK\033[0m\n" || {
			printf "\033[0;31mErrore\033[0m\n\n";
			echo "$compi_result";

			exit 1;
		}


		printf "\033[0;32mInstallazione completata con successo\033[0m\n\n";
	}

	# Checks if user can access to a remote system using SSH (USERNAME/PASSWORD are correct)
	function Connectivity.checkAccess () {
		local macchina="$1";
		local username="$2";
		local password="$3";
		sshpass -p "$password" ssh -tt -o LogLevel=QUIET -o StrictHostKeyChecking=No -o ConnectTimeout=5 -l "$username" "$macchina" "uname" > /dev/null 2>&1
	}

	# Checks if the remote system is reachable via SSH
	function Connectivity.checkHostnameReachable {
		ssh -o PubkeyAuthentication=no -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no -o ChallengeResponseAuthentication=no -o ConnectTimeout=5 -o StrictHostKeyChecking=No "$1" 2>&1 | grep -q "Permission denied";
	}

	function Connectivity.resolvePartialHostname {
		local macchina="$*";
		[[ -z "${macchina/[:space:]/}" ]] && return 1;

		local hosts_clean="$(grep -vE  '^\s*#' /etc/hosts | sed 's/#.*//g')";

		if [[ ! "$macchina" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
			full_hostname=$(echo "$hosts_clean" | grep -w "$macchina");
			
			# Controlla se NEL FILE HOSTS esiste la macchina con il nome COMPLETO fornito (piu veloce rispetto a cercare tutte le volte con getent)
			if [[ -n "$full_hostname" ]]; then 
				echo "$full_hostname" | grep -wo "$macchina";
			else
				# Controlla se esiste la macchina con il nome PARZIALE fornito
				macchine_hosts=$(echo "$hosts_clean" | grep -i $macchina | awk -v macchina=$macchina '{$1=""; for(i = 1; i <= NF; i++) { if (match(tolower($i), tolower(macchina))) print $i; } }' | tr -d '\r' | sort -u | tr '\n' ' ' | tr -s ' ' | sed 's/^[[:blank:]]*//; s/[[:blank:]]*$//');

				# Se ha trovato macchine simili ma non quella esatta le mostra a video
				if [ -n "$macchine_hosts" ]; then

					# Se ha trovato SOLO UN risultato lo usa per entrare in ssh
					[[ "$(wc -w <<<"$macchine_hosts")" == 1 ]] && {
						printf "${cyan}[ INFO ]${default} - Macchina $macchina non trovata [ $macchine_hosts ]\n" >&2;
						echo "$macchine_hosts";
					} || {
						# Se ha trovato PIU DI UN risultato simile esce
						printf "${red}ERRORE${default} - Macchina $macchina non trovata [ $macchine_hosts ]\n" >&2;

						return 2;
					}
				else 
					result_getent=$(getent hosts "$macchina");
					
					[[ $? != 0 ]] && {			
						printf "${red}ERRORE${default} - Macchina $macchina non censita nel file hosts e non trovata tramite 'getent hosts'\n\n" >&2;
						
						return 1;
					}
					
					printf "${cyan}[ INFO ]${default} - Macchina $macchina non censita nel file hosts ma trovata tramite 'getent hosts' [ %s ]\n" "IP $(echo "$result_getent" | sed -n '1p' | awk '{print $1}')" >&2;
				fi;
			fi;
		fi;
		return 0;
	}

	function Utils.user_confirmation {
		prompt="$@";

		[[ -n "$prompt" ]] && printf "$prompt [Y/N] ";

		while read;	do
			[ -z "$REPLY" ] && {
				[[ -n "$prompt" ]] && printf "$prompt [Y/N] ";

				continue;
			}

			[[ ${REPLY,,} =~ ^[\s\t]*(y|s|si|yes)[\s\t]*$ ]] && break;

			return 1;
		done;
		printf "\n\n";

		return 0;
	}

	main "$@"
);
