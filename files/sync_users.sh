#!/usr/bin/env bash
set -e

BASE="/opt/maritima"
DB="$BASE/users.db"
LOG="$BASE/logs/sync.log"

mkdir -p "$BASE/logs"
touch "$LOG"

NOW_DATE=$(date +%Y-%m-%d)
NOW_TIME=$(date +%s)

echo "=== SYNC $(date) ===" >> "$LOG"

# ===============================
# 1. MAPA DE USUÁRIOS VÁLIDOS
# ===============================
declare -A VALID_USERS

while IFS=: read -r u p exp lim extra; do
    [[ -z "$u" ]] && continue
    VALID_USERS["$u"]=1
done < "$DB"

# ===============================
# 2. REMOVER USUÁRIOS DO SISTEMA
#    QUE NÃO ESTÃO NO DB
# ===============================
while IFS=: read -r SYSUSER _ SYSUID _ _ _; do

    # Ignorar sistema
    [[ "$SYSUID" -lt 1000 ]] && continue

    # Se não existe no DB → DELETE
    if [[ -z "${VALID_USERS[$SYSUSER]}" ]]; then
        echo "[DEL] usuário fora do DB: $SYSUSER" >> "$LOG"
        pkill -u "$SYSUSER" 2>/dev/null || true
        userdel -r "$SYSUSER" 2>/dev/null || true
    fi

done < /etc/passwd

# ===============================
# 3. REMOVER USUÁRIOS EXPIRADOS
# ===============================
while IFS=: read -r u p exp lim extra; do
    [[ -z "$u" ]] && continue

    # Vitalício / teste
    [[ "$exp" == "NUNCA" || "$exp" == "TESTE" ]] && continue

    # Expiração por data
    if [[ "$exp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        EXP_TIME=$(date -d "$exp" +%s 2>/dev/null || echo 0)

        if [[ "$EXP_TIME" -lt "$NOW_TIME" ]]; then
            echo "[EXP] usuário expirado: $u ($exp)" >> "$LOG"
            pkill -u "$u" 2>/dev/null || true
            userdel -r "$u" 2>/dev/null || true
            sed -i "/^$u:/d" "$DB"
        fi
    fi
done < "$DB"

echo "=== FIM SYNC ===" >> "$LOG"

