#!/bin/bash

DB_HOST="sql12.freesqldatabase.com"
DB_PORT="3306"
DB_USER="sql12773185"
DB_PASS="vT3SfyZpSC"
DB_NAME="sql12773185"

logged_in_user_id=""
logged_in_username=""

# Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

function mysql_exec() {
    mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -se "$1"
}

function banner() {
    echo -e "${CYAN}"
    echo "==========================================="
    echo "        💬 Terminal Chat Application       "
    echo "==========================================="
    echo -e "${NC}"
}

function pause() {
    echo -e "\n${YELLOW}Press Enter to continue...${NC}"
    read
}

function generate_otp() {
    echo $((100000 + RANDOM % 900000))
}

function send_otp_email() {
    local email=$1
    local otp=$2
    echo -e "Subject: OTP Verification\n\nYour OTP is: $otp" | msmtp "$email"
}

function signup() {
    clear
    banner
    echo -e "${BLUE}🔐 Sign Up with Email OTP Verification${NC}"
    read -p "Username: " username
    read -p "Email: " email
    read -s -p "Password: " password
    echo

    # Check if user exists
    existing=$(mysql_exec "SELECT id FROM users01 WHERE username='$username';")
    if [[ -n "$existing" ]]; then
        echo -e "${RED}❌ Username already exists.${NC}"
        pause
        return
    fi

    otp=$(generate_otp)
    send_otp_email "$email" "$otp"
    echo -e "${YELLOW}📧 OTP sent to $email${NC}"

    read -p "Enter the OTP: " user_otp

    if [[ "$user_otp" != "$otp" ]]; then
        echo -e "${RED}❌ Incorrect OTP. Signup failed.${NC}"
    else
        mysql_exec "INSERT INTO users01 (username, email, password) VALUES ('$username', '$email', '$password');"
        echo -e "${GREEN}✅ Successfully signed up!${NC}"
    fi
    pause
}

function login() {
    clear
    banner
    echo -e "${BLUE}🔑 Login${NC}"
    read -p "Username: " username
    read -s -p "Password: " password
    echo

    user_id=$(mysql_exec "SELECT id FROM users01 WHERE username='$username' AND password='$password';")
    if [ -z "$user_id" ]; then
        echo -e "${RED}❌ Incorrect username or password.${NC}"
        pause
        return 1
    else
        logged_in_user_id=$user_id
        logged_in_username=$username
        echo -e "${GREEN}✅ Logged in as $username${NC}"
        pause
        return 0
    fi
}

function list_users() {
    clear
    banner
    echo -e "${CYAN}👥 Available Users to Chat:${NC}"
    users=$(mysql_exec "SELECT id, username FROM users01 WHERE id != $logged_in_user_id;")

    if [ -z "$users" ]; then
        echo -e "${YELLOW}No other users found!${NC}"
        pause
        return
    fi

    declare -A user_map
    index=1
    while IFS=$'\t' read -r id name; do
        echo "$index) $name"
        user_map[$index]=$id
        ((index++))
    done <<< "$users"

    echo -ne "${BLUE}Choose a user number to chat with (0 to back): ${NC}"
    read choice

    if [ "$choice" == "0" ]; then
        return
    elif [ -n "${user_map[$choice]}" ]; then
        chat_menu "${user_map[$choice]}"
    else
        echo -e "${RED}❌ Invalid selection.${NC}"
        pause
    fi
}

