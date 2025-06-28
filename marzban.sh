#!/usr/bin/env bash
set -e

INSTALL_DIR="/opt"
if [ -z "$APP_NAME" ]; then
    APP_NAME="marzban"
fi
APP_DIR="$INSTALL_DIR/$APP_NAME"
DATA_DIR="/var/lib/$APP_NAME"
COMPOSE_FILE="$APP_DIR/docker-compose.yml"
ENV_FILE="$APP_DIR/.env"
LAST_XRAY_CORES=10
USE_WILDCARD=false

colorized_echo() {
    local color=$1
    local text=$2
    
    case $color in
        "red")
        printf "\e[91m${text}\e[0m\n";;
        "green")
        printf "\e[92m${text}\e[0m\n";;
        "yellow")
        printf "\e[93m${text}\e[0m\n";;
        "blue")
        printf "\e[94m${text}\e[0m\n";;
        "magenta")
        printf "\e[95m${text}\e[0m\n";;
        "cyan")
        printf "\e[96m${text}\e[0m\n";;
        *)
            echo "${text}"
        ;;
    esac
}

update_env_var() {
    local key=$1
    local value=$2
    local env_file=$3

    # Check if the key exists (commented or uncommented, with optional spaces)
    if grep -q -E "^#?\s*${key}\s*=" "$env_file"; then
        # If it exists, update the line, removing any comment.
        # Using | as a delimiter to avoid issues with slashes in paths.
        sed -i -E "s|^#?\s*${key}\s*=.*|${key} = ${value}|" "$env_file"
    else
        # If it doesn't exist, append it to the file
        echo "${key} = ${value}" >> "$env_file"
    fi
}

check_running_as_root() {
    if [ "$(id -u)" != "0" ]; then
        colorized_echo red "This command must be run as root."
        exit 1
    fi
}

detect_os() {
    if [ -f /etc/lsb-release ]; then
        OS=$(lsb_release -si)
    elif [ -f /etc/os-release ]; then
        OS=$(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"')
    elif [ -f /etc/redhat-release ]; then
        OS=$(cat /etc/redhat-release | awk '{print $1}')
    elif [ -f /etc/arch-release ]; then
        OS="Arch"
    else
        colorized_echo red "Unsupported operating system"
        exit 1
    fi
}


detect_and_update_package_manager() {
    colorized_echo blue "Updating package manager"
    if [[ "$OS" == "Ubuntu"* ]] || [[ "$OS" == "Debian"* ]]; then
        PKG_MANAGER="apt-get"
        $PKG_MANAGER update
    elif [[ "$OS" == "CentOS"* ]] || [[ "$OS" == "AlmaLinux"* ]]; then
        PKG_MANAGER="yum"
        $PKG_MANAGER update -y
        $PKG_MANAGER install -y epel-release
    elif [ "$OS" == "Fedora"* ]; then
        PKG_MANAGER="dnf"
        $PKG_MANAGER update
    elif [ "$OS" == "Arch" ]; then
        PKG_MANAGER="pacman"
        $PKG_MANAGER -Sy
    elif [[ "$OS" == "openSUSE"* ]]; then
        PKG_MANAGER="zypper"
        $PKG_MANAGER refresh
    else
        colorized_echo red "Unsupported operating system"
        exit 1
    fi
}

install_package () {
    if [ -z $PKG_MANAGER ]; then
        detect_and_update_package_manager
    fi
    
    PACKAGE=$1
    colorized_echo blue "Installing $PACKAGE"
    if [[ "$OS" == "Ubuntu"* ]] || [[ "$OS" == "Debian"* ]]; then
        $PKG_MANAGER -y install "$PACKAGE"
    elif [[ "$OS" == "CentOS"* ]] || [[ "$OS" == "AlmaLinux"* ]]; then
        $PKG_MANAGER install -y "$PACKAGE"
    elif [ "$OS" == "Fedora"* ]; then
        $PKG_MANAGER install -y "$PACKAGE"
    elif [ "$OS" == "Arch" ]; then
        $PKG_MANAGER -S --noconfirm "$PACKAGE"
    else
        colorized_echo red "Unsupported operating system"
        exit 1
    fi
}

install_docker() {
    # Install Docker and Docker Compose using the official installation script
    colorized_echo blue "Installing Docker"
    curl -fsSL https://get.docker.com | sh
    colorized_echo green "Docker installed successfully"
}

detect_compose() {
    # Check if docker compose command exists
    if docker compose version >/dev/null 2>&1; then
        COMPOSE='docker compose'
    elif docker-compose version >/dev/null 2>&1; then
        COMPOSE='docker-compose'
    else
        colorized_echo red "docker compose not found"
        exit 1
    fi
}

install_marzban_script() {
    FETCH_REPO="naymintun800/Marzban-scripts"
    SCRIPT_URL="https://github.com/$FETCH_REPO/raw/master/marzban.sh"
    colorized_echo blue "Installing marzban script"
    curl -sSL $SCRIPT_URL | install -m 755 /dev/stdin /usr/local/bin/marzban
    colorized_echo green "marzban script installed successfully"
}

is_marzban_installed() {
    if [ -d $APP_DIR ]; then
        return 0
    else
        return 1
    fi
}

identify_the_operating_system_and_architecture() {
    if [[ "$(uname)" == 'Linux' ]]; then
        case "$(uname -m)" in
            'i386' | 'i686')
                ARCH='32'
            ;;
            'amd64' | 'x86_64')
                ARCH='64'
            ;;
            'armv5tel')
                ARCH='arm32-v5'
            ;;
            'armv6l')
                ARCH='arm32-v6'
                grep Features /proc/cpuinfo | grep -qw 'vfp' || ARCH='arm32-v5'
            ;;
            'armv7' | 'armv7l')
                ARCH='arm32-v7a'
                grep Features /proc/cpuinfo | grep -qw 'vfp' || ARCH='arm32-v5'
            ;;
            'armv8' | 'aarch64')
                ARCH='arm64-v8a'
            ;;
            'mips')
                ARCH='mips32'
            ;;
            'mipsle')
                ARCH='mips32le'
            ;;
            'mips64')
                ARCH='mips64'
                lscpu | grep -q "Little Endian" && ARCH='mips64le'
            ;;
            'mips64le')
                ARCH='mips64le'
            ;;
            'ppc64')
                ARCH='ppc64'
            ;;
            'ppc64le')
                ARCH='ppc64le'
            ;;
            'riscv64')
                ARCH='riscv64'
            ;;
            's390x')
                ARCH='s390x'
            ;;
            *)
                echo "error: The architecture is not supported."
                exit 1
            ;;
        esac
    else
        echo "error: This operating system is not supported."
        exit 1
    fi
}

