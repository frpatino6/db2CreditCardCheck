#!/bin/bash

# Obtener la cadena de entrada desde el parámetro
input_string="$1"

# Limpiar la cadena de entrada, dejando solo los dígitos
clean_card_number=$(echo "$input_string" | tr -cd '[:digit:]')

# Validar la longitud del número limpio
len=${#clean_card_number}
if [ $len -lt 13 ] || [ $len -gt 19 ]; then
    echo 0
    exit 0
fi

# Variables iniciales para la lógica de Luhn
i=$len
sum=0
odd=0

# Lógica de Luhn
while [ $i -gt 0 ]; do
    ((i--))
    digit=${clean_card_number:i:1}
    digit=$((digit))

    if [ $odd -eq 1 ]; then
        digit=$((digit * 2))
        if [ $digit -gt 9 ]; then
            digit=$((digit - 9))
        fi
        odd=0
    else
        odd=1
    fi

    sum=$((sum + digit))
done

mod=$((sum % 10))
if [ $mod -eq 0 ]; then
    echo 1
else
    echo 0
fi

exit 0