function chat_menu() {
    receiver_id=$1
    receiver_name=$(mysql_exec "SELECT username FROM users01 WHERE id = $receiver_id;")

    while true; do
        clear
        banner
        echo -e "${BLUE}💬 Chat with $receiver_name${NC}"
        echo "1) 📤 Send Message"
        echo "2) 📥 View Messages"
        echo "3) 🔙 Back"
        read -p "Choose: " option

        case "$option" in
            1)
                read -p "Enter your message: " msg
                mysql_exec "INSERT INTO messages01 (sender_id, receiver_id, message) VALUES ($logged_in_user_id, $receiver_id, '$msg');"
                echo -e "${GREEN}✅ Message sent!${NC}"
                pause
                ;;
            2)
                clear
                banner
                echo -e "${YELLOW}📜 Chat History with $receiver_name:${NC}"
                mysql_exec "SELECT u.username, m.message, m.timestamp FROM messages01 m JOIN users01 u ON m.sender_id=u.id WHERE (sender_id=$logged_in_user_id AND receiver_id=$receiver_id) OR (sender_id=$receiver_id AND receiver_id=$logged_in_user_id) ORDER BY timestamp;" | while IFS=$'\t' read -r sender msg time; do
                    echo -e "${CYAN}[$time] $sender:${NC} $msg"
                done
                pause
                ;;
            3) return ;;
            *) echo -e "${RED}❌ Invalid option.${NC}"; pause ;;
        esac
    done
}
send_otp() {
    email=$1
    otp=$((100000 + RANDOM % 900000))
    expiry=$(date -d "+5 minutes" +"%Y-%m-%d %H:%M:%S")

    # Send OTP via msmtp
    echo -e "Subject: OTP for Password Reset\n\nYour OTP is: $otp\nExpires in 5 minutes." | msmtp "$email"
}

forgot_password() {
    read -p "Enter your registered email: " email

    # Check if email exists
    user_count=$(mysql_exec "SELECT COUNT(*) FROM users WHERE email='$email';")

    if [[ "$user_count" -eq 1 ]]; then
        send_otp "$email"
        echo "📧 OTP sent to $email"

        read -p "Enter the OTP: " entered_otp
        result=$(mysql -h $DB_HOST -P 3306 -u $DB_USER -p$DB_PASS $DB_NAME -sse \
        "SELECT COUNT(*) FROM users WHERE email='$email' AND otp_code='$entered_otp' AND otp_expiry > NOW();")

        if [[ "$result" -eq 1 ]]; then
            echo "✅ OTP verified"
            while true; do
                read -s -p "Enter new password: " new_pass
                echo
                read -s -p "Confirm password: " confirm_pass
                echo
                if [[ "$new_pass" == "$confirm_pass" ]]; then
                    mysql -h $DB_HOST -P 3306 -u $DB_USER -p$DB_PASS $DB_NAME -e \
                    "UPDATE users SET password='$new_pass', otp_code=NULL, otp_expiry=NULL WHERE email='$email';"
                    echo -e "\n🔐 Password changed successfully."
                    break
                else
                    echo -e "\n❌ Passwords do not match. Try again."
                fi
            done
        else
            echo "❌ Invalid or expired OTP."
        fi
    else
        echo "❌ Email not found."
    fi
}

function main_menu() {
    while true; do
        clear
        banner
        echo -e "${CYAN}Welcome, $logged_in_username 👋${NC}"
        echo "1) 💬 Chat with a user"
        echo "2) 👥 Group Chat"
        echo "3) 🚪 Logout"
        read -p "Choose: " option

        case "$option" in
            1) list_users ;;
            2) source ./groupchat.sh ;;
            3) logged_in_user_id=""; logged_in_username=""; return ;;
            *) echo -e "${RED}Invalid option.${NC}"; pause ;;
        esac
    done
}

while true; do
    clear
    banner
    echo "1) 🔑 Login"
    echo "2) 📝 Signup"
    echo "3) 🔁 Forgot Password"
    echo "4) ❌ Exit"
    echo
    read -p "Choose: " option

    case "$option" in
        1) login && main_menu ;;
        2) signup ;;
        3) forgot_password ;;
        4) echo -e "${YELLOW}👋 See you next time!${NC}"; exit ;;
        *) echo -e "${RED}❗ Invalid input.${NC}"; pause ;;
    esac
done
# Entry Menu
