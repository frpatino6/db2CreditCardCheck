#!/bin/bash

# Configurar el entorno de DB2
source /home/db2inst2/sqllib/db2profile

# Verificar si se pasaron suficientes parámetros
if [ $# -lt 4 ]; then
    echo "Usage: $0 [SCHEMA_NAME1] [SCHEMA_NAME2] ... [DB_NAME] [DB_USER] [DB_PASSWORD]"
    exit 1
fi

# Capturar los parámetros en variables
SCHEMAS="${@:1:$#-3}"
DB_NAME="${@:$#-2:1}"
USER="${@:$#-1:1}"
PASSWORD="${@:$#}"

echo "Starting script execution..."

# Obtener la ruta del script actual
SCRIPT_PATH=$(dirname "$0")

# Archivo temporal para almacenar resultados
TEMP_RESULTS_FILE="$SCRIPT_PATH/results_temp.txt"
echo "Schema,Table,Column,Value" > "$TEMP_RESULTS_FILE"

# Archivo de resultados finales
RESULTS_FILE="$SCRIPT_PATH/credit_card_results.txt"
echo -e "Schema\t\tTable\t\tColumn\t\tMasked Value" > "$RESULTS_FILE"
echo -e "----------------------------------------------------------" >> "$RESULTS_FILE"

echo "Connecting to database $DB_NAME with user $USER..."
# Conectar a la base de datos
db2 connect to "$DB_NAME" user "$USER" using "$PASSWORD"
if [ $? -ne 0 ]; then
    echo "Failed to connect to database."
    exit 1
fi

echo "Connected to database $DB_NAME."

# Función para extraer posibles números de tarjetas de crédito de un texto
extract_credit_card_numbers() {
    echo "$1" | grep -oE '[0-9]{13,19}'
}

# Función para enmascarar el número de tarjeta de crédito
mask_credit_card() {
    local card_number="$1"
    local masked="${card_number:0:4}****${card_number: -4}"
    echo "$masked"
}

# Iterar sobre cada esquema proporcionado como parámetro
for SCHEMA_NAME in $SCHEMAS; do
    echo "Processing schema: $SCHEMA_NAME"

    # Obtener la lista de tablas y columnas para el esquema actual
    echo "Retrieving table and column lists for schema $SCHEMA_NAME..."
    db2 -x "SELECT TABNAME, COLNAME FROM SYSCAT.COLUMNS WHERE TABSCHEMA = '$SCHEMA_NAME' AND (TYPENAME = 'CLOB' OR (TYPENAME = 'VARCHAR' AND LENGTH > 13) OR (TYPENAME LIKE 'NUMERIC%' AND LENGTH >= 11) OR (TYPENAME = 'BIGINT' AND LENGTH >= 11) OR (TYPENAME LIKE 'DECIMAL%' AND LENGTH >= 11) OR (TYPENAME = 'MONEY' AND LENGTH >= 11))" > table_columns.txt

    if [ $? -ne 0 ]; then
        echo "Failed to retrieve table and column lists for schema $SCHEMA_NAME."
        continue
    fi

    # Procesar cada tabla y columna
    while IFS= read -r line; do
        TABLE=$(echo "$line" | awk '{print $1}')
        COLUMN=$(echo "$line" | awk '{print $2}')
        echo "TABLE_COLUMNS output: $TABLE $COLUMN"

        # Generar y ejecutar la consulta para verificar cada valor de la columna
        SQL="SELECT $COLUMN FROM $SCHEMA_NAME.$TABLE"
        echo "Executing SQL: $SQL"
        db2 -x "$SQL" > column_values.txt

        if [ $? -ne 0 ]; then
            echo "Failed to execute SQL: $SQL."
            continue
        fi

        while IFS= read -r VALUE; do
            VALUE=$(echo "$VALUE" | tr -d ' ')
            # echo "Checking value: $VALUE"

            # Extraer posibles números de tarjetas de crédito
            CARD_NUMBERS=$(extract_credit_card_numbers "$VALUE")

            for CARD_NUMBER in $CARD_NUMBERS; do
                # Llamar a LUHN_CHECK.sh y capturar el resultado
                CHECK_RESULT=$(bash LUHN_CHECK.sh "$CARD_NUMBER")
                # echo "LUHN_CHECK result for $CARD_NUMBER: $CHECK_RESULT" # Mensaje de depuración

                if [ "$CHECK_RESULT" -eq 1 ]; then
                    # Enmascarar el valor de la tarjeta de crédito
                    MASKED_VALUE=$(mask_credit_card "$CARD_NUMBER")
                    echo "$SCHEMA_NAME,$TABLE,$COLUMN,$MASKED_VALUE" >> "$TEMP_RESULTS_FILE"
                fi
            done
        done < column_values.txt
    done < table_columns.txt
done

# Desconectar de la base de datos
echo "Disconnecting from database..."
db2 connect reset

# Verificar si el archivo de resultados temporales tiene datos
echo "Checking temporary results file..."
cat "$TEMP_RESULTS_FILE" >> "$RESULTS_FILE"

echo "Flat file with results generated: $RESULTS_FILE"

# Eliminar archivos temporales
rm -f table_columns.txt column_values.txt results_temp.txt

echo "Script execution completed."