send_backup_to_telegram() {
    if [ -f "$ENV_FILE" ]; then
        while IFS='=' read -r key value; do
            if [[ -z "$key" || "$key" =~ ^# ]]; then
                continue
            fi
            key=$(echo "$key" | xargs)
            value=$(echo "$value" | xargs)
            if [[ "$key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
                export "$key"="$value"
            else
                colorized_echo yellow "Skipping invalid line in .env: $key=$value"
            fi
        done < "$ENV_FILE"
    else
        colorized_echo red "Environment file (.env) not found."
        exit 1
    fi

    if [ "$BACKUP_SERVICE_ENABLED" != "true" ]; then
        colorized_echo yellow "Backup service is not enabled. Skipping Telegram upload."
        return
    fi

    local server_ip=$(curl -s ifconfig.me || echo "Unknown IP")
    local latest_backup=$(ls -t "$APP_DIR/backup" | head -n 1)
    local backup_path="$APP_DIR/backup/$latest_backup"

    if [ ! -f "$backup_path" ]; then
        colorized_echo red "No backups found to send."
        return
    fi

    local backup_size=$(du -m "$backup_path" | cut -f1)
    local split_dir="/tmp/marzban_backup_split"
    local is_single_file=true

    mkdir -p "$split_dir"

    if [ "$backup_size" -gt 49 ]; then
        colorized_echo yellow "Backup is larger than 49MB. Splitting the archive..."
        split -b 49M "$backup_path" "$split_dir/part_"
        is_single_file=false
    else
        cp "$backup_path" "$split_dir/part_aa"
    fi


    local backup_time=$(date "+%Y-%m-%d %H:%M:%S %Z")


    for part in "$split_dir"/*; do
        local part_name=$(basename "$part")
        local custom_filename="backup_${part_name}.tar.gz"
        local caption="📦 *Backup Information*\n🌐 *Server IP*: \`${server_ip}\`\n📁 *Backup File*: \`${custom_filename}\`\n⏰ *Backup Time*: \`${backup_time}\`"
        curl -s -F chat_id="$BACKUP_TELEGRAM_CHAT_ID" \
            -F document=@"$part;filename=$custom_filename" \
            -F caption="$(echo -e "$caption" | sed 's/-/\\-/g;s/\./\\./g;s/_/\\_/g')" \
            -F parse_mode="MarkdownV2" \
            "https://api.telegram.org/bot$BACKUP_TELEGRAM_BOT_KEY/sendDocument" >/dev/null 2>&1 && \
        colorized_echo green "Backup part $custom_filename successfully sent to Telegram." || \
        colorized_echo red "Failed to send backup part $custom_filename to Telegram."
    done

    rm -rf "$split_dir"
}

send_backup_error_to_telegram() {
    local error_messages=$1
    local log_file=$2
    local server_ip=$(curl -s ifconfig.me || echo "Unknown IP")
    local error_time=$(date "+%Y-%m-%d %H:%M:%S %Z")
    local message="⚠️ *Backup Error Notification*\n"
    message+="🌐 *Server IP*: \`${server_ip}\`\n"
    message+="❌ *Errors*:\n\`${error_messages//_/\\_}\`\n"
    message+="⏰ *Time*: \`${error_time}\`"


    message=$(echo -e "$message" | sed 's/-/\\-/g;s/\./\\./g;s/_/\\_/g;s/(/\\(/g;s/)/\\)/g')

    local max_length=1000
    if [ ${#message} -gt $max_length ]; then
        message="${message:0:$((max_length - 50))}...\n\`[Message truncated]\`"
    fi


    curl -s -X POST "https://api.telegram.org/bot$BACKUP_TELEGRAM_BOT_KEY/sendMessage" \
        -d chat_id="$BACKUP_TELEGRAM_CHAT_ID" \
        -d parse_mode="MarkdownV2" \
        -d text="$message" >/dev/null 2>&1 && \
    colorized_echo green "Backup error notification sent to Telegram." || \
    colorized_echo red "Failed to send error notification to Telegram."


    if [ -f "$log_file" ]; then
        response=$(curl -s -w "%{http_code}" -o /tmp/tg_response.json \
            -F chat_id="$BACKUP_TELEGRAM_CHAT_ID" \
            -F document=@"$log_file;filename=backup_error.log" \
            -F caption="📜 *Backup Error Log* - ${error_time}" \
            "https://api.telegram.org/bot$BACKUP_TELEGRAM_BOT_KEY/sendDocument")

        http_code="${response:(-3)}"
        if [ "$http_code" -eq 200 ]; then
            colorized_echo green "Backup error log sent to Telegram."
        else
            colorized_echo red "Failed to send backup error log to Telegram. HTTP code: $http_code"
            cat /tmp/tg_response.json
        fi
    else
        colorized_echo red "Log file not found: $log_file"
    fi
}

backup_service() {
    local telegram_bot_key=""
    local telegram_chat_id=""
    local cron_schedule=""
    local interval_hours=""

    colorized_echo blue "====================================="
    colorized_echo blue "      Welcome to Backup Service      "
    colorized_echo blue "====================================="

    if grep -q "BACKUP_SERVICE_ENABLED=true" "$ENV_FILE"; then
        telegram_bot_key=$(awk -F'=' '/^BACKUP_TELEGRAM_BOT_KEY=/ {print $2}' "$ENV_FILE")
        telegram_chat_id=$(awk -F'=' '/^BACKUP_TELEGRAM_CHAT_ID=/ {print $2}' "$ENV_FILE")
        cron_schedule=$(awk -F'=' '/^BACKUP_CRON_SCHEDULE=/ {print $2}' "$ENV_FILE" | tr -d '"')

        if [[ "$cron_schedule" == "0 0 * * *" ]]; then
            interval_hours=24
        else
            interval_hours=$(echo "$cron_schedule" | grep -oP '(?<=\*/)[0-9]+')
        fi

        colorized_echo green "====================================="
        colorized_echo green "Current Backup Configuration:"
        colorized_echo cyan "Telegram Bot API Key: $telegram_bot_key"
        colorized_echo cyan "Telegram Chat ID: $telegram_chat_id"
        colorized_echo cyan "Backup Interval: Every $interval_hours hour(s)"
        colorized_echo green "====================================="
        echo "Choose an option:"
        echo "1. Reconfigure Backup Service"
        echo "2. Remove Backup Service"
        echo "3. Exit"
        read -p "Enter your choice (1-3): " user_choice

        case $user_choice in
            1)
                colorized_echo yellow "Starting reconfiguration..."
                remove_backup_service
                ;;
            2)
                colorized_echo yellow "Removing Backup Service..."
                remove_backup_service
                return
                ;;
            3)
                colorized_echo yellow "Exiting..."
                return
                ;;
            *)
                colorized_echo red "Invalid choice. Exiting."
                return
                ;;
        esac
    else
        colorized_echo yellow "No backup service is currently configured."
    fi

    while true; do
        printf "Enter your Telegram bot API key: "
        read telegram_bot_key
        if [[ -n "$telegram_bot_key" ]]; then
            break
        else
            colorized_echo red "API key cannot be empty. Please try again."
        fi
    done

    while true; do
        printf "Enter your Telegram chat ID: "
        read telegram_chat_id
        if [[ -n "$telegram_chat_id" ]]; then
            break
        else
            colorized_echo red "Chat ID cannot be empty. Please try again."
        fi
    done

    while true; do
        printf "Set up the backup interval in hours (1-24):\n"
        read interval_hours

        if ! [[ "$interval_hours" =~ ^[0-9]+$ ]]; then
            colorized_echo red "Invalid input. Please enter a valid number."
            continue
        fi

        if [[ "$interval_hours" -eq 24 ]]; then
            cron_schedule="0 0 * * *"
            colorized_echo green "Setting backup to run daily at midnight."
            break
        fi

        if [[ "$interval_hours" -ge 1 && "$interval_hours" -le 23 ]]; then
            cron_schedule="0 */$interval_hours * * *"
            colorized_echo green "Setting backup to run every $interval_hours hour(s)."
            break
        else
            colorized_echo red "Invalid input. Please enter a number between 1-24."
        fi
    done

    sed -i '/^BACKUP_SERVICE_ENABLED/d' "$ENV_FILE"
    sed -i '/^BACKUP_TELEGRAM_BOT_KEY/d' "$ENV_FILE"
    sed -i '/^BACKUP_TELEGRAM_CHAT_ID/d' "$ENV_FILE"
    sed -i '/^BACKUP_CRON_SCHEDULE/d' "$ENV_FILE"

    {
        echo ""
        echo "# Backup service configuration"
        echo "BACKUP_SERVICE_ENABLED=true"
        echo "BACKUP_TELEGRAM_BOT_KEY=$telegram_bot_key"
        echo "BACKUP_TELEGRAM_CHAT_ID=$telegram_chat_id"
        echo "BACKUP_CRON_SCHEDULE=\"$cron_schedule\""
    } >> "$ENV_FILE"

    colorized_echo green "Backup service configuration saved in $ENV_FILE."

    local backup_command="$(which bash) -c '$APP_NAME backup'"
    add_cron_job "$cron_schedule" "$backup_command"

    colorized_echo green "Backup service successfully configured."
    if [[ "$interval_hours" -eq 24 ]]; then
        colorized_echo cyan "Backups will be sent to Telegram daily (every 24 hours at midnight)."
    else
        colorized_echo cyan "Backups will be sent to Telegram every $interval_hours hour(s)."
    fi
    colorized_echo green "====================================="
}


add_cron_job() {
    local schedule="$1"
    local command="$2"
    local temp_cron=$(mktemp)

    crontab -l 2>/dev/null > "$temp_cron" || true
    grep -v "$command" "$temp_cron" > "${temp_cron}.tmp" && mv "${temp_cron}.tmp" "$temp_cron"
    echo "$schedule $command # marzban-backup-service" >> "$temp_cron"
    
    if crontab "$temp_cron"; then
        colorized_echo green "Cron job successfully added."
    else
        colorized_echo red "Failed to add cron job. Please check manually."
    fi
    rm -f "$temp_cron"
}

remove_backup_service() {
    colorized_echo red "in process..."


    sed -i '/^# Backup service configuration/d' "$ENV_FILE"
    sed -i '/BACKUP_SERVICE_ENABLED/d' "$ENV_FILE"
    sed -i '/BACKUP_TELEGRAM_BOT_KEY/d' "$ENV_FILE"
    sed -i '/BACKUP_TELEGRAM_CHAT_ID/d' "$ENV_FILE"
    sed -i '/BACKUP_CRON_SCHEDULE/d' "$ENV_FILE"

    local temp_cron=$(mktemp)
    crontab -l 2>/dev/null > "$temp_cron"

    sed -i '/# marzban-backup-service/d' "$temp_cron"

    if crontab "$temp_cron"; then
        colorized_echo green "Backup service task removed from crontab."
    else
        colorized_echo red "Failed to update crontab. Please check manually."
    fi

    rm -f "$temp_cron"

    colorized_echo green "Backup service has been removed."
}

