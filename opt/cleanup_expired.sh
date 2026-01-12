#!/bin/bash
DB="/opt/maritima/users.db"
LOG="/opt/maritima/login_attempts.log"
TODAY=$(date +%Y-%m-%d)

[[ -f "$DB" ]] || exit 0

temp_file="${DB}.temp"
> "$temp_file"

while IFS=: read -r u p e l uuid; do
    [[ -z "$u" ]] && continue
    
    # TESTE com data/hora
    if [[ "$e" == "TESTE" ]] && [[ "$uuid" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}$ ]]; then
        exp_seconds=$(date -d "$uuid" +%s 2>/dev/null || echo 0)
        now_seconds=$(date +%s)
        
        if [[ $exp_seconds -gt 0 ]] && [[ $now_seconds -ge $exp_seconds ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') - CRON: TESTE expirado $u" >> "$LOG"
            userdel "$u" 2>/dev/null
            pkill -u "$u" 2>/dev/null
            continue
        fi
    # Data normal
    elif [[ "$e" != "NUNCA" ]] && [[ "$e" != "TESTE" ]] && [[ "$e" < "$TODAY" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - CRON: Expirado $u ($e)" >> "$LOG"
        userdel "$u" 2>/dev/null
        pkill -u "$u" 2>/dev/null
        continue
    fi
    
    echo "$u:$p:$e:$l:$uuid" >> "$temp_file"
    
done < "$DB"

mv "$temp_file" "$DB" 2>/dev/null