backup_command() {
    local backup_dir="$APP_DIR/backup"
    local temp_dir="/tmp/marzban_backup"
    local timestamp=$(date +"%Y%m%d%H%M%S")
    local backup_file="$backup_dir/backup_$timestamp.tar.gz"
    local error_messages=()
    local log_file="/var/log/marzban_backup_error.log"
    > "$log_file"
    echo "Backup Log - $(date)" > "$log_file"

    if ! command -v rsync >/dev/null 2>&1; then
        detect_os
        install_package rsync
    fi

    rm -rf "$backup_dir"
    mkdir -p "$backup_dir"
    mkdir -p "$temp_dir"

    if [ -f "$ENV_FILE" ]; then
        while IFS='=' read -r key value; do
            if [[ -z "$key" || "$key" =~ ^# ]]; then
                continue
            fi
            key=$(echo "$key" | xargs)
            value=$(echo "$value" | xargs)
            if [[ "$key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
                export "$key"="$value"
            else
                echo "Skipping invalid line in .env: $key=$value" >> "$log_file"
            fi
        done < "$ENV_FILE"
    else
        error_messages+=("Environment file (.env) not found.")
        echo "Environment file (.env) not found." >> "$log_file"
        send_backup_error_to_telegram "${error_messages[*]}" "$log_file"
        exit 1
    fi

    local db_type=""
    local sqlite_file=""
    if grep -q "image: mariadb" "$COMPOSE_FILE"; then
        db_type="mariadb"
        container_name=$(docker compose -f "$COMPOSE_FILE" ps -q mariadb || echo "mariadb")

    elif grep -q "image: mysql" "$COMPOSE_FILE"; then
        db_type="mysql"
        container_name=$(docker compose -f "$COMPOSE_FILE" ps -q mysql || echo "mysql")

    elif grep -q "SQLALCHEMY_DATABASE_URL = .*sqlite" "$ENV_FILE"; then
        db_type="sqlite"
        sqlite_file=$(grep -Po '(?<=SQLALCHEMY_DATABASE_URL = "sqlite:////).*"' "$ENV_FILE" | tr -d '"')
        if [[ ! "$sqlite_file" =~ ^/ ]]; then
            sqlite_file="/$sqlite_file"
        fi

    fi

    if [ -n "$db_type" ]; then
        echo "Database detected: $db_type" >> "$log_file"
        case $db_type in
            mariadb)
                if ! docker exec "$container_name" mariadb-dump -u root -p"$MYSQL_ROOT_PASSWORD" --all-databases --ignore-database=mysql --ignore-database=performance_schema --ignore-database=information_schema --ignore-database=sys --events --triggers > "$temp_dir/db_backup.sql" 2>>"$log_file"; then
                    error_messages+=("MariaDB dump failed.")
                fi
                ;;
            mysql)
                if ! docker exec "$container_name" mysqldump -u root -p"$MYSQL_ROOT_PASSWORD" marzban --events --triggers  > "$temp_dir/db_backup.sql" 2>>"$log_file"; then
                    error_messages+=("MySQL dump failed.")
                fi
                ;;
            sqlite)
                if [ -f "$sqlite_file" ]; then
                    if ! cp "$sqlite_file" "$temp_dir/db_backup.sqlite" 2>>"$log_file"; then
                        error_messages+=("Failed to copy SQLite database.")
                    fi
                else
                    error_messages+=("SQLite database file not found at $sqlite_file.")
                fi
                ;;
        esac
    fi

    cp "$APP_DIR/.env" "$temp_dir/" 2>>"$log_file"
    cp "$APP_DIR/docker-compose.yml" "$temp_dir/" 2>>"$log_file"
    rsync -av --exclude 'xray-core' --exclude 'mysql' "$DATA_DIR/" "$temp_dir/marzban_data/" >>"$log_file" 2>&1

    if ! tar -czf "$backup_file" -C "$temp_dir" .; then
        error_messages+=("Failed to create backup archive.")
        echo "Failed to create backup archive." >> "$log_file"
    fi

    rm -rf "$temp_dir"

    if [ ${#error_messages[@]} -gt 0 ]; then
        send_backup_error_to_telegram "${error_messages[*]}" "$log_file"
        return
    fi
    colorized_echo green "Backup created: $backup_file"
    send_backup_to_telegram "$backup_file"
}



get_xray_core() {
    identify_the_operating_system_and_architecture
    clear

    validate_version() {
        local version="$1"
        
        local response=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases/tags/$version")
        if echo "$response" | grep -q '"message": "Not Found"'; then
            echo "invalid"
        else
            echo "valid"
        fi
    }

    print_menu() {
        clear
        echo -e "\033[1;32m==============================\033[0m"
        echo -e "\033[1;32m      Xray-core Installer     \033[0m"
        echo -e "\033[1;32m==============================\033[0m"
        echo -e "\033[1;33mAvailable Xray-core versions:\033[0m"
        for ((i=0; i<${#versions[@]}; i++)); do
            echo -e "\033[1;34m$((i + 1)):\033[0m ${versions[i]}"
        done
        echo -e "\033[1;32m==============================\033[0m"
        echo -e "\033[1;35mM:\033[0m Enter a version manually"
        echo -e "\033[1;31mQ:\033[0m Quit"
        echo -e "\033[1;32m==============================\033[0m"
    }

    latest_releases=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases?per_page=$LAST_XRAY_CORES")

    versions=($(echo "$latest_releases" | grep -oP '"tag_name": "\K(.*?)(?=")'))

    while true; do
        print_menu
        read -p "Choose a version to install (1-${#versions[@]}), or press M to enter manually, Q to quit: " choice
        
        if [[ "$choice" =~ ^[1-9][0-9]*$ ]] && [ "$choice" -le "${#versions[@]}" ]; then
            choice=$((choice - 1))
            selected_version=${versions[choice]}
            break
        elif [ "$choice" == "M" ] || [ "$choice" == "m" ]; then
            while true; do
                read -p "Enter the version manually (e.g., v1.2.3): " custom_version
                if [ "$(validate_version "$custom_version")" == "valid" ]; then
                    selected_version="$custom_version"
                    break 2
                else
                    echo -e "\033[1;31mInvalid version or version does not exist. Please try again.\033[0m"
                fi
            done
        elif [ "$choice" == "Q" ] || [ "$choice" == "q" ]; then
            echo -e "\033[1;31mExiting.\033[0m"
            exit 0
        else
            echo -e "\033[1;31mInvalid choice. Please try again.\033[0m"
            sleep 2
        fi
    done

    echo -e "\033[1;32mSelected version $selected_version for installation.\033[0m"

    # Check if the required packages are installed
    if ! command -v unzip >/dev/null 2>&1; then
        echo -e "\033[1;33mInstalling required packages...\033[0m"
        detect_os
        install_package unzip
    fi
    if ! command -v wget >/dev/null 2>&1; then
        echo -e "\033[1;33mInstalling required packages...\033[0m"
        detect_os
        install_package wget
    fi

    mkdir -p $DATA_DIR/xray-core
    cd $DATA_DIR/xray-core

    xray_filename="Xray-linux-$ARCH.zip"
    xray_download_url="https://github.com/XTLS/Xray-core/releases/download/${selected_version}/${xray_filename}"

    echo -e "\033[1;33mDownloading Xray-core version ${selected_version}...\033[0m"
    wget -q -O "${xray_filename}" "${xray_download_url}"

    echo -e "\033[1;33mExtracting Xray-core...\033[0m"
    unzip -o "${xray_filename}" >/dev/null 2>&1
    rm "${xray_filename}"
}

# Function to update the Marzban Main core
update_core_command() {
    check_running_as_root
    get_xray_core
    # Change the Marzban core
    xray_executable_path="XRAY_EXECUTABLE_PATH=\"/var/lib/marzban/xray-core/xray\""
    
    echo "Changing the Marzban core..."
    # Check if the XRAY_EXECUTABLE_PATH string already exists in the .env file
    if ! grep -q "^XRAY_EXECUTABLE_PATH=" "$ENV_FILE"; then
        # If the string does not exist, add it
        echo "${xray_executable_path}" >> "$ENV_FILE"
    else
        # Update the existing XRAY_EXECUTABLE_PATH line
        sed -i "s~^XRAY_EXECUTABLE_PATH=.*~${xray_executable_path}~" "$ENV_FILE"
    fi
    
    # Restart Marzban
    colorized_echo red "Restarting Marzban..."
    if restart_command -n >/dev/null 2>&1; then
        colorized_echo green "Marzban successfully restarted!"
    else
        colorized_echo red "Marzban restart failed!"
    fi
    colorized_echo blue "Installation of Xray-core version $selected_version completed."
}

prompt_for_domains() {
    colorized_echo blue "====================================="
    colorized_echo blue "      SSL Certificate Setup"
    colorized_echo blue "====================================="

    while true; do
        read -p "Enter domain(s) for SSL certificate (comma separated for multiple domains/subdomains): " domains
        if [[ -n "$domains" ]]; then
            IFS=',' read -ra DOMAIN_ARRAY <<< "$domains"
            DOMAIN="${DOMAIN_ARRAY[0]}"  # First domain is primary
            break
        else
            colorized_echo red "Domain cannot be empty. Please try again."
        fi
    done

    # Ask if user wants wildcard SSL
    colorized_echo blue "====================================="
    colorized_echo blue "      Wildcard SSL Option"
    colorized_echo blue "====================================="
    colorized_echo yellow "Do you want to generate a wildcard+SAN SSL certificate?"
    colorized_echo cyan "Wildcard+SAN certificate covers ALL domains you entered AND all their subdomains."
    colorized_echo cyan "Example: If you entered 'sub.example.com,api.another.com', the certificate will cover:"
    colorized_echo cyan "  • *.example.com, example.com (all subdomains + root of example.com)"
    colorized_echo cyan "  • *.another.com, another.com (all subdomains + root of another.com)"
    colorized_echo cyan "This requires Cloudflare DNS API credentials."
    echo
    while true; do
        read -p "Generate wildcard SSL certificates? (y/n): " wildcard_choice
        case $wildcard_choice in
            [Yy]* )
                USE_WILDCARD=true
                prompt_for_cloudflare_credentials
                break
                ;;
            [Nn]* )
                USE_WILDCARD=false
                colorized_echo green "Using standard SSL certificates with SAN for multiple domains."
                break
                ;;
            * )
                colorized_echo red "Please answer yes (y) or no (n)."
                ;;
        esac
    done
}

prompt_for_cloudflare_credentials() {
    colorized_echo blue "====================================="
    colorized_echo blue "    Cloudflare DNS API Setup"
    colorized_echo blue "====================================="
    colorized_echo cyan "For wildcard SSL certificates, we need your Cloudflare API credentials."
    colorized_echo cyan "You can get these from: https://dash.cloudflare.com/profile/api-tokens"
    echo
    colorized_echo yellow "Choose your authentication method:"
    echo "1. API Token (Recommended - more secure)"
    echo "2. Global API Key (Legacy method)"
    echo

    while true; do
        read -p "Choose option (1 or 2): " cf_auth_choice
        case $cf_auth_choice in
            1)
                colorized_echo green "Using API Token method"
                while true; do
                    read -p "Enter your Cloudflare API Token: " CF_Token
                    if [[ -n "$CF_Token" ]]; then
                        break
                    else
                        colorized_echo red "API Token cannot be empty. Please try again."
                    fi
                done
                CF_ACCOUNT_ID=""
                while true; do
                    read -p "Enter your Cloudflare Account ID (optional, press Enter to skip): " CF_ACCOUNT_ID
                    break
                done
                break
                ;;
            2)
                colorized_echo yellow "Using Global API Key method"
                while true; do
                    read -p "Enter your Cloudflare email: " CF_Email
                    if [[ -n "$CF_Email" ]]; then
                        break
                    else
                        colorized_echo red "Email cannot be empty. Please try again."
                    fi
                done
                while true; do
                    read -p "Enter your Cloudflare Global API Key: " CF_Key
                    if [[ -n "$CF_Key" ]]; then
                        break
                    else
                        colorized_echo red "API Key cannot be empty. Please try again."
                    fi
                done
                break
                ;;
            *)
                colorized_echo red "Please choose 1 or 2."
                ;;
        esac
    done

    colorized_echo green "Cloudflare credentials configured successfully!"
}

install_ssl_dependencies() {
    colorized_echo blue "Installing SSL dependencies..."
    install_package haproxy
    install_package socat
    
    # Install acme.sh if not already installed
    if [ ! -f ~/.acme.sh/acme.sh ]; then
        curl https://get.acme.sh | sh -s email=admin@$DOMAIN
        source ~/.bashrc
    fi
}

generate_ssl_certs() {
    mkdir -p /var/lib/marzban/certs

    if [ "$USE_WILDCARD" = true ]; then
        generate_wildcard_ssl_certs
    else
        generate_standard_ssl_certs
    fi

    # Set proper permissions
    chmod 600 /var/lib/marzban/certs/*
}

generate_standard_ssl_certs() {
    colorized_echo blue "Generating standard SSL certificates for $DOMAIN..."

    local acme_args=()
    for d in "${DOMAIN_ARRAY[@]}"; do
        acme_args+=("-d" "$d")
    done

    # Remove existing certs for the domains to avoid conflicts
    colorized_echo yellow "Checking for and removing existing certificates to prevent conflicts..."
    for d in "${DOMAIN_ARRAY[@]}"; do
        if [ -f "$HOME/.acme.sh/acme.sh" ]; then
            "$HOME/.acme.sh/acme.sh" --remove -d "$d" --ecc >/dev/null 2>&1 || true
        fi
    done

    colorized_echo blue "Issuing certificate..."
    # Use --force to overwrite existing domain keys and avoid interactive prompts.
    if ! "$HOME/.acme.sh/acme.sh" --issue --standalone --force "${acme_args[@]}"; then
        local exit_code=$?
        # Exit code 2 means the certificate is already issued and doesn't need renewal, which is not an error.
        if [ $exit_code -ne 2 ]; then
            colorized_echo red "acme.sh --issue failed with exit code $exit_code"
            exit $exit_code
        fi
    fi

    colorized_echo blue "Installing certificate..."
    if ! "$HOME/.acme.sh/acme.sh" --install-cert "${acme_args[@]}" \
        --fullchain-file "/var/lib/marzban/certs/$DOMAIN.cer" \
        --key-file "/var/lib/marzban/certs/$DOMAIN.cer.key"; then
        colorized_echo red "acme.sh --install-cert failed"
        exit 1
    fi
}

generate_wildcard_ssl_certs() {
    colorized_echo blue "Generating wildcard+SAN SSL certificate..."

    # Set up Cloudflare credentials for acme.sh
    if [[ -n "$CF_Token" ]]; then
        export CF_Token="$CF_Token"
        if [[ -n "$CF_ACCOUNT_ID" ]]; then
            export CF_Account_ID="$CF_ACCOUNT_ID"
        fi
        colorized_echo green "Using Cloudflare API Token for DNS challenge"
    elif [[ -n "$CF_Key" && -n "$CF_Email" ]]; then
        export CF_Key="$CF_Key"
        export CF_Email="$CF_Email"
        colorized_echo green "Using Cloudflare Global API Key for DNS challenge"
    else
        colorized_echo red "Cloudflare credentials not properly configured"
        exit 1
    fi

    # Extract unique root domains and build certificate arguments
    local root_domains=()
    local acme_args=()
    local seen_domains=()

    colorized_echo blue "Processing domains for wildcard+SAN certificate..."

    for domain in "${DOMAIN_ARRAY[@]}"; do
        # Extract root domain (remove any subdomain)
        root_domain=$(echo "$domain" | awk -F. '{print $(NF-1)"."$NF}')

        # Check if we've already processed this root domain
        local already_seen=false
        for seen in "${seen_domains[@]}"; do
            if [[ "$seen" == "$root_domain" ]]; then
                already_seen=true
                break
            fi
        done

        if [[ "$already_seen" == false ]]; then
            seen_domains+=("$root_domain")
            root_domains+=("$root_domain")
            wildcard_domain="*.$root_domain"

            # Add both wildcard and root domain to certificate
            acme_args+=("-d" "$wildcard_domain")
            acme_args+=("-d" "$root_domain")

            colorized_echo cyan "  Added to certificate: $wildcard_domain (covers all subdomains)"
            colorized_echo cyan "  Added to certificate: $root_domain (covers root domain)"
        fi
    done

    # Use the first root domain as the primary domain for file naming
    DOMAIN="${root_domains[0]}"

    colorized_echo blue "Certificate will cover:"
    for root_domain in "${root_domains[@]}"; do
        colorized_echo green "  • *.$root_domain (wildcard for all subdomains)"
        colorized_echo green "  • $root_domain (root domain)"
    done

    # Remove existing certificates to avoid conflicts
    colorized_echo yellow "Removing any existing certificates to prevent conflicts..."
    if [ -f "$HOME/.acme.sh/acme.sh" ]; then
        for root_domain in "${root_domains[@]}"; do
            "$HOME/.acme.sh/acme.sh" --remove -d "*.$root_domain" --ecc >/dev/null 2>&1 || true
            "$HOME/.acme.sh/acme.sh" --remove -d "$root_domain" --ecc >/dev/null 2>&1 || true
        done
    fi

    colorized_echo blue "Issuing single wildcard+SAN certificate for all domains..."
    # Issue single certificate with all wildcard domains using Cloudflare DNS challenge
    if ! "$HOME/.acme.sh/acme.sh" --issue --dns dns_cf --force "${acme_args[@]}"; then
        local exit_code=$?
        if [ $exit_code -ne 2 ]; then
            colorized_echo red "Failed to issue wildcard+SAN certificate"
            colorized_echo red "This might be due to:"
            colorized_echo red "  • Invalid Cloudflare credentials"
            colorized_echo red "  • Domains not managed by your Cloudflare account"
            colorized_echo red "  • Rate limiting from Let's Encrypt"
            exit $exit_code
        fi
    fi

    # Install the certificate using the primary domain as filename
    colorized_echo blue "Installing wildcard+SAN certificate..."
    if ! "$HOME/.acme.sh/acme.sh" --install-cert -d "*.${DOMAIN}" \
        --fullchain-file "/var/lib/marzban/certs/$DOMAIN.cer" \
        --key-file "/var/lib/marzban/certs/$DOMAIN.cer.key"; then
        colorized_echo red "Failed to install wildcard+SAN certificate"
        exit 1
    fi

    colorized_echo green "====================================="
    colorized_echo green "Wildcard+SAN certificate generated successfully!"
    colorized_echo green "Single certificate covers:"
    for root_domain in "${root_domains[@]}"; do
        colorized_echo green "  ✓ *.$root_domain (all subdomains)"
        colorized_echo green "  ✓ $root_domain (root domain)"
    done
    colorized_echo green "Certificate files:"
    colorized_echo green "  • /var/lib/marzban/certs/$DOMAIN.cer"
    colorized_echo green "  • /var/lib/marzban/certs/$DOMAIN.cer.key"
    colorized_echo green "====================================="
}

configure_env_ssl() {
    colorized_echo blue "Configuring SSL in Marzban environment..."

    update_env_var "UVICORN_PORT" "10000" "$ENV_FILE"
    update_env_var "UVICORN_HOST" '"127.0.0.1"' "$ENV_FILE"
    update_env_var "UVICORN_SSL_CERTFILE" "\"/var/lib/marzban/certs/$DOMAIN.cer\"" "$ENV_FILE"
    update_env_var "UVICORN_SSL_KEYFILE" "\"/var/lib/marzban/certs/$DOMAIN.cer.key\"" "$ENV_FILE"
    update_env_var "XRAY_SUBSCRIPTION_URL_PREFIX" "https://$DOMAIN" "$ENV_FILE"
}

configure_haproxy() {
    colorized_echo blue "Configuring HAProxy..."
    
    mkdir -p /etc/haproxy
    # Create or modify haproxy.cfg without overwriting existing config
    if [ ! -f /etc/haproxy/haproxy.cfg ]; then
        # Create new file if it doesn't exist
        cat > /etc/haproxy/haproxy.cfg <<EOF
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log global
    mode http
    option httplog
    option dontlognull
    timeout connect 5000
    timeout client 50000
    timeout server 50000

# Marzban Configuration
listen front
    mode tcp
    bind *:443

    tcp-request inspect-delay 5s
    tcp-request content accept if { req_ssl_hello_type 1 }

    use_backend panel if { req.ssl_sni -m end $DOMAIN }

    default_backend fallback

backend panel
    mode tcp
    server srv1 127.0.0.1:10000

backend fallback
    mode tcp
    server srv1 127.0.0.1:11000
EOF
    else
        # Append Marzban config to existing file if not already present
        if ! grep -q "backend panel" /etc/haproxy/haproxy.cfg; then
            cat >> /etc/haproxy/haproxy.cfg <<EOF

# Marzban Configuration
listen front
    mode tcp
    bind *:443

    tcp-request inspect-delay 5s
    tcp-request content accept if { req_ssl_hello_type 1 }

    use_backend panel if { req.ssl_sni -m end $DOMAIN }

    default_backend fallback

backend panel
    mode tcp
    server srv1 127.0.0.1:10000

backend fallback
    mode tcp
    server srv1 127.0.0.1:11000
EOF
        fi
    fi
}

configure_ufw() {
    colorized_echo blue "Configuring UFW firewall..."
    
    if ! command -v ufw >/dev/null 2>&1; then
        colorized_echo yellow "UFW not installed, skipping firewall configuration"
        return
    fi
    
    if ! ufw status | grep -q "Status: active"; then
        colorized_echo yellow "UFW is not active, skipping firewall configuration"
        return
    fi
    
    ufw allow 80/tcp    # For Let's Encrypt validation
    ufw allow 443/tcp   # Main HTTPS access
    
    colorized_echo green "UFW configured to allow HTTP/HTTPS traffic"
}

restart_services() {
    colorized_echo blue "Restarting services..."
    
    systemctl restart haproxy
    marzban restart -n
    
    colorized_echo green "Services restarted successfully"
}

install_marzban() {
    local marzban_version=$1
    local database_type=$2
    local domains_arg=$3
    # Fetch releases
    FILES_URL_PREFIX="https://raw.githubusercontent.com/naymintun800/Marzban/master"
    
    mkdir -p "$DATA_DIR"
    mkdir -p "$APP_DIR"
    
    colorized_echo blue "Setting up docker-compose.yml"
    docker_file_path="$APP_DIR/docker-compose.yml"
    
    if [ "$database_type" == "mariadb" ]; then
        # Generate docker-compose.yml with MariaDB content
        cat > "$docker_file_path" <<EOF
services:
  marzban:
    image: naymintun800/marzban:${marzban_version}
    restart: always
    env_file: .env
    network_mode: host
    volumes:
      - /var/lib/marzban:/var/lib/marzban
      - /var/lib/marzban/logs:/var/lib/marzban-node
    depends_on:
      mariadb:
        condition: service_healthy

  mariadb:
    image: mariadb:lts
    env_file: .env
    network_mode: host
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: \${MYSQL_ROOT_PASSWORD}
      MYSQL_ROOT_HOST: '%'
      MYSQL_DATABASE: \${MYSQL_DATABASE}
      MYSQL_USER: \${MYSQL_USER}
      MYSQL_PASSWORD: \${MYSQL_PASSWORD}
    command:
      - --bind-address=127.0.0.1
      - --character_set_server=utf8mb4
      - --collation_server=utf8mb4_unicode_ci
      - --host-cache-size=0
      - --innodb-open-files=1024
      - --innodb-buffer-pool-size=256M
      - --binlog_expire_logs_seconds=1209600
      - --innodb-log-file-size=64M
      - --innodb-log-files-in-group=2
      - --innodb-doublewrite=0
      - --general_log=0
      - --slow_query_log=1
      - --slow_query_log_file=/var/lib/mysql/slow.log
      - --long_query_time=2
    volumes:
      - /var/lib/marzban/mysql:/var/lib/mysql
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      start_period: 10s
      start_interval: 3s
      interval: 10s
      timeout: 5s
      retries: 3
EOF
        echo "----------------------------"
        colorized_echo red "Using MariaDB as database"
        echo "----------------------------"
        colorized_echo green "File generated at $APP_DIR/docker-compose.yml"

        # Modify .env file
        colorized_echo blue "Fetching .env file"
        curl -sL "$FILES_URL_PREFIX/.env.example" -o "$APP_DIR/.env"

        # Comment out the SQLite line
        sed -i 's~^\(SQLALCHEMY_DATABASE_URL = "sqlite:////var/lib/marzban/db.sqlite3"\)~#\1~' "$APP_DIR/.env"

        sed -i 's/^# \(XRAY_JSON = .*\)$/\1/' "$APP_DIR/.env"
        sed -i 's~\(XRAY_JSON = \).*~\1"/var/lib/marzban/xray_config.json"~' "$APP_DIR/.env"

        prompt_for_marzban_password
        MYSQL_ROOT_PASSWORD=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)
        
        echo "" >> "$ENV_FILE"
        echo "" >> "$ENV_FILE"
        echo "# Database configuration" >> "$ENV_FILE"
        echo "MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD" >> "$ENV_FILE"
        echo "MYSQL_DATABASE=marzban" >> "$ENV_FILE"
        echo "MYSQL_USER=marzban" >> "$ENV_FILE"
        echo "MYSQL_PASSWORD=$MYSQL_PASSWORD" >> "$ENV_FILE"
        
        SQLALCHEMY_DATABASE_URL="mysql+pymysql://marzban:${MYSQL_PASSWORD}@127.0.0.1:3306/marzban"
        
        echo "" >> "$ENV_FILE"
        echo "# SQLAlchemy Database URL" >> "$ENV_FILE"
        echo "SQLALCHEMY_DATABASE_URL=\"$SQLALCHEMY_DATABASE_URL\"" >> "$ENV_FILE"
        
        colorized_echo green "File saved in $APP_DIR/.env"

    elif [ "$database_type" == "mysql" ]; then
        # Generate docker-compose.yml with MySQL content
        cat > "$docker_file_path" <<EOF
services:
  marzban:
    image: naymintun800/marzban:${marzban_version}
    restart: always
    env_file: .env
    network_mode: host
    volumes:
      - /var/lib/marzban:/var/lib/marzban
    command: bash -c "mkdir -p /code/app/db/migrations/versions && alembic init -t async /code/app/db/migrations && alembic upgrade head && python3 main.py"
    depends_on:
      mysql:
        condition: service_healthy

  mysql:
    image: mysql:lts
    env_file: .env
    network_mode: host
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: \${MYSQL_ROOT_PASSWORD}
      MYSQL_ROOT_HOST: '%'
      MYSQL_DATABASE: \${MYSQL_DATABASE}
      MYSQL_USER: \${MYSQL_USER}
      MYSQL_PASSWORD: \${MYSQL_PASSWORD}
    command:
      - --mysqlx=OFF
      - --bind-address=127.0.0.1
      - --character_set_server=utf8mb4
      - --collation_server=utf8mb4_unicode_ci
      - --log-bin=mysql-bin
      - --binlog_expire_logs_seconds=1209600
      - --host-cache-size=0
      - --innodb-open-files=1024
      - --innodb-buffer-pool-size=256M
      - --innodb-log-file-size=64M
      - --innodb-log-files-in-group=2
      - --general_log=0
      - --slow_query_log=1
      - --slow_query_log_file=/var/lib/mysql/slow.log
      - --long_query_time=2
    volumes:
      - /var/lib/marzban/mysql:/var/lib/mysql
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "127.0.0.1", "-u", "marzban", "--password=\${MYSQL_PASSWORD}"]
      start_period: 5s
      interval: 5s
      timeout: 5s
      retries: 55
EOF
        echo "----------------------------"
        colorized_echo red "Using MySQL as database"
        echo "----------------------------"
        colorized_echo green "File generated at $APP_DIR/docker-compose.yml"

        # Modify .env file
        colorized_echo blue "Fetching .env file"
        curl -sL "$FILES_URL_PREFIX/.env.example" -o "$APP_DIR/.env"

        # Comment out the SQLite line
        sed -i 's~^\(SQLALCHEMY_DATABASE_URL = "sqlite:////var/lib/marzban/db.sqlite3"\)~#\1~' "$APP_DIR/.env"

        sed -i 's/^# \(XRAY_JSON = .*\)$/\1/' "$APP_DIR/.env"
        sed -i 's~\(XRAY_JSON = \).*~\1"/var/lib/marzban/xray_config.json"~' "$APP_DIR/.env"

        prompt_for_marzban_password
        MYSQL_ROOT_PASSWORD=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)
        
        echo "" >> "$ENV_FILE"
        echo "" >> "$ENV_FILE"
        echo "# Database configuration" >> "$ENV_FILE"
        echo "MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD" >> "$ENV_FILE"
        echo "MYSQL_DATABASE=marzban" >> "$ENV_FILE"
        echo "MYSQL_USER=marzban" >> "$ENV_FILE"
        echo "MYSQL_PASSWORD=$MYSQL_PASSWORD" >> "$ENV_FILE"
        
        SQLALCHEMY_DATABASE_URL="mysql+pymysql://marzban:${MYSQL_PASSWORD}@127.0.0.1:3306/marzban"
        
        echo "" >> "$ENV_FILE"
        echo "# SQLAlchemy Database URL" >> "$ENV_FILE"
        echo "SQLALCHEMY_DATABASE_URL=\"$SQLALCHEMY_DATABASE_URL\"" >> "$ENV_FILE"
        
        colorized_echo green "File saved in $APP_DIR/.env"

    else
        echo "----------------------------"
        colorized_echo red "Using SQLite as database"
        echo "----------------------------"
        colorized_echo blue "Fetching compose file"
        curl -sL "$FILES_URL_PREFIX/docker-compose.yml" -o "$docker_file_path"

        # Install requested version
        if [ "$marzban_version" == "latest" ]; then
            yq -i '.services.marzban.image = "naymintun800/marzban:latest"' "$docker_file_path"
        else
            yq -i ".services.marzban.image = \"naymintun800/marzban:${marzban_version}\"" "$docker_file_path"
        fi
        echo "Installing $marzban_version version"
        colorized_echo green "File saved in $APP_DIR/docker-compose.yml"

        colorized_echo blue "Fetching .env file"
        curl -sL "$FILES_URL_PREFIX/.env.example" -o "$APP_DIR/.env"

        # Update SQLite database path and Xray config path using the proper function
        update_env_var "SQLALCHEMY_DATABASE_URL" '"sqlite:////var/lib/marzban/db.sqlite3"' "$APP_DIR/.env"
        update_env_var "XRAY_JSON" '"/var/lib/marzban/xray_config.json"' "$APP_DIR/.env"
        
        colorized_echo green "File saved in $APP_DIR/.env"
    fi
    
    colorized_echo blue "Downloading latest Xray-core to generate keys"
    identify_the_operating_system_and_architecture
    if ! command -v wget >/dev/null 2>&1; then
        install_package wget
    fi
    if ! command -v unzip >/dev/null 2>&1; then
        install_package unzip
    fi

    local latest_version
    latest_version=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases/latest" | grep -oP '"tag_name": "\K(.*?)(?=")')
    if [ -z "$latest_version" ]; then
        colorized_echo red "Failed to fetch latest Xray-core version."
        exit 1
    fi

    local xray_filename="Xray-linux-$ARCH.zip"
    local xray_download_url="https://github.com/XTLS/Xray-core/releases/download/${latest_version}/${xray_filename}"
    local xray_zip_path="/tmp/${xray_filename}"
    local xray_core_dir="$DATA_DIR/xray-core"
    
    mkdir -p "$xray_core_dir"

    colorized_echo blue "Downloading Xray-core version ${latest_version}..."
    wget -q -O "${xray_zip_path}" "${xray_download_url}"

    colorized_echo blue "Extracting Xray-core..."
    unzip -o "${xray_zip_path}" -d "$xray_core_dir" >/dev/null 2>&1
    rm "${xray_zip_path}"

    local XRAY_PRIVATE_KEY
    XRAY_PRIVATE_KEY=$("$xray_core_dir/xray" x25519 | awk '/Private key:/ {print $3}')
    if [ -z "$XRAY_PRIVATE_KEY" ]; then
        colorized_echo red "Failed to generate Xray private key."
        exit 1
    fi

    colorized_echo blue "Creating xray config file"
    cat > "$DATA_DIR/xray_config.json" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "dns": {
    "servers": [
      "1.1.1.1"
    ],
    "queryStrategy": "UseIPv4"
  },
  "routing": {
    "rules": [
      {
        "protocol": [
          "bittorent"
        ],
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "BLOCK",
        "type": "field"
      }
    ]
  },
  "inbounds": [
    {
      "tag": "Shadowsocks TCP",
      "listen": "0.0.0.0",
      "port": 1080,
      "protocol": "shadowsocks",
      "settings": {
        "clients": [],
        "network": "tcp,udp"
      }
    },
    {
      "tag": "VLESS TCP REALITY",
      "listen": "127.0.0.1",
      "port": 12000,
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none",
        "flow": "xtls-rprx-vision"
      },
      "streamSettings": {
        "network": "tcp",
        "tcpSettings": {
          "acceptProxyProtocol": true
        },
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "gmail.com:443",
          "xver": 0,
          "serverNames": [
            "gmail.com"
          ],
          "privateKey": "$XRAY_PRIVATE_KEY",
          "SpiderX": "",
          "shortIds": [
            ""
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "DIRECT"
    },
    {
      "protocol": "blackhole",
      "tag": "BLOCK"
    }
  ]
}
EOF
    colorized_echo green "Xray config created at $DATA_DIR/xray_config.json with generated private key"

    colorized_echo blue "Fetching alembic.ini file"
    curl -sL "$FILES_URL_PREFIX/alembic.ini" -o "$APP_DIR/alembic.ini"
    colorized_echo green "File saved in $APP_DIR/alembic.ini"
    
    colorized_echo green "Marzban's files downloaded successfully"
    
    # Only setup SSL and HAProxy on Ubuntu
    if [[ "$OS" == "Ubuntu"* ]]; then
        if [ -n "$domains_arg" ]; then
            domains="$domains_arg"
            IFS=',' read -ra DOMAIN_ARRAY <<< "$domains"
            DOMAIN="${DOMAIN_ARRAY[0]}"
        else
            prompt_for_domains
        fi
        install_ssl_dependencies
        generate_ssl_certs
        configure_env_ssl
        configure_haproxy
        configure_ufw
        restart_services
    fi
}

up_marzban() {
    $COMPOSE -f $COMPOSE_FILE -p "$APP_NAME" up -d --remove-orphans
}

follow_marzban_logs() {
    $COMPOSE -f $COMPOSE_FILE -p "$APP_NAME" logs -f
}

status_command() {
    
    # Check if marzban is installed
    if ! is_marzban_installed; then
        echo -n "Status: "
        colorized_echo red "Not Installed"
        exit 1
    fi
    
    detect_compose
    
    if ! is_marzban_up; then
        echo -n "Status: "
        colorized_echo blue "Down"
        exit 1
    fi
    
    echo -n "Status: "
    colorized_echo green "Up"
    
    json=$($COMPOSE -f $COMPOSE_FILE ps -a --format=json)
    services=$(echo "$json" | jq -r 'if type == "array" then .[] else . end | .Service')
    states=$(echo "$json" | jq -r 'if type == "array" then .[] else . end | .State')
    # Print out the service names and statuses
    for i in $(seq 0 $(expr $(echo $services | wc -w) - 1)); do
        service=$(echo $services | cut -d' ' -f $(expr $i + 1))
        state=$(echo $states | cut -d' ' -f $(expr $i + 1))
        echo -n "- $service: "
        if [ "$state" == "running" ]; then
            colorized_echo green $state
        else
            colorized_echo red $state
        fi
    done
}


prompt_for_marzban_password() {
    colorized_echo cyan "This password will be used to access the database and should be strong."
    colorized_echo cyan "If you do not enter a custom password, a secure 20-character password will be generated automatically."

    # Запрашиваем ввод пароля
    read -p "Enter the password for the marzban user (or press Enter to generate a secure default password): " MYSQL_PASSWORD

    # Генерация 20-значного пароля, если пользователь оставил поле пустым
    if [ -z "$MYSQL_PASSWORD" ]; then
        MYSQL_PASSWORD=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)
        colorized_echo green "A secure password has been generated automatically."
    fi
    colorized_echo green "This password will be recorded in the .env file for future use."

    # Пауза 3 секунды перед продолжением
    sleep 3
}

install_command() {
    check_running_as_root

    # Default values
    database_type="sqlite"
    marzban_version="latest"
    marzban_version_set="false"
    local domains=""

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --domain)
                domains="$2"
                shift 2
            ;;
            --database)
                database_type="$2"
                shift 2
            ;;
            --dev)
                if [[ "$marzban_version_set" == "true" ]]; then
                    colorized_echo red "Error: Cannot use --dev and --version options simultaneously."
                    exit 1
                fi
                marzban_version="dev"
                marzban_version_set="true"
                shift
            ;;
            --version)
                if [[ "$marzban_version_set" == "true" ]]; then
                    colorized_echo red "Error: Cannot use --dev and --version options simultaneously."
                    exit 1
                fi
                marzban_version="$2"
                marzban_version_set="true"
                shift 2
            ;;
            *)
                echo "Unknown option: $1"
                exit 1
            ;;
        esac
    done

    # Check if marzban is already installed
    if is_marzban_installed; then
        colorized_echo red "Marzban is already installed at $APP_DIR"
        read -p "Do you want to override the previous installation? (y/n) "
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            colorized_echo red "Aborted installation"
            exit 1
        fi
    fi
    detect_os
    if ! command -v jq >/dev/null 2>&1; then
        install_package jq
    fi
    if ! command -v curl >/dev/null 2>&1; then
        install_package curl
    fi
    if ! command -v docker >/dev/null 2>&1; then
        install_docker
    fi
    if ! command -v yq >/dev/null 2>&1; then
        install_yq
    fi
    detect_compose
    install_marzban_script
    # Function to check if a version exists in the GitHub releases
    check_version_exists() {
        local version=$1
        repo_url="https://api.github.com/repos/naymintun800/Marzban/releases"
        if [ "$version" == "latest" ] || [ "$version" == "dev" ]; then
            return 0
        fi
        
        # Fetch the release data from GitHub API
        response=$(curl -s "$repo_url")
        
        # Check if the response contains the version tag
        if echo "$response" | jq -e ".[] | select(.tag_name == \"${version}\")" > /dev/null; then
            return 0
        else
            return 1
        fi
    }
    # Check if the version is valid and exists
    if [[ "$marzban_version" == "latest" || "$marzban_version" == "dev" || "$marzban_version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        if check_version_exists "$marzban_version"; then
            install_marzban "$marzban_version" "$database_type" "$domains"
            echo "Installing $marzban_version version"
        else
            echo "Version $marzban_version does not exist. Please enter a valid version (e.g. v0.5.2)"
            exit 1
        fi
    else
        echo "Invalid version format. Please enter a valid version (e.g. v0.5.2)"
        exit 1
    fi
    up_marzban

    colorized_echo blue "Waiting for services to initialize (15 seconds)..."
    sleep 15

    colorized_echo blue "Creating initial admin account..."
    marzban cli admin create --sudo

    colorized_echo green "Installation complete! You can now access the panel."
    colorized_echo green "Following logs... (Press Ctrl+C to exit)"
    follow_marzban_logs
}

install_yq() {
    if command -v yq &>/dev/null; then
        colorized_echo green "yq is already installed."
        return
    fi

    identify_the_operating_system_and_architecture

    local base_url="https://github.com/mikefarah/yq/releases/latest/download"
    local yq_binary=""

    case "$ARCH" in
        '64' | 'x86_64')
            yq_binary="yq_linux_amd64"
            ;;
        'arm32-v7a' | 'arm32-v6' | 'arm32-v5' | 'armv7l')
            yq_binary="yq_linux_arm"
            ;;
        'arm64-v8a' | 'aarch64')
            yq_binary="yq_linux_arm64"
            ;;
        '32' | 'i386' | 'i686')
            yq_binary="yq_linux_386"
            ;;
        *)
            colorized_echo red "Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac

    local yq_url="${base_url}/${yq_binary}"
    colorized_echo blue "Downloading yq from ${yq_url}..."

    if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
        colorized_echo yellow "Neither curl nor wget is installed. Attempting to install curl."
        install_package curl || {
            colorized_echo red "Failed to install curl. Please install curl or wget manually."
            exit 1
        }
    fi


    if command -v curl &>/dev/null; then
        if curl -L "$yq_url" -o /usr/local/bin/yq; then
            chmod +x /usr/local/bin/yq
            colorized_echo green "yq installed successfully!"
        else
            colorized_echo red "Failed to download yq using curl. Please check your internet connection."
            exit 1
        fi
    elif command -v wget &>/dev/null; then
        if wget -O /usr/local/bin/yq "$yq_url"; then
            chmod +x /usr/local/bin/yq
            colorized_echo green "yq installed successfully!"
        else
            colorized_echo red "Failed to download yq using wget. Please check your internet connection."
            exit 1
        fi
    fi


    if ! echo "$PATH" | grep -q "/usr/local/bin"; then
        export PATH="/usr/local/bin:$PATH"
    fi


    hash -r

    if command -v yq &>/dev/null; then
        colorized_echo green "yq is ready to use."
    elif [ -x "/usr/local/bin/yq" ]; then

        colorized_echo yellow "yq is installed at /usr/local/bin/yq but not found in PATH."
        colorized_echo yellow "You can add /usr/local/bin to your PATH environment variable."
    else
        colorized_echo red "yq installation failed. Please try again or install manually."
        exit 1
    fi
}


down_marzban() {
    $COMPOSE -f $COMPOSE_FILE -p "$APP_NAME" down
}



show_marzban_logs() {
    $COMPOSE -f $COMPOSE_FILE -p "$APP_NAME" logs
}

follow_marzban_logs() {
    $COMPOSE -f $COMPOSE_FILE -p "$APP_NAME" logs -f
}

marzban_cli() {
    $COMPOSE -f $COMPOSE_FILE -p "$APP_NAME" exec -e CLI_PROG_NAME="marzban cli" marzban marzban-cli "$@"
}


is_marzban_up() {
    if [ -z "$($COMPOSE -f $COMPOSE_FILE ps -q -a)" ]; then
        return 1
    else
        return 0
    fi
}

uninstall_command() {
    check_running_as_root
    # Check if marzban is installed
    if ! is_marzban_installed; then
        colorized_echo red "Marzban's not installed!"
        exit 1
    fi
    
    read -p "Do you really want to uninstall Marzban? (y/n) "
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        colorized_echo red "Aborted"
        exit 1
    fi
    
    detect_compose
    if is_marzban_up; then
        down_marzban
    fi
    uninstall_marzban_script
    uninstall_marzban
    uninstall_marzban_docker_images
    
    read -p "Do you want to remove Marzban's data files too ($DATA_DIR)? (y/n) "
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        colorized_echo green "Marzban uninstalled successfully"
    else
        uninstall_marzban_data_files
        colorized_echo green "Marzban uninstalled successfully"
    fi
}

uninstall_marzban_script() {
    if [ -f "/usr/local/bin/marzban" ]; then
        colorized_echo yellow "Removing marzban script"
        rm "/usr/local/bin/marzban"
    fi
}

uninstall_marzban() {
    if [ -d "$APP_DIR" ]; then
        colorized_echo yellow "Removing directory: $APP_DIR"
        rm -r "$APP_DIR"
    fi
}

uninstall_marzban_docker_images() {
    images=$(docker images | grep marzban | awk '{print $3}')
    
    if [ -n "$images" ]; then
        colorized_echo yellow "Removing Docker images of Marzban"
        for image in $images; do
            if docker rmi "$image" >/dev/null 2>&1; then
                colorized_echo yellow "Image $image removed"
            fi
        done
    fi
}

uninstall_marzban_data_files() {
    if [ -d "$DATA_DIR" ]; then
        colorized_echo yellow "Removing directory: $DATA_DIR"
        rm -r "$DATA_DIR"
    fi
}

restart_command() {
    help() {
        colorized_echo red "Usage: marzban restart [options]"
        echo
        echo "OPTIONS:"
        echo "  -h, --help        display this help message"
        echo "  -n, --no-logs     do not follow logs after starting"
    }
    
    local no_logs=false
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -n|--no-logs)
                no_logs=true
            ;;
            -h|--help)
                help
                exit 0
            ;;
            *)
                echo "Error: Invalid option: $1" >&2
                help
                exit 0
            ;;
        esac
        shift
    done
    
    # Check if marzban is installed
    if ! is_marzban_installed; then
        colorized_echo red "Marzban's not installed!"
        exit 1
    fi
    
    detect_compose
    
    down_marzban
    up_marzban
    if [ "$no_logs" = false ]; then
        follow_marzban_logs
    fi
    colorized_echo green "Marzban successfully restarted!"
}
logs_command() {
    help() {
        colorized_echo red "Usage: marzban logs [options]"
        echo ""
        echo "OPTIONS:"
        echo "  -h, --help        display this help message"
        echo "  -n, --no-follow   do not show follow logs"
    }
    
    local no_follow=false
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -n|--no-follow)
                no_follow=true
            ;;
            -h|--help)
                help
                exit 0
            ;;
            *)
                echo "Error: Invalid option: $1" >&2
                help
                exit 0
            ;;
        esac
        shift
    done
    
    # Check if marzban is installed
    if ! is_marzban_installed; then
        colorized_echo red "Marzban's not installed!"
        exit 1
    fi
    
    detect_compose
    
    if ! is_marzban_up; then
        colorized_echo red "Marzban is not up."
        exit 1
    fi
    
    if [ "$no_follow" = true ]; then
        show_marzban_logs
    else
        follow_marzban_logs
    fi
}

down_command() {
    
    # Check if marzban is installed
    if ! is_marzban_installed; then
        colorized_echo red "Marzban's not installed!"
        exit 1
    fi
    
    detect_compose
    
    if ! is_marzban_up; then
        colorized_echo red "Marzban's already down"
        exit 1
    fi
    
    down_marzban
}

cli_command() {
    # Check if marzban is installed
    if ! is_marzban_installed; then
        colorized_echo red "Marzban's not installed!"
        exit 1
    fi
    
    detect_compose
    
    if ! is_marzban_up; then
        colorized_echo red "Marzban is not up."
        exit 1
    fi
    
    marzban_cli "$@"
}

up_command() {
    help() {
        colorized_echo red "Usage: marzban up [options]"
        echo ""
        echo "OPTIONS:"
        echo "  -h, --help        display this help message"
        echo "  -n, --no-logs     do not follow logs after starting"
    }
    
    local no_logs=false
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -n|--no-logs)
                no_logs=true
            ;;
            -h|--help)
                help
                exit 0
            ;;
            *)
                echo "Error: Invalid option: $1" >&2
                help
                exit 0
            ;;
        esac
        shift
    done
    
    # Check if marzban is installed
    if ! is_marzban_installed; then
        colorized_echo red "Marzban's not installed!"
        exit 1
    fi
    
    detect_compose
    
    if is_marzban_up; then
        colorized_echo red "Marzban's already up"
        exit 1
    fi
    
    up_marzban
    if [ "$no_logs" = false ]; then
        follow_marzban_logs
    fi
}

update_command() {
    check_running_as_root
    # Check if marzban is installed
    if ! is_marzban_installed; then
        colorized_echo red "Marzban's not installed!"
        exit 1
    fi
    
    detect_compose
    
    update_marzban_script
    colorized_echo blue "Pulling latest version"
    update_marzban
    
    colorized_echo blue "Restarting Marzban's services"
    down_marzban
    up_marzban
    
    colorized_echo blue "Marzban updated successfully"
}

update_marzban_script() {
    FETCH_REPO="naymintun800/Marzban-scripts"
    SCRIPT_URL="https://github.com/$FETCH_REPO/raw/master/marzban.sh"
    colorized_echo blue "Updating marzban script"
    curl -sSL $SCRIPT_URL | install -m 755 /dev/stdin /usr/local/bin/marzban
    colorized_echo green "marzban script updated successfully"
}

update_marzban() {
    $COMPOSE -f $COMPOSE_FILE -p "$APP_NAME" pull
}

check_editor() {
    if [ -z "$EDITOR" ]; then
        if command -v nano >/dev/null 2>&1; then
            EDITOR="nano"
            elif command -v vi >/dev/null 2>&1; then
            EDITOR="vi"
        else
            detect_os
            install_package nano
            EDITOR="nano"
        fi
    fi
}


edit_command() {
    detect_os
    check_editor
    if [ -f "$COMPOSE_FILE" ]; then
        $EDITOR "$COMPOSE_FILE"
    else
        colorized_echo red "Compose file not found at $COMPOSE_FILE"
        exit 1
    fi
}

edit_env_command() {
    detect_os
    check_editor
    if [ -f "$ENV_FILE" ]; then
        $EDITOR "$ENV_FILE"
    else
        colorized_echo red "Environment file not found at $ENV_FILE"
        exit 1
    fi
}

ssl_cert_command() {
    check_running_as_root

    # Check if marzban is installed
    if ! is_marzban_installed; then
        colorized_echo red "Marzban is not installed. Please install Marzban first."
        exit 1
    fi

    # Check if we're on Ubuntu (SSL setup is only supported on Ubuntu in this script)
    detect_os
    if [[ "$OS" != "Ubuntu"* ]]; then
        colorized_echo red "SSL certificate generation is currently only supported on Ubuntu."
        exit 1
    fi

    colorized_echo blue "====================================="
    colorized_echo blue "    SSL Certificate Management"
    colorized_echo blue "====================================="

    # Parse command line arguments
    local domains=""
    local force_wildcard=false
    local force_standard=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --domain)
                domains="$2"
                shift 2
                ;;
            --wildcard)
                force_wildcard=true
                shift
                ;;
            --standard)
                force_standard=true
                shift
                ;;
            *)
                colorized_echo red "Unknown option: $1"
                colorized_echo yellow "Usage: marzban ssl-cert [--domain domain1,domain2] [--wildcard|--standard]"
                exit 1
                ;;
        esac
    done

    # If domains not provided via command line, prompt for them
    if [ -z "$domains" ]; then
        prompt_for_domains
    else
        IFS=',' read -ra DOMAIN_ARRAY <<< "$domains"
        DOMAIN="${DOMAIN_ARRAY[0]}"

        # Determine certificate type if not forced
        if [ "$force_wildcard" = true ] && [ "$force_standard" = true ]; then
            colorized_echo red "Cannot use both --wildcard and --standard options together."
            exit 1
        elif [ "$force_wildcard" = true ]; then
            USE_WILDCARD=true
            prompt_for_cloudflare_credentials
        elif [ "$force_standard" = true ]; then
            USE_WILDCARD=false
        else
            # Ask user for preference
            colorized_echo blue "====================================="
            colorized_echo blue "      Wildcard SSL Option"
            colorized_echo blue "====================================="
            colorized_echo yellow "Do you want to generate a wildcard+SAN SSL certificate?"
            colorized_echo cyan "Wildcard+SAN certificate covers ALL domains you entered AND all their subdomains."
            colorized_echo cyan "This creates a single certificate for maximum compatibility."
            colorized_echo cyan "This requires Cloudflare DNS API credentials."
            echo
            while true; do
                read -p "Generate wildcard SSL certificates? (y/n): " wildcard_choice
                case $wildcard_choice in
                    [Yy]* )
                        USE_WILDCARD=true
                        prompt_for_cloudflare_credentials
                        break
                        ;;
                    [Nn]* )
                        USE_WILDCARD=false
                        colorized_echo green "Using standard SSL certificates with SAN for multiple domains."
                        break
                        ;;
                    * )
                        colorized_echo red "Please answer yes (y) or no (n)."
                        ;;
                esac
            done
        fi
    fi

    # Install SSL dependencies
    install_ssl_dependencies

    # Generate certificates
    generate_ssl_certs

    # Configure environment and services
    configure_env_ssl
    configure_haproxy
    configure_ufw

    # Restart services
    colorized_echo blue "Restarting services to apply SSL configuration..."
    restart_services

    colorized_echo green "====================================="
    colorized_echo green "SSL certificates have been successfully generated and configured!"
    if [ "$USE_WILDCARD" = true ]; then
        colorized_echo green "Wildcard certificates are now active for your domains."
    else
        colorized_echo green "Standard SSL certificates with SAN are now active for your domains."
    fi
    colorized_echo green "====================================="
}

usage() {
    local script_name="${0##*/}"
    colorized_echo blue "=============================="
    colorized_echo magenta "           Marzban Help"
    colorized_echo blue "=============================="
    colorized_echo cyan "Usage:"
    echo "  ${script_name} [command]"
    echo

    colorized_echo cyan "Commands:"
    colorized_echo yellow "  up              $(tput sgr0)– Start services"
    colorized_echo yellow "  down            $(tput sgr0)– Stop services"
    colorized_echo yellow "  restart         $(tput sgr0)– Restart services"
    colorized_echo yellow "  status          $(tput sgr0)– Show status"
    colorized_echo yellow "  logs            $(tput sgr0)– Show logs"
    colorized_echo yellow "  cli             $(tput sgr0)– Marzban CLI"
    colorized_echo yellow "  install         $(tput sgr0)– Install Marzban"
    colorized_echo yellow "  update          $(tput sgr0)– Update to latest version"
    colorized_echo yellow "  uninstall       $(tput sgr0)– Uninstall Marzban"
    colorized_echo yellow "  install-script  $(tput sgr0)– Install Marzban script"
    colorized_echo yellow "  backup          $(tput sgr0)– Manual backup launch"
    colorized_echo yellow "  backup-service  $(tput sgr0)– Marzban Backupservice to backup to TG, and a new job in crontab"
    colorized_echo yellow "  core-update     $(tput sgr0)– Update/Change Xray core"
    colorized_echo yellow "  ssl-cert        $(tput sgr0)– Generate/Update SSL certificates (supports wildcard)"
    colorized_echo yellow "  edit            $(tput sgr0)– Edit docker-compose.yml (via nano or vi editor)"
    colorized_echo yellow "  edit-env        $(tput sgr0)– Edit environment file (via nano or vi editor)"
    colorized_echo yellow "  help            $(tput sgr0)– Show this help message"
    
    
    echo
    colorized_echo cyan "SSL Certificate Examples:"
    colorized_echo magenta "  marzban ssl-cert                                    # Interactive mode"
    colorized_echo magenta "  marzban ssl-cert --domain example.com              # Standard SSL for single domain"
    colorized_echo magenta "  marzban ssl-cert --domain example.com,sub.example.com --standard  # Standard SSL with SAN"
    colorized_echo magenta "  marzban ssl-cert --domain example.com,another.com --wildcard      # Single Wildcard+SAN SSL"
    colorized_echo magenta "    # Wildcard+SAN covers: *.example.com, example.com, *.another.com, another.com"
    echo
    colorized_echo cyan "Directories:"
    colorized_echo magenta "  App directory: $APP_DIR"
    colorized_echo magenta "  Data directory: $DATA_DIR"
    colorized_echo blue "================================"
    echo
}

case "$1" in
    up)
        shift; up_command "$@";;
    down)
        shift; down_command "$@";;
    restart)
        shift; restart_command "$@";;
    status)
        shift; status_command "$@";;
    logs)
        shift; logs_command "$@";;
    cli)
        shift; cli_command "$@";;
    backup)
        shift; backup_command "$@";;
    backup-service)
        shift; backup_service "$@";;
    install)
        shift; install_command "$@";;
    update)
        shift; update_command "$@";;
    uninstall)
        shift; uninstall_command "$@";;
    install-script)
        shift; install_marzban_script "$@";;
    core-update)
        shift; update_core_command "$@";;
    ssl-cert)
        shift; ssl_cert_command "$@";;
    edit)
        shift; edit_command "$@";;
    edit-env)
        shift; edit_env_command "$@";;
    help|*)
        usage;;
esac
